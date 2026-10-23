// The still.fail client core in Hermes, for the macOS and iOS hosts (core_api.h; core/README.md): the same engine
// still.fail's Android app runs it in (React Native 0.81.4's Hermes, its JSI; apps/android/core/src/main/cpp/engine.cpp,
// whose loop this is, without JNI), on the same Rust shell (client/shell), the same bytecode (core.hbc: scripts/core.sh
// hermes). Built by scripts/core.sh engine into out/core/<target>/libmbui_core.a (Objective-C++, ARC), which the apps
// with the core link with Hermes's framework (scripts/core.sh hermes-apple fetches it).
//
// One thread runs the core, with 8 MB of stack (the core's parsers recurse; Android's engine gives Hermes the same): the
// runtime, its tasks (what the UI says, the shell's answers, the host's own answers) in order, its timers on
// CLOCK_MONOTONIC (which on Apple's systems goes on while the machine sleeps, as Android's CLOCK_BOOTTIME: a 10 s wait
// begun before a sleep is over after it), and the microtasks drained after each.
//
// The script's `__native` is ember's HermesNative (hosts/hermes-globals.ts; bytes as ArrayBuffers both ways), its calls
// going to the shell (HTTP, still.fail cloud's socket, files and the accounts' SQLite, TCP, iroh), whose answers come
// from its threads and are posted here as tasks. What only an app can do is not the shell's: `listen.*` (a login's
// loopback listener) is answered here, on apple_listen.m; `secure.*` here too (the Keychain, or files for a build that
// can't use it). A JS error that escapes, or a bug the core reports, ends the core as on Android: `{"fatal": …}` to the
// UI, and the host starts another.
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <algorithm>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>

#include <hermes/hermes.h>
#include <jsi/jsi.h>

#include "core_api.h"
#include "listen_api.h"
#include "electron_sealed.h"

namespace jsi = facebook::jsi;

extern "C" {
typedef void (*sf_complete)(void *, uint64_t, const uint8_t *, size_t, const uint8_t *, size_t, const uint8_t *, size_t, uint8_t);
void *sf_shell_start(const char *data_dir, sf_complete complete, void *ctx);
void sf_shell_call(const void *shell, uint64_t id, const char *op, const uint8_t *json, size_t json_len, const uint8_t *bytes, size_t bytes_len, uint8_t has_bytes);
uint8_t *sf_shell_call_sync(const void *shell, const char *op, const uint8_t *json, size_t json_len, size_t *out_len);
void sf_free(uint8_t *ptr, size_t len);
void sf_shell_stop(void *shell);
int32_t sf_utc_offset_min(double at_ms);
}

#if TARGET_OS_IPHONE
static const char *const kOS = "ios";
#else
static const char *const kOS = "macos";
#endif

namespace {

double clock_ms(clockid_t c) {
  timespec t{};
  clock_gettime(c, &t);
  return double(t.tv_sec) * 1000.0 + double(t.tv_nsec) / 1e6;
}

/// The timers' clock: on Darwin CLOCK_MONOTONIC counts the time asleep too.
double timer_ms() { return clock_ms(CLOCK_MONOTONIC); }

/// A JSON string literal of `s` (for `{"fatal": …}`).
std::string quote(const std::string &s) {
  std::string out = "\"";
  for (unsigned char c : s) {
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (c < 0x20) {
          char buf[8];
          snprintf(buf, sizeof buf, "\\u%04x", c);
          out += buf;
        } else out += char(c);
    }
  }
  return out + "\"";
}

/// Bytes the runtime keeps as its script.
class Bytes : public jsi::Buffer {
 public:
  explicit Bytes(std::string data) : data_(std::move(data)) {}
  size_t size() const override { return data_.size(); }
  const uint8_t *data() const override { return reinterpret_cast<const uint8_t *>(data_.data()); }

 private:
  std::string data_;
};

/// What the shell answers through. Stopping the shell (tokio's shutdown_background) does not wait for what it is
/// doing, so an answer can come after the core is gone: the shell holds this, not the core, and stopping closes it
/// under its lock (as the Android engine's Gate). Never freed: a few bytes per restart.
struct Gate {
  std::mutex mutex;
  bool open = true;
};

using Task = std::function<void(jsi::Runtime &)>;

/// The one core. `tasks`, `timers`, `dues` and `stopping` under `mutex`; the rest is the core thread's, but for what
/// mb_core_start sets before the thread starts and mb_core_stop reads after it ended.
struct Core {
  pthread_t thread{};
  bool running = false;
  Gate *gate = nullptr;
  void *shell = nullptr;
  std::mutex mutex;
  std::condition_variable wake;
  std::deque<Task> tasks;
  std::unordered_map<uint64_t, double> timers;
  std::multimap<double, uint64_t> dues;
  bool stopping = false;
  bool dead = false;
  mb_core_message_fn on_message = nullptr;
  void *ctx = nullptr;
  std::string dataDir, cloud;
  bool beta = false;
  double client = 1;  // the UI's, as `connect` gave it (the core's thread)
};

