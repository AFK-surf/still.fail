// The still.fail client core in JavaScriptCore, for the macOS and iOS hosts (core_api.h; core/README.md).
//
// One thread runs the core: a JSContext with the core's script (core/jsc.ts bundled, scripts/core.sh bundle) and a
// run loop that takes tasks (what the UI says, the shell's answers) and timers in order. JavaScriptCore drains the
// promise jobs itself each time a call into it returns. The thread is our own, not a dispatch queue's: a dispatch
// worker has 512 KB of stack and the core's parsers recurse; it gets 8 MB, as the Android engine gives Hermes.
//
// The script's `__native` goes to the Rust shell (client/shell, linked in: HTTP, still.fail cloud's socket, files and
// the accounts' SQLite, TCP, iroh), whose answers come from its threads (`complete`) and are posted here as tasks.
// `__native` is ember's HermesNative (hosts/hermes-globals.ts; bytes as ArrayBuffers both ways) plus `os`, so the
// script starts the core as on Android, through hosts/engine.ts (core/jsc-start.ts).
// What only an app can do is not the shell's: `listen.*` (a login's loopback listener) is answered here, on
// apple_listen.m; `secure.*` here too (the Keychain, or files for a build that can't use it). A JS error that escapes, or a bug the
// core reports, ends the core as on Android: `{"fatal": …}` to the UI, and the host starts another.
#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <Security/Security.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "core_api.h"
#include "listen_api.h"

typedef void (*sf_complete)(void *, uint64_t, const uint8_t *, size_t, const uint8_t *, size_t, const uint8_t *, size_t, uint8_t);
extern void *sf_shell_start(const char *data_dir, sf_complete complete, void *ctx);
extern void sf_shell_call(const void *shell, uint64_t id, const char *op, const uint8_t *json, size_t json_len, const uint8_t *bytes, size_t bytes_len, uint8_t has_bytes);
extern uint8_t *sf_shell_call_sync(const void *shell, const char *op, const uint8_t *json, size_t json_len, size_t *out_len);
extern void sf_free(uint8_t *ptr, size_t len);
extern void sf_shell_stop(void *shell);
extern int32_t sf_utc_offset_min(double at_ms);

#if TARGET_OS_IPHONE
static NSString *const kOS = @"ios";
#else
static NSString *const kOS = @"macos";
#endif

// What the shell answers through. Stopping the shell (tokio's shutdown_background) does not wait for what it is
// doing, so an answer can come after the core is gone: the shell holds this, not the core, and stopping closes it
// under its lock (as the Android engine's Gate). Never freed: a few bytes per restart.
typedef struct {
  pthread_mutex_t mutex;
  int open;
} Gate;

// The one core. Its fields are the core thread's, but for `loop` (set once it runs) and `gate`.
static struct {
  NSThread *thread;
  CFRunLoopRef loop;
  Gate *gate;
  void *shell;
  JSContext *js;
  JSValue *sf;  // __stillfail
  NSMutableDictionary<NSNumber *, NSValue *> *timers;  // id -> CFRunLoopTimerRef (retained)
  double client;
  int dead;
  int stopping;
  mb_core_message_fn on_message;
  void *ctx;
  dispatch_semaphore_t up, down;
} C;

static double clock_ms(clockid_t c) {
  struct timespec t;
  clock_gettime(c, &t);
  return (double)t.tv_sec * 1000.0 + (double)t.tv_nsec / 1e6;
}

static void say(const char *json, size_t len, const uint8_t *bytes, size_t blen) {
  if (C.on_message) C.on_message(json, len, bytes, blen, C.ctx);
}

static void fatal(NSString *reason) {
  if (C.dead) return;
  C.dead = 1;
  fprintf(stderr, "[core] fatal: %s\n", reason.UTF8String);
  NSData *d = [NSJSONSerialization dataWithJSONObject:@{@"fatal" : reason ?: @"the core failed"} options:0 error:nil];
  say(d.bytes, d.length, NULL, 0);
}

// ── the loop ──

// A task for the core's thread, in order with the others; from any thread.
static void post(void (^task)(void)) {
  CFRunLoopRef loop = C.loop;
  if (!loop) return;
  CFRunLoopPerformBlock(loop, kCFRunLoopDefaultMode, ^{
    @autoreleasepool {
      if (!C.stopping) task();
    }
  });
  CFRunLoopWakeUp(loop);
}

