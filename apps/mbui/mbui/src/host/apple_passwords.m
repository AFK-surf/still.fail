// This device's password manager for the macOS host (host_native.mbt `pw_*`, hostapi/passwords.mbt): 1Password's
// command-line tool `op`, run without a window with the arguments the app gives (never through a shell), its output
// kept until the app takes it. `op` signed in through 1Password's desktop app asks the person itself (Touch ID, in its
// own window). Found where Homebrew and 1Password's installer put it, else on PATH. None on iOS.
#import <Foundation/Foundation.h>
#import "apple.h"

void mb_host_request_frame(void);

#if TARGET_OS_IPHONE

int32_t mb_host_passwords_able(void) { return 0; }
int32_t mb_host_passwords_run(moonbit_string_t args) { (void)args; return 0; }
moonbit_string_t mb_host_passwords_out(int32_t id) { (void)id; return mb_string_from_ns(@""); }
void mb_host_passwords_end(int32_t id) { (void)id; }

#else

/// The runs, by id, under their own lock: a run's end is heard on another thread.
static NSMutableDictionary<NSNumber *, NSMutableDictionary *> *runs;
static int run_next;

/// Where `op` is: Homebrew's (Apple silicon, Intel), 1Password's own installer's, else the first on PATH.
static NSString *op_path(void) {
  NSMutableArray<NSString *> *places = [@[ @"/opt/homebrew/bin/op", @"/usr/local/bin/op", @"/usr/bin/op" ] mutableCopy];
  NSString *path = NSProcessInfo.processInfo.environment[@"PATH"] ?: @"";
  for (NSString *dir in [path componentsSeparatedByString:@":"])
    if (dir.length) [places addObject:[dir stringByAppendingPathComponent:@"op"]];
  for (NSString *p in places)
    if ([NSFileManager.defaultManager isExecutableFileAtPath:p]) return p;
  return nil;
}

int32_t mb_host_passwords_able(void) { return 1; }

int32_t mb_host_passwords_run(moonbit_string_t args) {
  // One argument after another, each ended by a unit separator (U+001F).
  NSMutableArray<NSString *> *argv = [[mb_ns_from_string(args) componentsSeparatedByString:@"\x1f"] mutableCopy];
  [argv removeLastObject];
  if (!runs) runs = [NSMutableDictionary dictionary];
  int id;
  NSMutableDictionary *run = [NSMutableDictionary dictionary];
  @synchronized(runs) {
    id = ++run_next;
    runs[@(id)] = run;
  }
  NSString *op = op_path();
  if (!op) {
    @synchronized(runs) {
      run[@"done"] = @{@"code" : @(-1), @"out" : @"", @"err" : @"op not found"};
    }
    mb_host_request_frame();
    return id;
  }
  NSTask *t = [NSTask new];
  t.executableURL = [NSURL fileURLWithPath:op];
  t.arguments = argv;
  NSPipe *out = [NSPipe pipe], *err = [NSPipe pipe];
  t.standardOutput = out;
  t.standardError = err;
  t.standardInput = [NSFileHandle fileHandleWithNullDevice];
  // Read as it comes (a pipe that fills up holds the process), handed over as it ends.
  NSMutableData *said = [NSMutableData data], *errs = [NSMutableData data];
  out.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
    NSData *d = h.availableData;
    @synchronized(said) {
      [said appendData:d];
    }
  };
  err.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
    NSData *d = h.availableData;
    @synchronized(errs) {
      [errs appendData:d];
    }
  };
  t.terminationHandler = ^(NSTask *task) {
    out.fileHandleForReading.readabilityHandler = nil;
    err.fileHandleForReading.readabilityHandler = nil;
    NSData *rest = [out.fileHandleForReading readDataToEndOfFile], *restErr = [err.fileHandleForReading readDataToEndOfFile];
    NSString *o, *e;
    @synchronized(said) {
      [said appendData:rest];
      o = [[NSString alloc] initWithData:said encoding:NSUTF8StringEncoding] ?: @"";
    }
    @synchronized(errs) {
      [errs appendData:restErr];
      e = [[NSString alloc] initWithData:errs encoding:NSUTF8StringEncoding] ?: @"";
    }
    @synchronized(runs) {
      run[@"done"] = @{@"code" : @(task.terminationStatus), @"out" : o, @"err" : e};
      [run removeObjectForKey:@"task"];
    }
    mb_host_request_frame();
  };
  NSError *why = nil;
  if (![t launchAndReturnError:&why]) {
    @synchronized(runs) {
      run[@"done"] = @{@"code" : @(-1), @"out" : @"", @"err" : why.localizedDescription ?: @"op did not start"};
    }
    mb_host_request_frame();
    return id;
  }
  @synchronized(runs) {
    if (!run[@"done"]) run[@"task"] = t;
  }
  return id;
}

// How it ended, once it has: its exit code, its output and its error output, each ended by a unit separator; "" before.
moonbit_string_t mb_host_passwords_out(int32_t id) {
  NSDictionary *done = nil;
  @synchronized(runs) {
    done = runs[@(id)][@"done"];
  }
  if (!done) return mb_string_from_ns(@"");
  return mb_string_from_ns([NSString stringWithFormat:@"%@\x1f%@\x1f%@\x1f", done[@"code"], done[@"out"], done[@"err"]]);
}

void mb_host_passwords_end(int32_t id) {
  NSTask *t = nil;
  @synchronized(runs) {
    t = runs[@(id)][@"task"];
    [runs removeObjectForKey:@(id)];
  }
  if (t.running) [t terminate];
}

#endif

// This device's passkeys (host_native.mbt `wa_*`): none on Apple's systems, which sign a sign-in for another site only
// for a browser they entitle (win_passkeys.c is Windows').
int32_t mb_host_passkeys_able(void) { return 0; }
int32_t mb_host_passkeys_get(moonbit_string_t ask) { (void)ask; return 0; }
moonbit_string_t mb_host_passkeys_out(int32_t id) { (void)id; return mb_string_from_ns(@""); }
void mb_host_passkeys_end(int32_t id) { (void)id; }