Core C;

void say(const char *json, size_t len, const uint8_t *bytes, size_t blen) {
  if (C.on_message) C.on_message(json, len, bytes, blen, C.ctx);
}

void fatal(const std::string &reason) {
  if (C.dead) return;
  C.dead = true;
  fprintf(stderr, "[core] fatal: %s\n", reason.c_str());
  std::string json = "{\"fatal\":" + quote(reason.empty() ? "the core failed" : reason) + "}";
  say(json.data(), json.size(), nullptr, 0);
}

/// A task for the core's thread, in order with the others; from any thread. Dropped once the core is stopping.
void post(Task task) {
  {
    std::lock_guard<std::mutex> lock(C.mutex);
    if (C.stopping || !C.running) return;
    C.tasks.push_back(std::move(task));
  }
  C.wake.notify_one();
}

jsi::Object stillfail(jsi::Runtime &rt) { return rt.global().getPropertyAsObject(rt, "__stillfail"); }

jsi::Object array_buffer(jsi::Runtime &rt, const void *data, size_t size) {
  jsi::Object buffer = rt.global().getPropertyAsFunction(rt, "ArrayBuffer").callAsConstructor(rt, double(size)).asObject(rt);
  if (size > 0) std::memcpy(buffer.getArrayBuffer(rt).data(rt), data, size);
  return buffer;
}

/// MB_CORE_TRACE=1: each operation and its answer on stderr.
bool tracing() {
  static int on = -1;
  if (on < 0) on = getenv("MB_CORE_TRACE") != nullptr;
  return on != 0;
}

/// An answer to the core's call `id` (the shell's, or the host's own): a task. `error` empty when it succeeded.
void completed(uint64_t id, std::string json, std::string error, std::string bytes, bool has_bytes) {
  if (tracing())
    fprintf(stderr, "[core trace] <- %llu %s%s\n", (unsigned long long)id,
            error.empty() ? json.substr(0, 120).c_str() : ("error " + error).c_str(),
            has_bytes ? (" +" + std::to_string(bytes.size()) + " bytes").c_str() : "");
  post([id, json = std::move(json), error = std::move(error), bytes = std::move(bytes), has_bytes](jsi::Runtime &rt) {
    jsi::Value j = error.empty() ? jsi::Value(jsi::String::createFromUtf8(rt, json)) : jsi::Value::null();
    jsi::Value e = error.empty() ? jsi::Value::null() : jsi::Value(jsi::String::createFromUtf8(rt, error));
    jsi::Value b = has_bytes ? jsi::Value(array_buffer(rt, bytes.data(), bytes.size())) : jsi::Value::undefined();
    jsi::Object sf = stillfail(rt);
    sf.getPropertyAsFunction(rt, "complete").callWithThis(rt, sf, jsi::Value(double(id)), j, e, b);
  });
}

void on_complete(void *ctx, uint64_t id, const uint8_t *json, size_t jl, const uint8_t *error, size_t el, const uint8_t *bytes, size_t bl, uint8_t has) {
  auto *gate = static_cast<Gate *>(ctx);
  std::lock_guard<std::mutex> lock(gate->mutex);
  if (!gate->open) return;
  completed(id, std::string(reinterpret_cast<const char *>(json), jl), std::string(reinterpret_cast<const char *>(error), el),
            has ? std::string(reinterpret_cast<const char *>(bytes), bl) : std::string(), has != 0);
}

}  // namespace

// ── the host's own answers, from Objective-C ──

static NSData *const_json(const char *s) { return [NSData dataWithBytes:s length:strlen(s)]; }

static std::string std_of(NSData *d) { return d ? std::string(static_cast<const char *>(d.bytes), d.length) : std::string(); }

// An answer, later on the core's thread, as the shell's come.
static void answer_later(double cid, NSData *json, NSString *error, NSData *bytes) {
  completed(uint64_t(cid), error ? std::string() : std_of(json), error ? std::string(error.UTF8String ?: "error") : std::string(), std_of(bytes),
            !error && bytes != nil);
}

// ── secure.* (ember hosts/bridge.ts; Android's Keystore) ──
//   secure.get {key, user, reason} → {} + the bytes, or {none: true}; secure.set {key, user} + the bytes → {};
//   secure.delete {key} → {}; secure.ask {reason}: unsupported.
// What the core keeps out of the files it syncs (the lock's signing seed, a vault's key): in the Keychain, as a
// generic password per data directory and key, readable once the device is unlocked after a restart and never with a
// dialog (none can be answered on a station's locked screen: it fails instead). `user` (asking the person, Touch ID or
// Face ID) is not offered yet. MBUI_KEYS_IN_FILES=1 keeps them as files of `<data>/secure` instead (0600), for unsigned
// development builds on macOS, which a Keychain item made by one build would ask about when the next build reads it.
// (The iOS simulator's Keychain needs no signing beyond the ad hoc one: there it is the Keychain.)