// ── bytes across the boundary ──

static void free_bytes(void *bytes, void *ctx) { free(bytes); }

// An ArrayBuffer over a copy of `bytes` (handed to the JS heap without a second copy): what engine.ts takes.
static JSValue *array_buffer(const uint8_t *bytes, size_t n) {
  JSGlobalContextRef g = C.js.JSGlobalContextRef;
  void *copy = malloc(n ? n : 1);
  if (n) memcpy(copy, bytes, n);
  JSValueRef exc = NULL;
  JSObjectRef a = JSObjectMakeArrayBufferWithBytesNoCopy(g, copy, n, free_bytes, NULL, &exc);
  if (!a) {
    free(copy);
    return [JSValue valueWithUndefinedInContext:C.js];
  }
  return [JSValue valueWithJSValueRef:a inContext:C.js];
}

// The bytes of a typed array or ArrayBuffer `v`, valid until the JS runs again. 0 when it is neither.
static int bytes_of(JSValue *v, const uint8_t **p, size_t *n) {
  if (!v || v.isUndefined || v.isNull || !v.isObject) return 0;
  JSGlobalContextRef g = C.js.JSGlobalContextRef;
  JSValueRef ref = v.JSValueRef;
  JSTypedArrayType type = JSValueGetTypedArrayType(g, ref, NULL);
  JSObjectRef obj = JSValueToObject(g, ref, NULL);
  if (type == kJSTypedArrayTypeNone) return 0;
  if (type == kJSTypedArrayTypeArrayBuffer) {
    *p = JSObjectGetArrayBufferBytesPtr(g, obj, NULL);
    *n = JSObjectGetArrayBufferByteLength(g, obj, NULL);
    return 1;
  }
  JSObjectRef buffer = JSObjectGetTypedArrayBuffer(g, obj, NULL);
  const uint8_t *base = buffer ? JSObjectGetArrayBufferBytesPtr(g, buffer, NULL) : NULL;
  *n = JSObjectGetTypedArrayByteLength(g, obj, NULL);
  *p = base ? base + JSObjectGetTypedArrayByteOffset(g, obj, NULL) : NULL;
  if (!*p && *n) return 0;
  return 1;
}

// A JS string as UTF-8.
static NSData *utf8(JSValue *v) { return [v.toString dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data]; }

static JSValue *js_string(const uint8_t *p, size_t n) {
  NSString *s = n ? [[NSString alloc] initWithBytes:p length:n encoding:NSUTF8StringEncoding] : @"";
  return [JSValue valueWithObject:s ?: @"" inContext:C.js];
}

// ── the shell's answers ──

// MB_CORE_TRACE=1: each shell operation and its answer on stderr.
static int tracing(void) {
  static int on = -1;
  if (on < 0) on = getenv("MB_CORE_TRACE") != NULL;
  return on;
}

static void complete(uint64_t id, JSValue *json, JSValue *error, JSValue *bytes) {
  if (tracing()) {
    const uint8_t *p;
    size_t n = 0;
    int has = bytes_of(bytes, &p, &n);
    fprintf(stderr, "[core trace] <- %llu %s%s\n", (unsigned long long)id, error.isString ? [@"error " stringByAppendingString:error.toString].UTF8String : json.isString ? [json.toString substringToIndex:MIN(json.toString.length, 120)].UTF8String : "null",
            has ? [NSString stringWithFormat:@" +%zu bytes", n].UTF8String : "");
  }
  if (C.dead || !C.sf) return;
  [C.sf invokeMethod:@"complete" withArguments:@[ @((double)id), json, error, bytes ]];
}

static void on_complete(void *ctx, uint64_t id, const uint8_t *json, size_t jl, const uint8_t *error, size_t el, const uint8_t *bytes, size_t bl, uint8_t has) {
  Gate *gate = ctx;
  pthread_mutex_lock(&gate->mutex);
  if (gate->open) {
    NSData *j = [NSData dataWithBytes:json length:jl];
    NSData *e = [NSData dataWithBytes:error length:el];
    NSData *b = has ? [NSData dataWithBytes:bytes length:bl] : nil;
    post(^{
      JSValue *null = [JSValue valueWithNullInContext:C.js];
      JSValue *jv = e.length ? null : js_string(j.bytes, j.length);
      JSValue *ev = e.length ? js_string(e.bytes, e.length) : null;
      JSValue *bv = b ? array_buffer(b.bytes, b.length) : [JSValue valueWithUndefinedInContext:C.js];
      complete(id, jv, ev, bv);
    });
  }
  pthread_mutex_unlock(&gate->mutex);
}

