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
// What only an app can do is not the shell's: `secure.*` (the Keychain) and `listen.*` (a login's loopback listener)
// are answered "unsupported" for now. A JS error that escapes, or a bug the core reports, ends the core as on Android:
// `{"fatal": …}` to the UI, and the host starts another.
#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "core_api.h"

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

static int app_only(NSString *op) { return [op hasPrefix:@"secure."] || [op hasPrefix:@"listen."]; }

static void install(JSContext *js) {
  JSValue *native = [JSValue valueWithNewObjectInContext:js];
  native[@"call"] = ^(double id, NSString *op, JSValue *json, JSValue *bytes) {
    if (app_only(op)) {
      if (tracing()) fprintf(stderr, "[core trace] -> %llu %s (unsupported here)\n", (unsigned long long)id, op.UTF8String);
      // Not the shell's (core/README.md, Login): answered as a failure, later, as the shell would.
      post(^{
        complete((uint64_t)id, [JSValue valueWithNullInContext:C.js], [JSValue valueWithObject:@"unsupported" inContext:C.js], [JSValue valueWithUndefinedInContext:C.js]);
      });
      return;
    }
    NSData *j = utf8(json);
    const uint8_t *p = NULL;
    size_t n = 0;
    int has = bytes_of(bytes, &p, &n);
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