static NSString *secure_dir;

static NSString *secure_path(NSString *key) {
  NSMutableString *hex = [NSMutableString string];
  NSData *k = [key dataUsingEncoding:NSUTF8StringEncoding];
  const uint8_t *b = static_cast<const uint8_t *>(k.bytes);
  for (NSUInteger i = 0; i < k.length; i++) [hex appendFormat:@"%02x", b[i]];
  return [secure_dir stringByAppendingPathComponent:hex];
}

static BOOL keys_in_files(void) {
  const char *v = getenv("MBUI_KEYS_IN_FILES");
  return v && *v && strcmp(v, "0") != 0;
}

// (kSecUseAuthenticationUIFail, deprecated for LAContext.interactionNotAllowed, is what also keeps macOS's legacy
// keychain from asking whether this build may read an item another build made: kept, as it was with JavaScriptCore)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static NSMutableDictionary *keychain_query(NSString *key) {
  return [@{
    (id)kSecClass : (id)kSecClassGenericPassword,
    (id)kSecAttrService : @"fail.still.mbui.core",
    (id)kSecAttrAccount : [NSString stringWithFormat:@"%@\n%@", secure_dir, key],
    (id)kSecUseAuthenticationUI : (id)kSecUseAuthenticationUIFail,
  } mutableCopy];
}
#pragma clang diagnostic pop

// A key still.fail's desktop app (Electron's) kept, where this app is built in its place and so keeps its data where
// that one did (src/sfcore/apple_engine.m: <that app's userData>/core): its file in userData/sealed, opened with the
// password Electron's safeStorage keeps in the Keychain ("<app> Safe Storage", the userData's name being the app's),
// which this app reads unasked as its designated requirement is that app's; asked about otherwise, it is not read
// (kSecUseAuthenticationUIFail) and the key is none (electron_sealed.h). nil when there is none.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static NSData *electron_sealed(NSString *key) {
  NSString *user_data = [[secure_dir stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
  NSString *file = [[user_data stringByAppendingPathComponent:@"sealed"] stringByAppendingPathComponent:electron_sealed_name(key)];
  NSData *blob = [NSData dataWithContentsOfFile:file];
  if (!blob) return nil;
  NSDictionary *q = @{
    (id)kSecClass : (id)kSecClassGenericPassword,
    (id)kSecAttrService : [user_data.lastPathComponent stringByAppendingString:@" Safe Storage"],
    (id)kSecReturnData : @YES,
    (id)kSecMatchLimit : (id)kSecMatchLimitOne,
    (id)kSecUseAuthenticationUI : (id)kSecUseAuthenticationUIFail,
  };
  CFTypeRef out = NULL;
  if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &out) != errSecSuccess) return nil;
  NSData *password = (__bridge_transfer NSData *)out;
  return electron_sealed_open(blob, password);
}
#pragma clang diagnostic pop