// ── timers ──

static void clear_timer(NSNumber *key) {
  NSValue *t = C.timers[key];
  if (!t) return;
  CFRunLoopTimerRef timer = t.pointerValue;
  CFRunLoopTimerInvalidate(timer);
  CFRelease(timer);
  [C.timers removeObjectForKey:key];
}

static void set_timer(double id, double ms) {
  NSNumber *key = @(id);
  clear_timer(key);
  CFRunLoopTimerRef timer = CFRunLoopTimerCreateWithHandler(NULL, CFAbsoluteTimeGetCurrent() + (ms > 0 ? ms : 0) / 1000.0, 0, 0, 0, ^(CFRunLoopTimerRef t) {
    @autoreleasepool {
      if (C.timers[key].pointerValue != t) return;
      CFRelease(t);
      [C.timers removeObjectForKey:key];
      if (C.dead || C.stopping) return;
      [C.js[@"__stillfail_timer"] callWithArguments:@[ key ]];
    }
  });
  C.timers[key] = [NSValue valueWithPointer:timer];
  CFRunLoopAddTimer(C.loop, timer, kCFRunLoopDefaultMode);
}

// ── __native ──

// ── secure.* (ember hosts/bridge.ts; Android's Keystore) ──
//   secure.get {key, user, reason} → {} + the bytes, or {none: true}; secure.set {key, user} + the bytes → {};
//   secure.delete {key} → {}; secure.ask {reason}: unsupported.
// What the core keeps out of the files it syncs (the lock's signing seed, a vault's key): in the Keychain, as a
// generic password per data directory and key, readable once the Mac is unlocked after a restart and never with a
// dialog (none can be answered on a station's locked screen: it fails instead). `user` (asking the person, Touch ID)
// is not offered yet. MBUI_KEYS_IN_FILES=1 keeps them as files of `<data>/secure` instead (0600), for unsigned
// development builds, which a Keychain item made by one build would ask about when the next build reads it.

static NSString *secure_dir;
static void answer_later(double id, NSData *json, NSString *error, NSData *bytes);
static NSData *const_json(const char *s);

static NSString *secure_path(NSString *key) {
  NSMutableString *hex = [NSMutableString string];
  NSData *k = [key dataUsingEncoding:NSUTF8StringEncoding];
  const uint8_t *b = k.bytes;
  for (NSUInteger i = 0; i < k.length; i++) [hex appendFormat:@"%02x", b[i]];
  return [secure_dir stringByAppendingPathComponent:hex];
}

static BOOL keys_in_files(void) { return getenv("MBUI_KEYS_IN_FILES") != NULL; }

static NSMutableDictionary *keychain_query(NSString *key) {
  return [@{
    (id)kSecClass : (id)kSecClassGenericPassword,
    (id)kSecAttrService : @"fail.still.mbui.core",
    (id)kSecAttrAccount : [NSString stringWithFormat:@"%@\n%@", secure_dir, key],
    (id)kSecUseAuthenticationUI : (id)kSecUseAuthenticationUIFail,
  } mutableCopy];
}