// One secure.* operation, done here and now: its answer's JSON and bytes, or why not (`*error`).
static void secure_do(NSString *op, NSDictionary *a, NSData *bytes, NSData **json_out, NSData **bytes_out, NSString **error) {
  *json_out = nil;
  *bytes_out = nil;
  *error = nil;
  NSString *key = [a isKindOfClass:[NSDictionary class]] ? a[@"key"] : nil;
  if ([op isEqualToString:@"secure.ask"] || ([a isKindOfClass:[NSDictionary class]] && [a[@"user"] boolValue])) {
    *error = @"unsupported";
    return;
  }
  if (![key isKindOfClass:[NSString class]] || key.length == 0) {
    *error = [op stringByAppendingString:@": no key"];
    return;
  }
  if (keys_in_files()) {
    NSString *path = secure_path(key);
    if ([op isEqualToString:@"secure.get"]) {
      NSData *d = [NSData dataWithContentsOfFile:path];
      *json_out = const_json(d ? "{}" : "{\"none\":true}");
      *bytes_out = d;
    } else if ([op isEqualToString:@"secure.set"]) {
      [[NSFileManager defaultManager] createDirectoryAtPath:secure_dir withIntermediateDirectories:YES
                                                 attributes:@{NSFilePosixPermissions : @0700} error:nil];
      BOOL ok = [bytes ?: [NSData data] writeToFile:path options:NSDataWritingAtomic error:nil];
      if (ok) [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions : @0600} ofItemAtPath:path error:nil];
      if (ok) *json_out = const_json("{}");
      else *error = @"secure.set: not written";
    } else if ([op isEqualToString:@"secure.delete"]) {
      [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
      *json_out = const_json("{}");
    } else {
      *error = @"unsupported";
    }
    return;
  }
  NSMutableDictionary *q = keychain_query(key);
  if ([op isEqualToString:@"secure.get"]) {
    q[(id)kSecReturnData] = @YES;
    q[(id)kSecMatchLimit] = (id)kSecMatchLimitOne;
    CFTypeRef out = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &out);
    if (st == errSecSuccess) {
      *json_out = const_json("{}");
      *bytes_out = (__bridge_transfer NSData *)out;
    } else if (st == errSecItemNotFound) {
      // none here yet: still.fail's desktop app's, where this app is built in its place, sealed here again
      NSData *old = electron_sealed(key);
      if (old) {
        NSMutableDictionary *add = keychain_query(key);
        add[(id)kSecValueData] = old;
        add[(id)kSecAttrAccessible] = (id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
        SecItemAdd((__bridge CFDictionaryRef)add, NULL);
        *json_out = const_json("{}");
        *bytes_out = old;
      } else {
        *json_out = const_json("{\"none\":true}");
      }
    } else {
      *error = [NSString stringWithFormat:@"secure.get: Keychain %d", (int)st];
    }
  } else if ([op isEqualToString:@"secure.set"]) {
    SecItemDelete((__bridge CFDictionaryRef)keychain_query(key));
    q[(id)kSecValueData] = bytes ?: [NSData data];
    q[(id)kSecAttrAccessible] = (id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    OSStatus st = SecItemAdd((__bridge CFDictionaryRef)q, NULL);
    if (st == errSecSuccess) *json_out = const_json("{}");
    else *error = [NSString stringWithFormat:@"secure.set: Keychain %d", (int)st];
  } else if ([op isEqualToString:@"secure.delete"]) {
    SecItemDelete((__bridge CFDictionaryRef)q);
    *json_out = const_json("{}");
  } else {
    *error = @"unsupported";
  }
}

static void core_secure(double cid, NSString *op, NSData *json, const uint8_t *bytes, size_t blen) {
  NSDictionary *a = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
  NSData *j = nil, *b = nil;
  NSString *error = nil;
  secure_do(op, a, bytes ? [NSData dataWithBytes:bytes length:blen] : nil, &j, &b, &error);
  answer_later(cid, j, error, b);
}

/// secure.set, secure.get (the same bytes back), secure.delete and secure.get again ({none}) done here as the core's
/// calls are (MBUI_SECURE_TEST=1 in src/coredemo; Android's CoreHost.secureTest), off the main thread, under the
/// running core's data directory (else a temporary one); the outcome on stderr as SECURE_TEST lines. Returns 1.
extern "C" int mb_core_secure_test(void) {
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    if (!secure_dir) secure_dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"mbui-secure-test"];
    double t0 = clock_ms(CLOCK_MONOTONIC);
    NSDictionary *k = @{@"key" : @"secure-test"};
    uint8_t raw[48];
    arc4random_buf(raw, sizeof raw);
    NSData *value = [NSData dataWithBytes:raw length:sizeof raw];
    NSData *j = nil, *b = nil;
    NSString *e = nil;
    BOOL ok = YES;
    secure_do(@"secure.set", k, value, &j, &b, &e);
    fprintf(stderr, "SECURE_TEST secure.set %s\n", e ? e.UTF8String : std_of(j).c_str());
    ok = ok && !e;
    secure_do(@"secure.get", k, nil, &j, &b, &e);
    BOOL same = [b isEqualToData:value];
    fprintf(stderr, "SECURE_TEST secure.get %s %lu bytes, %s\n", e ? e.UTF8String : std_of(j).c_str(), (unsigned long)b.length, same ? "the same" : "NOT the same");
    ok = ok && !e && same;
    secure_do(@"secure.delete", k, nil, &j, &b, &e);
    fprintf(stderr, "SECURE_TEST secure.delete %s\n", e ? e.UTF8String : std_of(j).c_str());
    ok = ok && !e;
    secure_do(@"secure.get", k, nil, &j, &b, &e);
    BOOL gone = !e && std_of(j) == "{\"none\":true}";
    fprintf(stderr, "SECURE_TEST secure.get after delete %s\n", e ? e.UTF8String : std_of(j).c_str());
    ok = ok && gone;
    fprintf(stderr, "SECURE_TEST %s in %.0f ms (%s)\n", ok ? "ok" : "FAILED", clock_ms(CLOCK_MONOTONIC) - t0,
            keys_in_files() ? "files, MBUI_KEYS_IN_FILES" : "the Keychain");
  });
  return 1;
}

// ── listen.* (ember client/core-ts hosts/bridge.ts; Android's Loopback.kt) ──
//   listen.open {port, host} → {id, port}, or the error (the port taken: "Address already in use")
//   listen.next {id} → {request, method, path, headers} + the body, or {end: true} once the listener is closed
//   listen.respond {id, request, status, headers: [[name, value]]} + the body → {}
//   listen.close {id} → {}
// The listeners are apple_listen.m's; what they take waits here, on the core's thread, for a listen.next.

@interface MBCoreListen : NSObject
@property(nonatomic) int lid;
@property(nonatomic) BOOL ended;
/// Requests no listen.next has taken yet: @[json, body].
@property(nonatomic, strong) NSMutableArray<NSArray<NSData *> *> *requests;
/// listen.next calls waiting for a request.
@property(nonatomic, strong) NSMutableArray<NSNumber *> *waiting;
@end

@implementation MBCoreListen
@end

// The core's listeners by id; only on the core's thread.
static NSMutableDictionary<NSNumber *, MBCoreListen *> *core_listens;

// What a listener says, from its queue: a request (handed to a waiting listen.next, else kept), or its end.
static void core_listen_took(void *ctx, const char *json, size_t len, const uint8_t *body, size_t blen) {
  if (!json) {
    MBCoreListen *l = (__bridge_transfer MBCoreListen *)ctx;
    post([l](jsi::Runtime &) {
      l.ended = YES;
      for (NSNumber *wid in l.waiting) answer_later(wid.doubleValue, const_json("{\"end\":true}"), nil, nil);
      [l.waiting removeAllObjects];
      [l.requests removeAllObjects];
      if (core_listens[@(l.lid)] == l) [core_listens removeObjectForKey:@(l.lid)];
    });
    return;
  }
  MBCoreListen *l = (__bridge MBCoreListen *)ctx;
  NSData *j = [NSData dataWithBytes:json length:len];
  NSData *b = [NSData dataWithBytes:body length:blen];
  post([l, j, b](jsi::Runtime &) {
    if (l.ended) return;
    if (l.waiting.count) {
      NSNumber *wid = l.waiting.firstObject;
      [l.waiting removeObjectAtIndex:0];
      answer_later(wid.doubleValue, j, nil, b);
    } else {
      [l.requests addObject:@[ j, b ]];
    }
  });
}

static void core_listen(double cid, NSString *op, NSData *json, const uint8_t *bytes, size_t blen) {
  NSDictionary *a = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
  if (![a isKindOfClass:NSDictionary.class]) a = @{};
  NSNumber *which = [a[@"id"] isKindOfClass:NSNumber.class] ? a[@"id"] : nil;
  if (!core_listens) core_listens = [NSMutableDictionary dictionary];
  if ([op isEqualToString:@"listen.open"]) {
    NSNumber *port = [a[@"port"] isKindOfClass:NSNumber.class] ? a[@"port"] : nil;
    NSString *host = [a[@"host"] isKindOfClass:NSString.class] ? a[@"host"] : nil;
    if (!port || !host) { answer_later(cid, nil, @"listen.open: port and host", nil); return; }
    MBCoreListen *l = [MBCoreListen new];
    l.requests = [NSMutableArray array];
    l.waiting = [NSMutableArray array];
    char why[160] = "";
    int bound = 0;
    void *ctx = (__bridge_retained void *)l;
    int lid = mb_listen_open(host.UTF8String, port.intValue, core_listen_took, ctx, &bound, why, sizeof why);
    if (!lid) {
      CFRelease(ctx);
      answer_later(cid, nil, @(why), nil);
      return;
    }
    l.lid = lid;
    core_listens[@(lid)] = l;
    answer_later(cid, [NSJSONSerialization dataWithJSONObject:@{@"id" : @(lid), @"port" : @(bound)} options:0 error:nil], nil, nil);
    return;
  }
  if ([op isEqualToString:@"listen.next"]) {
    MBCoreListen *l = which ? core_listens[which] : nil;
    if (!l || l.ended) { answer_later(cid, const_json("{\"end\":true}"), nil, nil); return; }
    if (l.requests.count) {
      NSArray<NSData *> *r = l.requests.firstObject;
      [l.requests removeObjectAtIndex:0];
      answer_later(cid, r[0], nil, r[1]);
      return;
    }
    [l.waiting addObject:@(cid)];
    return;
  }
  if ([op isEqualToString:@"listen.respond"]) {
    NSNumber *request = [a[@"request"] isKindOfClass:NSNumber.class] ? a[@"request"] : nil;
    NSNumber *status = [a[@"status"] isKindOfClass:NSNumber.class] ? a[@"status"] : @502;
    NSMutableArray<NSString *> *kv = [NSMutableArray array];
    for (NSArray *h in [a[@"headers"] isKindOfClass:NSArray.class] ? a[@"headers"] : @[]) {
      if (![h isKindOfClass:NSArray.class] || h.count < 2 || ![h[0] isKindOfClass:NSString.class] || ![h[1] isKindOfClass:NSString.class]) continue;
      [kv addObject:h[0]];
      [kv addObject:h[1]];
    }
    const char **pairs = static_cast<const char **>(calloc(kv.count ? kv.count : 1, sizeof(char *)));
    for (NSUInteger i = 0; i < kv.count; i++) pairs[i] = kv[i].UTF8String;
    if (which && request) mb_listen_respond(which.intValue, request.longValue, status.intValue, pairs, (int)(kv.count / 2), bytes, blen);
    free(pairs);
    answer_later(cid, const_json("{}"), nil, nil);
    return;
  }
  if ([op isEqualToString:@"listen.close"]) {
    if (which) mb_listen_close(which.intValue);
    answer_later(cid, const_json("{}"), nil, nil);
    return;
  }
  answer_later(cid, nil, @"unsupported", nil);
}