// (`cid`, not `id`: the call's id would hide Objective-C's `id` in the casts below)
static void core_secure(double cid, NSString *op, NSData *json, const uint8_t *bytes, size_t blen) {
  NSDictionary *a = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
  NSString *key = [a isKindOfClass:[NSDictionary class]] ? a[@"key"] : nil;
  if ([op isEqualToString:@"secure.ask"] || [a[@"user"] boolValue]) {
    answer_later(cid, nil, @"unsupported", nil);
    return;
  }
  if (![key isKindOfClass:[NSString class]] || key.length == 0) {
    answer_later(cid, nil, [op stringByAppendingString:@": no key"], nil);
    return;
  }
  if (keys_in_files()) {
    NSString *path = secure_path(key);
    if ([op isEqualToString:@"secure.get"]) {
      NSData *d = [NSData dataWithContentsOfFile:path];
      if (d) answer_later(cid, const_json("{}"), nil, d);
      else answer_later(cid, const_json("{\"none\":true}"), nil, nil);
    } else if ([op isEqualToString:@"secure.set"]) {
      [[NSFileManager defaultManager] createDirectoryAtPath:secure_dir withIntermediateDirectories:YES
                                                 attributes:@{NSFilePosixPermissions : @0700} error:nil];
      NSData *d = [NSData dataWithBytes:bytes length:blen];
      BOOL ok = [d writeToFile:path options:NSDataWritingAtomic error:nil];
      if (ok) [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions : @0600} ofItemAtPath:path error:nil];
      answer_later(cid, ok ? const_json("{}") : nil, ok ? nil : @"secure.set: not written", nil);
    } else if ([op isEqualToString:@"secure.delete"]) {
      [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
      answer_later(cid, const_json("{}"), nil, nil);
    } else {
      answer_later(cid, nil, @"unsupported", nil);
    }
    return;
  }
  NSMutableDictionary *q = keychain_query(key);
  if ([op isEqualToString:@"secure.get"]) {
    q[(id)kSecReturnData] = @YES;
    q[(id)kSecMatchLimit] = (id)kSecMatchLimitOne;
    CFTypeRef out = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &out);
    if (st == errSecSuccess) answer_later(cid, const_json("{}"), nil, (__bridge_transfer NSData *)out);
    else if (st == errSecItemNotFound) answer_later(cid, const_json("{\"none\":true}"), nil, nil);
    else answer_later(cid, nil, [NSString stringWithFormat:@"secure.get: Keychain %d", (int)st], nil);
  } else if ([op isEqualToString:@"secure.set"]) {
    NSData *d = [NSData dataWithBytes:bytes length:blen];
    SecItemDelete((__bridge CFDictionaryRef)keychain_query(key));
    q[(id)kSecValueData] = d;
    q[(id)kSecAttrAccessible] = (id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    OSStatus st = SecItemAdd((__bridge CFDictionaryRef)q, NULL);
    if (st == errSecSuccess) answer_later(cid, const_json("{}"), nil, nil);
    else answer_later(cid, nil, [NSString stringWithFormat:@"secure.set: Keychain %d", (int)st], nil);
  } else if ([op isEqualToString:@"secure.delete"]) {
    SecItemDelete((__bridge CFDictionaryRef)q);
    answer_later(cid, const_json("{}"), nil, nil);
  } else {
    answer_later(cid, nil, @"unsupported", nil);
  }
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

static JSValue *js_null(void) { return [JSValue valueWithNullInContext:C.js]; }
static JSValue *js_undefined(void) { return [JSValue valueWithUndefinedInContext:C.js]; }

// An answer, later on the core's thread, as the shell's come.
static void answer_later(double id, NSData *json, NSString *error, NSData *bytes) {
  post(^{
    if (error) complete((uint64_t)id, js_null(), [JSValue valueWithObject:error inContext:C.js], js_undefined());
    else complete((uint64_t)id, js_string(json.bytes, json.length), js_null(), bytes ? array_buffer(bytes.bytes, bytes.length) : js_undefined());
  });
}

static NSData *const_json(const char *s) { return [NSData dataWithBytes:s length:strlen(s)]; }

// What a listener says, from its queue: a request (handed to a waiting listen.next, else kept), or its end.
static void core_listen_took(void *ctx, const char *json, size_t len, const uint8_t *body, size_t blen) {
  if (!json) {
    MBCoreListen *l = (__bridge_transfer MBCoreListen *)ctx;
    post(^{
      l.ended = YES;
      for (NSNumber *id in l.waiting) complete(id.unsignedLongLongValue, js_string((const uint8_t *)"{\"end\":true}", 12), js_null(), js_undefined());
      [l.waiting removeAllObjects];
      [l.requests removeAllObjects];
      if (core_listens[@(l.lid)] == l) [core_listens removeObjectForKey:@(l.lid)];
    });
    return;
  }
  MBCoreListen *l = (__bridge MBCoreListen *)ctx;
  NSData *j = [NSData dataWithBytes:json length:len];
  NSData *b = [NSData dataWithBytes:body length:blen];
  post(^{
    if (l.ended) return;
    if (l.waiting.count) {
      NSNumber *id = l.waiting.firstObject;
      [l.waiting removeObjectAtIndex:0];
      complete(id.unsignedLongLongValue, js_string(j.bytes, j.length), js_null(), array_buffer(b.bytes, b.length));
    } else {
      [l.requests addObject:@[ j, b ]];
    }
  });
}

static void core_listen(double id, NSString *op, NSData *json, const uint8_t *bytes, size_t blen) {
  NSDictionary *a = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
  if (![a isKindOfClass:NSDictionary.class]) a = @{};
  NSNumber *which = [a[@"id"] isKindOfClass:NSNumber.class] ? a[@"id"] : nil;
  if (!core_listens) core_listens = [NSMutableDictionary dictionary];
  if ([op isEqualToString:@"listen.open"]) {
    NSNumber *port = [a[@"port"] isKindOfClass:NSNumber.class] ? a[@"port"] : nil;
    NSString *host = [a[@"host"] isKindOfClass:NSString.class] ? a[@"host"] : nil;
    if (!port || !host) { answer_later(id, nil, @"listen.open: port and host", nil); return; }
    MBCoreListen *l = [MBCoreListen new];
    l.requests = [NSMutableArray array];
    l.waiting = [NSMutableArray array];
    char why[160] = "";
    int bound = 0;
    void *ctx = (__bridge_retained void *)l;
    int lid = mb_listen_open(host.UTF8String, port.intValue, core_listen_took, ctx, &bound, why, sizeof why);
    if (!lid) {
      CFRelease(ctx);
      answer_later(id, nil, @(why), nil);
      return;
    }
    l.lid = lid;
    core_listens[@(lid)] = l;
    answer_later(id, [NSJSONSerialization dataWithJSONObject:@{@"id" : @(lid), @"port" : @(bound)} options:0 error:nil], nil, nil);
    return;
  }
  if ([op isEqualToString:@"listen.next"]) {
    MBCoreListen *l = which ? core_listens[which] : nil;
    if (!l || l.ended) { answer_later(id, const_json("{\"end\":true}"), nil, nil); return; }
    if (l.requests.count) {
      NSArray<NSData *> *r = l.requests.firstObject;
      [l.requests removeObjectAtIndex:0];
      answer_later(id, r[0], nil, r[1]);
      return;
    }
    [l.waiting addObject:@(id)];
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
    const char **pairs = calloc(kv.count ? kv.count : 1, sizeof(char *));
    for (NSUInteger i = 0; i < kv.count; i++) pairs[i] = kv[i].UTF8String;
    if (which && request) mb_listen_respond(which.intValue, request.longValue, status.intValue, pairs, (int)(kv.count / 2), bytes, blen);
    free(pairs);
    answer_later(id, const_json("{}"), nil, nil);
    return;
  }
  if ([op isEqualToString:@"listen.close"]) {
    if (which) mb_listen_close(which.intValue);
    answer_later(id, const_json("{}"), nil, nil);
    return;
  }
  answer_later(id, nil, @"unsupported", nil);
}

// Every listener of this core closed (the core ends).
static void core_listen_close_all(void) {
  for (NSNumber *lid in core_listens.allKeys) mb_listen_close(lid.intValue);
  core_listens = nil;
}

static void install(JSContext *js) {
  JSValue *native = [JSValue valueWithNewObjectInContext:js];
  native[@"call"] = ^(double id, NSString *op, JSValue *json, JSValue *bytes) {
    NSData *j = utf8(json);
    const uint8_t *p = NULL;
    size_t n = 0;
    int has = bytes_of(bytes, &p, &n);
    if ([op hasPrefix:@"secure."]) {
      if (tracing()) fprintf(stderr, "[core trace] -> %llu %s (here)\n", (unsigned long long)id, op.UTF8String);
      core_secure(id, op, j, has ? p : NULL, has ? n : 0);
      return;
    }
    if ([op hasPrefix:@"listen."]) {
      if (tracing()) fprintf(stderr, "[core trace] -> %llu %s %.*s (here)\n", (unsigned long long)id, op.UTF8String, (int)MIN(j.length, 120), (const char *)j.bytes);
      core_listen(id, op, j, has ? p : NULL, has ? n : 0);
      return;
    }
    if (tracing()) fprintf(stderr, "[core trace] -> %llu %s %.*s%s\n", (unsigned long long)id, op.UTF8String, (int)MIN(j.length, 120), (const char *)j.bytes, has ? [NSString stringWithFormat:@" +%zu bytes", n].UTF8String : "");
    sf_shell_call(C.shell, (uint64_t)id, op.UTF8String, j.bytes, j.length, p, n, (uint8_t)has);
  };
  native[@"callSync"] = ^JSValue *(NSString *op, JSValue *json) {
    NSData *j = utf8(json);
    if (tracing()) fprintf(stderr, "[core trace] sync %s %.*s\n", op.UTF8String, (int)MIN(j.length, 120), (const char *)j.bytes);
    size_t len = 0;
    uint8_t *out = sf_shell_call_sync(C.shell, op.UTF8String, j.bytes, j.length, &len);
    JSValue *s = js_string(out, len);
    sf_free(out, len);
    return s;
  };
  native[@"emit"] = ^(double client, JSValue *json) {
    NSData *j = utf8(json);
    say(j.bytes, j.length, NULL, 0);
  };
  native[@"emitBytes"] = ^(double client, JSValue *json, JSValue *bytes) {
    NSData *j = utf8(json);
    const uint8_t *p = NULL;
    size_t n = 0;
    if (!bytes_of(bytes, &p, &n)) p = NULL, n = 0;
    static const uint8_t none = 0;
    say(j.bytes, j.length, p ? p : &none, n);
  };
  native[@"fatal"] = ^(JSValue *reason) {
    fatal(reason.isString ? reason.toString : @"the core failed");
  };
  native[@"now"] = ^double(void) { return clock_ms(CLOCK_REALTIME); };
  native[@"monotonic"] = ^double(void) { return clock_ms(CLOCK_MONOTONIC); };
  native[@"utcOffset"] = ^double(double at) { return (double)sf_utc_offset_min(at); };
  native[@"random"] = ^JSValue *(double count) {
    size_t n = count > 0 ? (size_t)count : 0;
    void *bytes = malloc(n ? n : 1);
    arc4random_buf(bytes, n);
    JSObjectRef b = JSObjectMakeArrayBufferWithBytesNoCopy(C.js.JSGlobalContextRef, bytes, n, free_bytes, NULL, NULL);
    return [JSValue valueWithJSValueRef:b inContext:C.js];
  };
  native[@"setTimer"] = ^(double id, double ms) { set_timer(id, ms); };
  native[@"clearTimer"] = ^(double id) { clear_timer(@(id)); };
  native[@"log"] = ^(double level, NSString *message) {
    if (level >= 1 || getenv("MB_CORE_DEBUG")) fprintf(stderr, "[core %s] %s\n", level >= 3 ? "error" : level == 2 ? "warn" : level == 1 ? "info" : "debug", message.UTF8String);
  };
  native[@"os"] = kOS;  // for core/jsc-start.ts's startEngine
  js[@"__native"] = native;
}

static NSString *script_path(void) {
  const char *env = getenv("MB_CORE_BUNDLE");
  if (env && *env) return @(env);
  return [[NSBundle mainBundle] pathForResource:@"core" ofType:@"js"];
}

// The core's thread: the shell, the context, the script, then the loop until stopped.
static void run(NSString *dataDir, NSString *cloud, int beta) {
  secure_dir = [dataDir stringByAppendingPathComponent:@"secure"];
  C.loop = CFRunLoopGetCurrent();
  CFRetain(C.loop);
  // A source that never fires keeps the loop running while nothing else is in it.
  CFRunLoopSourceContext none = {0};
  CFRunLoopSourceRef keep = CFRunLoopSourceCreate(NULL, 0, &none);
  CFRunLoopAddSource(C.loop, keep, kCFRunLoopDefaultMode);
  dispatch_semaphore_signal(C.up);

  @autoreleasepool {
    double t0 = clock_ms(CLOCK_MONOTONIC);
    C.shell = sf_shell_start(dataDir.fileSystemRepresentation, on_complete, C.gate);
    if (!C.shell) fatal([NSString stringWithFormat:@"the core's files cannot be kept: %@", dataDir]);
    NSString *path = script_path();
    NSString *script = path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
    if (C.shell && !script) fatal([NSString stringWithFormat:@"no core script (MB_CORE_BUNDLE, or core.js in the app): %@", path ?: @"-"]);
    if (!C.dead) {
      C.js = [[JSContext alloc] init];
      C.js.name = @"still.fail core";
      C.js.exceptionHandler = ^(JSContext *js, JSValue *e) {
        NSString *stack = [e[@"stack"] toString];
        fatal([NSString stringWithFormat:@"%@%@%@", e.toString, stack.length ? @"\n" : @"", stack ?: @""]);
      };
      C.timers = [NSMutableDictionary dictionary];
      install(C.js);
      double t1 = clock_ms(CLOCK_MONOTONIC);
      [C.js evaluateScript:script withSourceURL:[NSURL fileURLWithPath:path]];
      double t2 = clock_ms(CLOCK_MONOTONIC);
      C.sf = C.js[@"__stillfail"];
      if (!C.dead && C.sf.isObject) {
        [C.sf invokeMethod:@"start" withArguments:@[ cloud, @(beta != 0) ]];
        C.client = [[C.sf invokeMethod:@"connect" withArguments:@[]] toDouble];
      } else if (!C.dead) {
        fatal(@"the core's script has no __stillfail");
      }
      fprintf(stderr, "[core] shell %.1f ms, script %.1f ms (%lu bytes), start %.1f ms\n", t1 - t0, t2 - t1,
              (unsigned long)[script lengthOfBytesUsingEncoding:NSUTF8StringEncoding], clock_ms(CLOCK_MONOTONIC) - t2);
    }
  }

  while (!C.stopping) {
    @autoreleasepool {
      CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1e9, false);
    }
  }

  @autoreleasepool {
    core_listen_close_all();
    for (NSNumber *key in C.timers.allKeys) clear_timer(key);
    C.timers = nil;
    C.sf = nil;
    C.js = nil;
  }
  CFRunLoopRemoveSource(C.loop, keep, kCFRunLoopDefaultMode);
  CFRelease(keep);
  dispatch_semaphore_signal(C.down);
}