// Every listener of this core closed (the core ends).
static void core_listen_close_all(void) {
  for (NSNumber *lid in core_listens.allKeys) mb_listen_close(lid.intValue);
  core_listens = nil;
}

// ── __native ──

static NSData *ns_data(const std::string &s) { return [NSData dataWithBytes:s.data() length:s.size()]; }

static void install(jsi::Runtime &rt) {
  jsi::Object native(rt);
  auto fn = [&](const char *name, unsigned args, jsi::HostFunctionType f) {
    native.setProperty(rt, name, jsi::Function::createFromHostFunction(rt, jsi::PropNameID::forAscii(rt, name), args, std::move(f)));
  };
  fn("call", 4, [](jsi::Runtime &rt, const jsi::Value &, const jsi::Value *a, size_t n) -> jsi::Value {
    uint64_t id = uint64_t(a[0].asNumber());
    std::string op = a[1].asString(rt).utf8(rt);
    std::string json = a[2].asString(rt).utf8(rt);
    const uint8_t *p = nullptr;
    size_t len = 0;
    bool has = n > 3 && a[3].isObject() && a[3].asObject(rt).isArrayBuffer(rt);
    if (has) {
      jsi::ArrayBuffer b = a[3].asObject(rt).getArrayBuffer(rt);
      p = b.data(rt);
      len = b.size(rt);
    }
    bool here = op.rfind("secure.", 0) == 0 || op.rfind("listen.", 0) == 0;
    if (tracing())
      fprintf(stderr, "[core trace] -> %llu %s %.*s%s%s\n", (unsigned long long)id, op.c_str(), (int)std::min<size_t>(json.size(), 120), json.c_str(),
              has ? (" +" + std::to_string(len) + " bytes").c_str() : "", here ? " (here)" : "");
    if (here) {
      @autoreleasepool {
        NSString *name = @(op.c_str());
        if (op[0] == 's') core_secure(double(id), name, ns_data(json), p, len);
        else core_listen(double(id), name, ns_data(json), p, len);
      }
      return jsi::Value::undefined();
    }
    sf_shell_call(C.shell, id, op.c_str(), reinterpret_cast<const uint8_t *>(json.data()), json.size(), p, len, has ? 1 : 0);
    return jsi::Value::undefined();
  });
  fn("callSync", 2, [](jsi::Runtime &rt, const jsi::Value &, const jsi::Value *a, size_t) -> jsi::Value {
    std::string op = a[0].asString(rt).utf8(rt);
    std::string json = a[1].asString(rt).utf8(rt);
    if (tracing()) fprintf(stderr, "[core trace] sync %s %.*s\n", op.c_str(), (int)std::min<size_t>(json.size(), 120), json.c_str());
    size_t len = 0;
    uint8_t *out = sf_shell_call_sync(C.shell, op.c_str(), reinterpret_cast<const uint8_t *>(json.data()), json.size(), &len);
    jsi::String s = jsi::String::createFromUtf8(rt, out, len);
    sf_free(out, len);
    return s;
  });
  fn("emit", 2, [](jsi::Runtime &rt, const jsi::Value &, const jsi::Value *a, size_t) -> jsi::Value {
    std::string json = a[1].asString(rt).utf8(rt);
    say(json.data(), json.size(), nullptr, 0);
    return jsi::Value::undefined();
  });
  fn("emitBytes", 3, [](jsi::Runtime &rt, const jsi::Value &, const jsi::Value *a, size_t n) -> jsi::Value {
    static const uint8_t none = 0;
    std::string json = a[1].asString(rt).utf8(rt);
    if (n > 2 && a[2].isObject() && a[2].asObject(rt).isArrayBuffer(rt)) {
      jsi::ArrayBuffer b = a[2].asObject(rt).getArrayBuffer(rt);
      size_t len = b.size(rt);
      say(json.data(), json.size(), len ? b.data(rt) : &none, len);
    } else {
      say(json.data(), json.size(), &none, 0);
    }
    return jsi::Value::undefined();
  });
  fn("fatal", 1, [](jsi::Runtime &rt, const jsi::Value &, const jsi::Value *a, size_t) -> jsi::Value {
    fatal(a[0].isString() ? a[0].asString(rt).utf8(rt) : "the core failed");
    return jsi::Value::undefined();
  });
  fn("now", 0, [](jsi::Runtime &, const jsi::Value &, const jsi::Value *, size_t) -> jsi::Value { return jsi::Value(clock_ms(CLOCK_REALTIME)); });
  fn("monotonic", 0, [](jsi::Runtime &, const jsi::Value &, const jsi::Value *, size_t) -> jsi::Value { return jsi::Value(clock_ms(CLOCK_MONOTONIC)); });
  fn("utcOffset", 1, [](jsi::Runtime &, const jsi::Value &, const jsi::Value *a, size_t) -> jsi::Value {
    return jsi::Value(double(sf_utc_offset_min(a[0].asNumber())));
  });
  fn("random", 1, [](jsi::Runtime &rt, const jsi::Value &, const jsi::Value *a, size_t) -> jsi::Value {
    size_t n = a[0].asNumber() > 0 ? size_t(a[0].asNumber()) : 0;
    std::string bytes(n, '\0');
    if (n) arc4random_buf(bytes.data(), n);
    return array_buffer(rt, bytes.data(), n);
  });
  fn("setTimer", 2, [](jsi::Runtime &, const jsi::Value &, const jsi::Value *a, size_t) -> jsi::Value {
    uint64_t id = uint64_t(a[0].asNumber());
    double due = timer_ms() + std::max(0.0, a[1].asNumber());
    std::lock_guard<std::mutex> lock(C.mutex);
    C.timers[id] = due;
    C.dues.emplace(due, id);
    return jsi::Value::undefined();
  });
  fn("clearTimer", 1, [](jsi::Runtime &, const jsi::Value &, const jsi::Value *a, size_t) -> jsi::Value {
    std::lock_guard<std::mutex> lock(C.mutex);
    C.timers.erase(uint64_t(a[0].asNumber()));
    return jsi::Value::undefined();
  });
  fn("log", 2, [](jsi::Runtime &rt, const jsi::Value &, const jsi::Value *a, size_t) -> jsi::Value {
    int level = int(a[0].asNumber());
    if (level >= 1 || getenv("MB_CORE_DEBUG"))
      fprintf(stderr, "[core %s] %s\n", level >= 3 ? "error" : level == 2 ? "warn" : level == 1 ? "info" : "debug", a[1].asString(rt).utf8(rt).c_str());
    return jsi::Value::undefined();
  });
  native.setProperty(rt, "os", jsi::String::createFromAscii(rt, kOS));
  rt.global().setProperty(rt, "__native", native);
}

// $MB_CORE_BUNDLE, else core.hbc in the app's resources.
static NSString *script_path(void) {
  const char *env = getenv("MB_CORE_BUNDLE");
  if (env && *env) return @(env);
  return [[NSBundle mainBundle] pathForResource:@"core" ofType:@"hbc"];
}

// The core's thread: the shell, the runtime, the script, then the loop until stopped.
static void run(void) {
  std::unique_ptr<facebook::hermes::HermesRuntime> rt;
  @autoreleasepool {
    secure_dir = [@(C.dataDir.c_str()) stringByAppendingPathComponent:@"secure"];
    double t0 = clock_ms(CLOCK_MONOTONIC);
    C.shell = sf_shell_start(C.dataDir.c_str(), on_complete, C.gate);
    if (!C.shell) fatal("the core's files cannot be kept: " + C.dataDir);
    NSString *path = script_path();
    NSData *script = path ? [NSData dataWithContentsOfFile:path] : nil;
    if (C.shell && !script) fatal(std::string("no core script (MB_CORE_BUNDLE, or core.hbc in the app): ") + (path ? path.UTF8String : "-"));
    if (!C.dead) {
      auto config = ::hermes::vm::RuntimeConfig::Builder().withMicrotaskQueue(true).withEnableBlockScoping(true).withIntl(true).build();
      rt = facebook::hermes::makeHermesRuntime(config);
      double t1 = clock_ms(CLOCK_MONOTONIC), t2 = t1;
      try {
        install(*rt);
        rt->evaluateJavaScript(std::make_shared<Bytes>(std_of(script)), path.lastPathComponent.UTF8String ?: "core.hbc");
        t2 = clock_ms(CLOCK_MONOTONIC);
        jsi::Object sf = stillfail(*rt);
        sf.getPropertyAsFunction(*rt, "start")
            .callWithThis(*rt, sf, jsi::String::createFromUtf8(*rt, C.cloud), jsi::Value(C.beta), jsi::String::createFromAscii(*rt, kOS));
        C.client = sf.getPropertyAsFunction(*rt, "connect").callWithThis(*rt, sf).asNumber();
        rt->drainMicrotasks();
      } catch (const std::exception &e) {
        fatal(std::string("the core did not start: ") + e.what());
      }
      fprintf(stderr, "[core] Hermes: shell %.1f ms, script %.1f ms (%lu bytes), start %.1f ms\n", t1 - t0, t2 - t1, (unsigned long)script.length,
              clock_ms(CLOCK_MONOTONIC) - t2);
    }
  }

  for (;;) {
    Task task;
    uint64_t timer = 0;
    {
      std::unique_lock<std::mutex> lock(C.mutex);
      for (;;) {
        if (C.stopping) break;
        if (!C.tasks.empty()) {
          task = std::move(C.tasks.front());
          C.tasks.pop_front();
          break;
        }
        // The next timer still set (one cleared, or set again later, is passed over).
        while (!C.dues.empty()) {
          auto first = C.dues.begin();
          auto it = C.timers.find(first->second);
          if (it == C.timers.end() || it->second != first->first) {
            C.dues.erase(first);
            continue;
          }
          break;
        }
        if (!C.dues.empty()) {
          double left = C.dues.begin()->first - timer_ms();
          if (left <= 0) {
            timer = C.dues.begin()->second;
            C.timers.erase(timer);
            C.dues.erase(C.dues.begin());
            break;
          }
          C.wake.wait_for(lock, std::chrono::microseconds(int64_t(left * 1000)));
        } else {
          C.wake.wait(lock);
        }
      }
      if (C.stopping) break;
    }
    if (C.dead || !rt) continue;
    @autoreleasepool {
      try {
        if (task) task(*rt);
        else rt->global().getPropertyAsFunction(*rt, "__stillfail_timer").call(*rt, jsi::Value(double(timer)));
        rt->drainMicrotasks();
      } catch (const std::exception &e) {
        fatal(e.what());
      }
    }
  }

  @autoreleasepool {
    core_listen_close_all();
    rt.reset();
  }
}