void mb_core_start(const char *data_dir, const char *cloud_origin, int beta, mb_core_message_fn on_message, void *ctx) {
  if (C.thread) return;
  C.on_message = on_message;
  C.ctx = ctx;
  C.dead = 0;
  C.stopping = 0;
  C.gate = calloc(1, sizeof(Gate));
  pthread_mutex_init(&C.gate->mutex, NULL);
  C.gate->open = 1;
  C.up = dispatch_semaphore_create(0);
  C.down = dispatch_semaphore_create(0);
  NSString *dir = @(data_dir);
  NSString *cloud = @(cloud_origin);
  C.thread = [[NSThread alloc] initWithBlock:^{
    run(dir, cloud, beta);
  }];
  C.thread.name = @"still.fail core";
  C.thread.stackSize = 8 << 20;
  C.thread.qualityOfService = NSQualityOfServiceUserInitiated;
  [C.thread start];
  dispatch_semaphore_wait(C.up, DISPATCH_TIME_FOREVER);
}

void mb_core_send(const char *json, size_t len, const uint8_t *bytes, size_t blen) {
  NSData *j = [NSData dataWithBytes:json length:len];
  NSData *b = bytes ? [NSData dataWithBytes:bytes length:blen] : nil;
  post(^{
    if (C.dead || !C.sf) return;
    JSValue *s = js_string(j.bytes, j.length);
    if (b) [C.sf invokeMethod:@"receiveBytes" withArguments:@[ @(C.client), s, array_buffer(b.bytes, b.length) ]];
    else [C.sf invokeMethod:@"receive" withArguments:@[ @(C.client), s ]];
  });
}

void mb_core_stop(void) {
  if (!C.thread) return;
  // No answer from the shell reaches the core after this (one being posted finishes first).
  pthread_mutex_lock(&C.gate->mutex);
  C.gate->open = 0;
  pthread_mutex_unlock(&C.gate->mutex);
  CFRunLoopRef loop = C.loop;
  CFRunLoopPerformBlock(loop, kCFRunLoopDefaultMode, ^{
    C.stopping = 1;
    CFRunLoopStop(CFRunLoopGetCurrent());
  });
  CFRunLoopWakeUp(loop);
  dispatch_semaphore_wait(C.down, DISPATCH_TIME_FOREVER);
  C.on_message = NULL;
  if (C.shell) sf_shell_stop(C.shell);
  C.shell = NULL;
  C.loop = NULL;
  CFRelease(loop);
  C.thread = nil;
}