// exit() (a host's, or AppKit's as the app quits) runs what atexit was given, the last first, then the destructors of
// this file's statics (C's mutex and queues) and Hermes's, registered as the program loaded: a core thread still in a
// task then locked a destroyed mutex (abort) or read freed memory (SIGSEGV), and the system said the app had crashed.
// So the core ends first, as mb_core_stop ends it (core/exit_test.m).
static void stop_at_exit(void) {
  if (!pthread_equal(pthread_self(), C.thread)) mb_core_stop();
}

void mb_core_start(const char *data_dir, const char *cloud_origin, int beta, mb_core_message_fn on_message, void *ctx) {
  if (C.running) return;
  static bool at_exit = false;
  if (!at_exit) at_exit = atexit(stop_at_exit) == 0;
  C.on_message = on_message;
  C.ctx = ctx;
  C.dead = false;
  C.dataDir = data_dir;
  C.cloud = cloud_origin;
  C.beta = beta != 0;
  C.shell = nullptr;
  C.gate = new Gate();
  {
    std::lock_guard<std::mutex> lock(C.mutex);
    C.tasks.clear();
    C.timers.clear();
    C.dues.clear();
    C.stopping = false;
    C.running = true;
  }
  pthread_attr_t attr;
  pthread_attr_init(&attr);
  pthread_attr_setstacksize(&attr, 8 << 20);
  pthread_create(&C.thread, &attr, [](void *) -> void * {
    pthread_setname_np("still.fail core");
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INITIATED, 0);
    run();
    return nullptr;
  }, nullptr);
  pthread_attr_destroy(&attr);
}

void mb_core_send(const char *json, size_t len, const uint8_t *bytes, size_t blen) {
  std::string j(json, len);
  bool has = bytes != nullptr;
  std::string b = has ? std::string(reinterpret_cast<const char *>(bytes), blen) : std::string();
  post([j = std::move(j), b = std::move(b), has](jsi::Runtime &rt) {
    jsi::Object sf = stillfail(rt);
    if (has)
      sf.getPropertyAsFunction(rt, "receiveBytes").callWithThis(rt, sf, jsi::Value(C.client), jsi::String::createFromUtf8(rt, j), array_buffer(rt, b.data(), b.size()));
    else
      sf.getPropertyAsFunction(rt, "receive").callWithThis(rt, sf, jsi::Value(C.client), jsi::String::createFromUtf8(rt, j));
  });
}

void mb_core_stop(void) {
  if (!C.running) return;
  {
    std::lock_guard<std::mutex> lock(C.mutex);
    C.stopping = true;
  }
  C.wake.notify_all();
  pthread_join(C.thread, nullptr);
  {
    // An answer under way finishes posting first (and is dropped); none reaches the core after.
    std::lock_guard<std::mutex> lock(C.gate->mutex);
    C.gate->open = false;
  }
  C.on_message = nullptr;
  if (C.shell) sf_shell_stop(C.shell);
  C.shell = nullptr;
  std::lock_guard<std::mutex> lock(C.mutex);
  C.tasks.clear();
  C.running = false;
}
