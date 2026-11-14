// still.fail's own host's side of src/stillfail/reports.mbt on iOS and macOS (src/stillfail/core_engine.m includes it), what
// Android's Crashes.java does: the app's crashes and hangs, to still.fail's PostHog project as
// `$exception` events. iOS lets no app see its own end: MetricKit (MXMetricManager) gives the system's report of each
// crash, and of each hang, as the app starts the next time. Each is kept in the app's files as it comes
// (crashes/<id>.json: what MetricKit gave, its kind and when) and goes once an account is signed in, as it, in one
// batch to /batch/; what fails to go goes at the next start. A report's frames are the system's, unsymbolicated: each
// binary's name, UUID and offset into its text, for the build's dSYM ( says how).
//
// A build without PostHog's key (Info.plist's StillfailPosthogKey: scripts/ios-core.sh and, for still.fail's own Mac app,
// scripts/mac-app.sh write it from the file STILLFAIL_POSTHOG names, the release's POSTHOG_JSON) sends nothing and keeps nothing, and answers `hello` 0:
// the app then reports what it reports as on a host without its own (reports.mbt). Nor one whose person turned it off
// (the settings' 「发送使用统计和错误报告」, this device's own, in reports.json beside the kept ones): everything goes
// by `sf_send`, which looks first.
//
// SF_REPORTS_PURE (scripts/ios-reports-test.sh) leaves only what turns a kept report into its event: Foundation's, run
// on a Mac by the test.
#import <CommonCrypto/CommonDigest.h>
#import <Foundation/Foundation.h>

/// What goes up of one report's frames, the crashing thread's (the `trace` property's lines, the `frames` property).
static const NSUInteger SF_FRAMES = 64;
/// What goes up of one report's trace, as Android's (Crashes.LOGS).
static const NSUInteger SF_TRACE = 60 * 1024;

static NSString *sf_hex(const unsigned char *b, size_t n) {
  NSMutableString *s = [NSMutableString stringWithCapacity:n * 2];
  for (size_t i = 0; i < n; i++) [s appendFormat:@"%02x", b[i]];
  return s;
}

/// A report's id: its kind and what MetricKit said of it (its JSON, keys sorted: the same report given again, by
/// pastDiagnosticPayloads or after a failed send, is the same id), hashed: the first 16 bytes of SHA-256, as hex. (None on
/// macOS, which keeps no MetricKit report.)
__attribute__((unused)) static NSString *sf_report_id(NSString *kind, NSDictionary *diagnostic) {
  NSData *json = [NSJSONSerialization dataWithJSONObject:diagnostic options:NSJSONWritingSortedKeys error:nil];
  if (!json) return nil;
  NSMutableData *all = [[kind stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding].mutableCopy;
  [all appendData:json];
  unsigned char h[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(all.bytes, (CC_LONG)all.length, h);
  return sf_hex(h, 16);
}

/// The uuid a report's event goes with, from its id (32 hex digits): sent again (its answer lost), it is the same
/// event, and PostHog keeps one. Its version digit 5 and its variant RFC 4122's, as a name's uuid is.
static NSString *sf_report_uuid(NSString *rid) {
  if (rid.length != 32) return nil;
  NSString *s = rid.lowercaseString;
  unichar variant = [@"89ab" characterAtIndex:(NSUInteger)(strtol([s substringWithRange:NSMakeRange(16, 1)].UTF8String, NULL, 16) & 3)];
  return [NSString stringWithFormat:@"%@-%@-5%@-%C%@-%@", [s substringToIndex:8], [s substringWithRange:NSMakeRange(8, 4)],
                                    [s substringWithRange:NSMakeRange(13, 3)], variant, [s substringWithRange:NSMakeRange(17, 3)],
                                    [s substringFromIndex:20]];
}

static NSString *sf_iso(double ms) {
  NSDateFormatter *f = [NSDateFormatter new];
  f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
  f.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
  f.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
  return [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:ms / 1000.0]];
}

static NSString *sf_signal_name(long sig) {
  switch (sig) {
    case 4: return @"SIGILL";
    case 5: return @"SIGTRAP";
    case 6: return @"SIGABRT";
    case 7: return @"SIGEMT";
    case 8: return @"SIGFPE";
    case 9: return @"SIGKILL";
    case 10: return @"SIGBUS";
    case 11: return @"SIGSEGV";
    case 12: return @"SIGSYS";
    case 13: return @"SIGPIPE";
    case 15: return @"SIGTERM";
    default: return [NSString stringWithFormat:@"signal %ld", sig];
  }
}

/// A Mach exception's name, as a crash log says it.
static NSString *sf_mach_name(long type) {
  switch (type) {
    case 1: return @"EXC_BAD_ACCESS";
    case 2: return @"EXC_BAD_INSTRUCTION";
    case 3: return @"EXC_ARITHMETIC";
    case 4: return @"EXC_EMULATION";
    case 5: return @"EXC_SOFTWARE";
    case 6: return @"EXC_BREAKPOINT";
    case 7: return @"EXC_SYSCALL";
    case 8: return @"EXC_MACH_SYSCALL";
    case 9: return @"EXC_RPC_ALERT";
    case 10: return @"EXC_CRASH";
    case 11: return @"EXC_RESOURCE";
    case 12: return @"EXC_GUARD";
    case 13: return @"EXC_CORPSE_NOTIFY";
    default: return [NSString stringWithFormat:@"exception %ld", type];
  }
}

static NSString *sf_string(id v) {
  if ([v isKindOfClass:NSString.class]) return [(NSString *)v length] ? v : nil;
  if ([v isKindOfClass:NSNumber.class]) return [v stringValue];
  return nil;
}

static NSDictionary *sf_dict(id v) { return [v isKindOfClass:NSDictionary.class] ? v : nil; }
static NSArray *sf_array(id v) { return [v isKindOfClass:NSArray.class] ? v : nil; }

/// The crashing thread's frames, innermost first (a hang's: the main thread's), from a report's callStackTree: the
/// thread MetricKit attributes it to (threadAttributed), else its first. A crash's stack is a chain: each frame's
/// caller its first subframe.
static NSArray<NSDictionary *> *sf_frames(NSDictionary *tree) {
  NSArray *stacks = sf_array(tree[@"callStacks"]);
  NSDictionary *stack = nil;
  for (id s in stacks)
    if ([sf_dict(s)[@"threadAttributed"] boolValue]) {
      stack = s;
      break;
    }
  if (!stack) stack = sf_dict(stacks.firstObject);
  NSMutableArray *out = [NSMutableArray array];
  NSDictionary *f = sf_dict(sf_array(stack[@"callStackRootFrames"]).firstObject);
  while (f && out.count < SF_FRAMES) {
    NSMutableDictionary *frame = [NSMutableDictionary dictionary];
    frame[@"binary"] = sf_string(f[@"binaryName"]) ?: @"???";
    if (sf_string(f[@"binaryUUID"])) frame[@"uuid"] = f[@"binaryUUID"];
    if ([f[@"offsetIntoBinaryTextSegment"] isKindOfClass:NSNumber.class]) frame[@"offset"] = f[@"offsetIntoBinaryTextSegment"];
    if ([f[@"address"] isKindOfClass:NSNumber.class]) frame[@"address"] = f[@"address"];
    [out addObject:frame];
    f = sf_dict(sf_array(f[@"subFrames"]).firstObject);
  }
  return out;
}

/// A frame as a crash log's line says it: its binary and its offset into it (where the dSYM is read).
static NSString *sf_frame_text(NSDictionary *f) {
  return [NSString stringWithFormat:@"%@ + 0x%llx", f[@"binary"], [f[@"offset"] unsignedLongLongValue]];
}

/// "iPhone OS 27.2 (24C101)" → "27.2".
static NSString *sf_os_version(NSString *said) {
  for (NSString *w in [said componentsSeparatedByString:@" "])
    if (w.length && [NSCharacterSet.decimalDigitCharacterSet characterIsMember:[w characterAtIndex:0]]) return w;
  return said;
}

/// A kept report as its `$exception` event, as `account` (the signed-in account's id), with `here`'s properties (the
/// app and device now: what the report itself does not say) under what the report says of the build and device it
/// came from. kept: {"kind": "crash" | "hang", "at": ms, "hang_ms": ms (a hang's), "diagnostic": MetricKit's JSON}.
static NSDictionary *sf_report_event(NSDictionary *kept, NSString *rid, NSString *account, NSDictionary *here) {
  NSString *kind = sf_string(kept[@"kind"]);
  NSDictionary *d = sf_dict(kept[@"diagnostic"]);
  NSString *uuid = sf_report_uuid(rid);
  if (!d || !uuid || !account.length || !([kind isEqual:@"crash"] || [kind isEqual:@"hang"])) return nil;
  BOOL crash = [kind isEqual:@"crash"];
  NSDictionary *meta = sf_dict(d[@"diagnosticMetaData"]) ?: @{};
  NSArray<NSDictionary *> *frames = sf_frames(sf_dict(d[@"callStackTree"]));
  NSMutableDictionary *p = [here mutableCopy] ?: [NSMutableDictionary dictionary];
  p[@"reason"] = kind;
  NSString *version = sf_string(meta[@"appVersion"]), *build = sf_string(meta[@"appBuildVersion"]);
  if (version) {
    // the version and the TestFlight build, as the release's workflow run names them: "0.1.0 (37)"
    p[@"release"] = build ? [NSString stringWithFormat:@"%@ (%@)", version, build] : version;
    p[@"$app_version"] = version;
  }
  if (build) p[@"$app_build"] = build;
  if (sf_string(meta[@"osVersion"])) {
    p[@"$os_version"] = sf_os_version(meta[@"osVersion"]);
    p[@"os_build"] = meta[@"osVersion"];
  }
  if (sf_string(meta[@"deviceType"])) p[@"$device_model"] = meta[@"deviceType"];
  if (sf_string(meta[@"platformArchitecture"])) p[@"arch"] = meta[@"platformArchitecture"];
  if (sf_string(meta[@"bundleIdentifier"])) p[@"bundle"] = meta[@"bundleIdentifier"];
  if ([meta[@"isTestFlightApp"] isKindOfClass:NSNumber.class]) p[@"testflight"] = meta[@"isTestFlightApp"];
  if ([meta[@"lowPowerModeEnabled"] isKindOfClass:NSNumber.class]) p[@"low_power"] = meta[@"lowPowerModeEnabled"];
  NSString *type, *value, *headline;
  NSMutableArray *said = [NSMutableArray array];
  if (crash) {
    NSString *signal = [meta[@"signal"] isKindOfClass:NSNumber.class] ? sf_signal_name([meta[@"signal"] longValue]) : nil;
    NSString *mach = [meta[@"exceptionType"] isKindOfClass:NSNumber.class] ? sf_mach_name([meta[@"exceptionType"] longValue]) : nil;
    if (signal) p[@"signal"] = signal;
    if (mach) p[@"exception_type"] = mach;
    if ([meta[@"exceptionCode"] isKindOfClass:NSNumber.class]) p[@"exception_code"] = meta[@"exceptionCode"];
    if (sf_string(meta[@"terminationReason"])) p[@"termination_reason"] = meta[@"terminationReason"];
    if (sf_string(meta[@"virtualMemoryRegionInfo"])) p[@"vm_region"] = meta[@"virtualMemoryRegionInfo"];
    // an Objective-C exception not caught (iOS 17's): its name and its message
    NSDictionary *objc = sf_dict(meta[@"objectiveCexceptionReason"]) ?: sf_dict(meta[@"exceptionReason"]);
    NSString *name = sf_string(objc[@"exceptionName"]) ?: sf_string(objc[@"className"]);
    if (name) p[@"objc_exception"] = name;
    headline = mach && signal ? [NSString stringWithFormat:@"%@ (%@)", mach, signal] : mach ?: signal ?: @"Crash";
    type = name ?: signal ?: mach ?: @"Crash";
    if (name) [said addObject:headline];
    if (sf_string(objc[@"composedMessage"])) [said addObject:objc[@"composedMessage"]];
    if (sf_string(meta[@"terminationReason"])) [said addObject:meta[@"terminationReason"]];
    if (!name && mach && signal) [said insertObject:mach atIndex:0];
  } else {
    double ms = [kept[@"hang_ms"] doubleValue];
    p[@"hang_ms"] = @((long long)ms);
    headline = [NSString stringWithFormat:@"the main thread hung %.1f s", ms / 1000.0];
    type = @"Hang";
    [said addObject:headline];
  }
  value = [said componentsJoinedByString:@": "];
  // the trace as a crash log has it: what it was, then the thread's frames (binary, its UUID, the offset)
  NSMutableString *trace = [NSMutableString stringWithFormat:@"%@\n%@\n", headline, crash ? @"Crashed thread:" : @"Main thread:"];
  NSMutableArray *top = [NSMutableArray array];
  [frames enumerateObjectsUsingBlock:^(NSDictionary *f, NSUInteger i, BOOL *stop) {
    [trace appendFormat:@"%-3lu %@  0x%llx + %llu (%@)\n", (unsigned long)i, f[@"binary"], [f[@"address"] unsignedLongLongValue],
                        [f[@"offset"] unsignedLongLongValue], f[@"uuid"] ?: @"?"];
    if (top.count < 6) [top addObject:sf_frame_text(f)];
  }];
  p[@"trace"] = trace.length > SF_TRACE ? [trace substringToIndex:SF_TRACE] : trace;
  p[@"frames"] = frames;
  // no frames PostHog reads (unsymbolicated): what makes two the same issue is where they happened
  if (top.count) p[@"$exception_fingerprint"] = [NSString stringWithFormat:@"ios:%@:%@", type, [top componentsJoinedByString:@"|"]];
  NSMutableDictionary *x = [@{@"type" : type,
                              @"mechanism" : @{@"handled" : @NO, @"synthetic" : @NO, @"type" : crash ? @"signalhandler" : @"hang"}} mutableCopy];
  if (value.length) x[@"value"] = value;
  p[@"$exception_list"] = @[ x ];
  p[@"$exception_level"] = crash ? @"fatal" : @"error";
  return @{
    @"event" : @"$exception",
    @"distinct_id" : account,
    @"uuid" : uuid,
    @"timestamp" : sf_iso([kept[@"at"] doubleValue]),
    @"properties" : p,
  };
}

#ifndef SF_REPORTS_PURE
#if TARGET_OS_IPHONE
#import <MetricKit/MetricKit.h>
#else
#include <sys/sysctl.h>
#endif
#include "moonbit.h"

#if TARGET_OS_IPHONE
/// At most this many reports kept, and sent each start: the newest.
static const NSUInteger SF_MOST = 20;
/// A hang reported from this long on (MetricKit gives shorter ones too: a hitch, not what a person waited through).
static const double SF_HANG_MS = 2000;
#endif
/// At most this many reports' ids remembered as sent (pastDiagnosticPayloads gives them again for a while).
static const NSUInteger SF_SENT = 200;

static NSString *posthog_host, *posthog_key;
/// What is kept and what is sent run on it, one at a time.
static dispatch_queue_t reports_queue;
/// The account signed in this run (signed_in): reports that come after go at once.
static NSString *signed_in;

static BOOL sf_has_key(void) { return posthog_key.length > 0; }

/// Who a report goes as before an account was ever signed in on this device.
#if TARGET_OS_IPHONE
static NSString *const sf_anonymous = @"ios-anonymous";
#else
static NSString *const sf_anonymous = @"macos-anonymous";
#endif

/// The app's files: Application Support/<bundle id>/, beside the core's (apple_engine.m core_data_dir).
static NSString *sf_files_dir(void) {
  NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
  return [support.path stringByAppendingPathComponent:NSBundle.mainBundle.bundleIdentifier ?: @"mbui"];
}

static NSString *sf_kept_dir(void) { return [sf_files_dir() stringByAppendingPathComponent:@"crashes"]; }

/// reports.json: {"reporting": false when turned off, "account": the last report's, "sent": ids}. A file of the app's
/// own, not NSUserDefaults (one of Apple's required-reason APIs); read and changed under state_lock, from the UI's
/// thread too (the settings' switch), never behind reports_queue (a send waits there).
static NSObject *state_lock;

static NSMutableDictionary *state_read(void) {
  @synchronized(state_lock) {
    NSData *d = [NSData dataWithContentsOfFile:[sf_files_dir() stringByAppendingPathComponent:@"reports.json"]];
    NSDictionary *v = d ? sf_dict([NSJSONSerialization JSONObjectWithData:d options:0 error:nil]) : nil;
    return v ? v.mutableCopy : [NSMutableDictionary dictionary];
  }
}

static void state_change(void (^change)(NSMutableDictionary *state)) {
  @synchronized(state_lock) {
    NSMutableDictionary *state = state_read();
    change(state);
    NSData *d = [NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
    [NSFileManager.defaultManager createDirectoryAtPath:sf_files_dir() withIntermediateDirectories:YES attributes:nil error:nil];
    [d writeToFile:[sf_files_dir() stringByAppendingPathComponent:@"reports.json"] atomically:YES];
  }
}

/// Whether reports go (reports.json's `reporting`), read once: the settings ask it as they are drawn.
static NSNumber *reporting_on;

static BOOL sf_reporting(void) {
  @synchronized(state_lock) {
    if (!reporting_on) {
      id on = state_read()[@"reporting"];
      reporting_on = @(on ? [on boolValue] : YES);
    }
    return reporting_on.boolValue;
  }
}

/// still.fail's own app (fail.still.iphone, TestFlight's) or another build of it (still.fail preview's, a debug one):
/// its reports not counted as the released app's, as Android's android-mbui.
/// On macOS still.fail's own Mac app (fail.still.desktop, its beta fail.still.desktop.beta) is `macos`, any other build
/// `macos-mbui`; the device's model is the machine's (hw.model, "Mac16,1").
static NSDictionary *sf_here(void) {
  NSDictionary *info = NSBundle.mainBundle.infoDictionary;
  NSString *version = sf_string(info[@"CFBundleShortVersionString"]) ?: @"", *build = sf_string(info[@"CFBundleVersion"]) ?: @"";
  NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
#if TARGET_OS_IPHONE
  BOOL own = [NSBundle.mainBundle.bundleIdentifier isEqual:@"fail.still.iphone"];
  const char *model = getenv("MBUI_DEVICE_MODEL");
  NSString *device = model ? @(model) : @"";
  NSString *app = own ? @"ios" : @"ios-mbui", *system = @"iOS", *lib = own ? @"stillfail-ios" : @"stillfail-mbui-ios";
#else
  NSString *bid = NSBundle.mainBundle.bundleIdentifier ?: @"";
  BOOL own = [bid isEqual:@"fail.still.desktop"] || [bid isEqual:@"fail.still.desktop.beta"];
  char model[64] = {0};
  size_t size = sizeof(model) - 1;
  NSString *device = sysctlbyname("hw.model", model, &size, NULL, 0) == 0 ? @(model) : @"";
  NSString *app = own ? @"macos" : @"macos-mbui", *system = @"macOS", *lib = own ? @"stillfail-macos" : @"stillfail-mbui-macos";
#endif
  return @{
    @"release" : [NSString stringWithFormat:@"%@ (%@)", version, build],
    @"app" : app,
    @"$app_version" : version,
    @"$app_build" : build,
    @"$os" : system,
    @"$os_version" : [NSString stringWithFormat:@"%ld.%ld", (long)os.majorVersion, (long)os.minorVersion],
    @"$device_manufacturer" : @"Apple",
    @"$device_model" : device,
    @"$lib" : lib,
  };
}

/// Everything the app sends to PostHog, on reports_queue: YES when it went, or when nothing is to go (turned off: what
/// was to go is not kept for later, as Android's Crashes.send).
static BOOL sf_send(NSArray<NSDictionary *> *batch) {
  if (!sf_has_key()) return NO;
  if (!sf_reporting() || !batch.count) return YES;
  NSData *body = [NSJSONSerialization dataWithJSONObject:@{@"api_key" : posthog_key, @"batch" : batch} options:0 error:nil];
  if (!body) return NO;
  NSString *host = posthog_host;
  while ([host hasSuffix:@"/"]) host = [host substringToIndex:host.length - 1];
  NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[host stringByAppendingString:@"/batch/"]]];
  r.HTTPMethod = @"POST";
  r.HTTPBody = body;
  r.timeoutInterval = 15;
  [r setValue:@"application/json" forHTTPHeaderField:@"content-type"];
  __block BOOL ok = NO;
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  [[NSURLSession.sharedSession dataTaskWithRequest:r completionHandler:^(NSData *data, NSURLResponse *res, NSError *error) {
    NSInteger status = [res isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)res).statusCode : 0;
    ok = !error && status >= 200 && status <= 299;
    dispatch_semaphore_signal(done);
  }] resume];
  dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
  return ok;
}

/// The kept reports, oldest first: {id, at, path, kept}.
static NSArray<NSDictionary *> *kept_reports(void) {
  NSMutableArray *out = [NSMutableArray array];
  for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:sf_kept_dir() error:nil]) {
    if (![name hasSuffix:@".json"]) continue;
    NSString *path = [sf_kept_dir() stringByAppendingPathComponent:name];
    NSData *d = [NSData dataWithContentsOfFile:path];
    NSDictionary *k = d ? sf_dict([NSJSONSerialization JSONObjectWithData:d options:0 error:nil]) : nil;
    if (!k) {
      [NSFileManager.defaultManager removeItemAtPath:path error:nil];
      continue;
    }
    [out addObject:@{@"id" : [name stringByDeletingPathExtension], @"at" : @([k[@"at"] doubleValue]), @"path" : path, @"kept" : k}];
  }
  [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"at"] compare:b[@"at"]]; }];
  return out;
}

/// Sends what is kept as `signed_in`; what went (or was not to go) is forgotten and its id remembered as sent.
static void report_kept(void) {
  if (!signed_in || !sf_has_key()) return;
  NSArray *all = kept_reports();
  if (!all.count) return;
  NSMutableArray *batch = [NSMutableArray array];
  NSDictionary *now = sf_here();
  for (NSDictionary *r in all) {
    NSDictionary *e = sf_report_event(r[@"kept"], r[@"id"], signed_in, now);
    if (e) [batch addObject:e];
  }
  if (!sf_send(batch)) return;
  for (NSDictionary *r in all) [NSFileManager.defaultManager removeItemAtPath:r[@"path"] error:nil];
  state_change(^(NSMutableDictionary *state) {
    NSMutableArray *sent = [sf_array(state[@"sent"]) mutableCopy] ?: [NSMutableArray array];
    for (NSDictionary *r in all)
      if (![sent containsObject:r[@"id"]]) [sent addObject:r[@"id"]];
    if (sent.count > SF_SENT) [sent removeObjectsInRange:NSMakeRange(0, sent.count - SF_SENT)];
    state[@"sent"] = sent;
  });
}

#if TARGET_OS_IPHONE
/// One report MetricKit gave kept, unless it was kept or sent already.
static void sf_keep(NSString *kind, NSData *json, NSDate *at, double hang_ms, NSArray *sent) {
  NSDictionary *diagnostic = json ? sf_dict([NSJSONSerialization JSONObjectWithData:json options:0 error:nil]) : nil;
  NSString *rid = diagnostic ? sf_report_id(kind, diagnostic) : nil;
  if (!rid || [sent containsObject:rid]) return;
  NSString *path = [sf_kept_dir() stringByAppendingPathComponent:[rid stringByAppendingPathExtension:@"json"]];
  if ([NSFileManager.defaultManager fileExistsAtPath:path]) return;
  NSMutableDictionary *k = [@{@"kind" : kind, @"at" : @(floor((at ?: NSDate.date).timeIntervalSince1970 * 1000)), @"diagnostic" : diagnostic} mutableCopy];
  if (hang_ms > 0) k[@"hang_ms"] = @(hang_ms);
  [NSFileManager.defaultManager createDirectoryAtPath:sf_kept_dir() withIntermediateDirectories:YES attributes:nil error:nil];
  [[NSJSONSerialization dataWithJSONObject:k options:0 error:nil] writeToFile:path atomically:YES];
}

/// What MetricKit gave kept (only while reports go: turned off, a crash is not kept for later), the newest SF_MOST,
/// and sent at once when an account is signed in already.
static void keep_payloads(NSArray<MXDiagnosticPayload *> *payloads) {
  if (!sf_has_key() || !sf_reporting()) return;
  NSArray *sent = sf_array(state_read()[@"sent"]) ?: @[];
  for (MXDiagnosticPayload *payload in payloads) {
    for (MXCrashDiagnostic *c in payload.crashDiagnostics) sf_keep(@"crash", c.JSONRepresentation, payload.timeStampEnd, 0, sent);
    for (MXHangDiagnostic *h in payload.hangDiagnostics) {
      double ms = [h.hangDuration measurementByConvertingToUnit:NSUnitDuration.seconds].doubleValue * 1000;
      if (ms >= SF_HANG_MS) sf_keep(@"hang", h.JSONRepresentation, payload.timeStampEnd, ms, sent);
    }
  }
  NSArray *all = kept_reports();
  for (NSUInteger i = 0; i + SF_MOST < all.count; i++) [NSFileManager.defaultManager removeItemAtPath:all[i][@"path"] error:nil];
  report_kept();
}

@interface SFReports : NSObject <MXMetricManagerSubscriber>
@end

@implementation SFReports
- (void)didReceiveDiagnosticPayloads:(NSArray<MXDiagnosticPayload *> *)payloads {
  dispatch_async(reports_queue, ^{
    keep_payloads(payloads);
  });
}
@end

static SFReports *subscriber;
#endif

/// PostHog's project from the Info.plist; MetricKit asked for the reports once the app runs (its delivery comes on a
/// queue of its own, soon after), and for those it gave before (a start that ended before it kept them).
__attribute__((constructor)) static void reports_start(void) {
  NSDictionary *info = NSBundle.mainBundle.infoDictionary;
  posthog_host = sf_string(info[@"StillfailPosthogHost"]) ?: @"https://us.i.posthog.com";
  posthog_key = sf_string(info[@"StillfailPosthogKey"]) ?: @"";
  reports_queue = dispatch_queue_create("stillfail-reports", DISPATCH_QUEUE_SERIAL);
  state_lock = [NSObject new];
  if (!sf_has_key()) return;
#if TARGET_OS_IPHONE
  dispatch_async(dispatch_get_main_queue(), ^{
    subscriber = [SFReports new];
    [MXMetricManager.sharedManager addSubscriber:subscriber];
    NSArray *past = MXMetricManager.sharedManager.pastDiagnosticPayloads;
    dispatch_async(reports_queue, ^{
      keep_payloads(past);
    });
  });
#endif
}

/// An error the app got past, sent at once as `type` with `value` and `reason` (CoreFailed, UiFault: Android's
/// Crashes.handled), as the account the last report went as, or ios-anonymous before one.
static void sf_handled(NSString *type, NSString *value, NSString *reason) {
  if (!sf_has_key()) return;
  double at = floor(NSDate.date.timeIntervalSince1970 * 1000);
  dispatch_async(reports_queue, ^{
    NSString *account = signed_in ?: sf_string(state_read()[@"account"]) ?: sf_anonymous;
    NSMutableDictionary *p = [sf_here() mutableCopy];
    p[@"reason"] = reason;
    p[@"$exception_level"] = @"error";
    p[@"$exception_list"] = @[ @{
      @"type" : type,
      @"value" : value.length > 1000 ? [value substringToIndex:1000] : value,
      @"mechanism" : @{@"handled" : @YES, @"synthetic" : @NO, @"type" : @"generic"}
    } ];
    sf_send(@[ @{@"event" : @"$exception", @"distinct_id" : account, @"uuid" : NSUUID.UUID.UUIDString.lowercaseString,
              @"timestamp" : sf_iso(at), @"properties" : p} ]);
  });
}

/// What the window thread found (mbui's src/ui/journal.mbt): a hang, or what the app did while shown, sent at once as
/// `name` with the JSON's fields as its properties (Android's Crashes.hang).
static void sf_hang(NSString *json, NSString *name) {
  if (!sf_has_key()) return;
  double at = floor(NSDate.date.timeIntervalSince1970 * 1000);
  dispatch_async(reports_queue, ^{
    NSDictionary *said = sf_dict([NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]);
    if (!said) return;
    NSString *account = signed_in ?: sf_string(state_read()[@"account"]) ?: sf_anonymous;
    NSMutableDictionary *p = [sf_here() mutableCopy];
    [p addEntriesFromDictionary:said];
    sf_send(@[ @{@"event" : name, @"distinct_id" : account, @"uuid" : NSUUID.UUID.UUIDString.lowercaseString,
              @"timestamp" : sf_iso(at), @"properties" : p} ]);
  });
}

static NSString *sf_ns_string(moonbit_string_t s) {
  return [NSString stringWithCharacters:(const unichar *)s length:(NSUInteger)Moonbit_array_length(s)];
}

/// What the app tells (reports.mbt, as Android's Reports.tell): what it answers. The bar's timing is Android's alone
/// (placed, built, followed, decoded: 0).
int32_t mb_stillfail_tell(moonbit_string_t what_, moonbit_string_t a_, moonbit_string_t b_, int32_t n, int32_t m) {
  NSString *what = sf_ns_string(what_);
  // whether this host takes them: a build with PostHog's key
  if ([what isEqual:@"hello"]) return sf_has_key() ? 1 : 0;
  // whether usage statistics and error reports go out from this device: 1 yes, 0 turned off, -1 a build without
  // PostHog's key (no settings row)
  if ([what isEqual:@"reporting"]) {
    if (!sf_has_key()) return -1;
    return sf_reporting() ? 1 : 0;
  }
  // turned on (n 1) or off (0) in the settings
  if ([what isEqual:@"set_reporting"]) {
    state_change(^(NSMutableDictionary *state) {
      state[@"reporting"] = @(n != 0);
      reporting_on = @(n != 0);
    });
    return 0;
  }
  // the first account signed in (its `sub`): what was kept goes as it, and what comes after this run
  if ([what isEqual:@"signed_in"]) {
    NSString *account = sf_ns_string(a_);
    dispatch_async(reports_queue, ^{
      signed_in = account;
      if (![state_read()[@"account"] isEqual:account])
        state_change(^(NSMutableDictionary *state) {
          state[@"account"] = account;
        });
      report_kept();
    });
    return 0;
  }
  // the core failed and is started again, its reason (Android's Crashes.coreFailed)
  if ([what isEqual:@"core_failed"]) {
    sf_handled(@"CoreFailed", sf_ns_string(a_), @"core_failed");
    return 0;
  }
  // what the UI was asked that it could not do as asked, its category (Android's Crashes.uiFault)
  if ([what isEqual:@"ui_fault"]) {
    sf_handled(@"UiFault", sf_ns_string(a_), @"ui_fault");
    return 0;
  }
  // the window thread's hang, and what the app did while shown as it is hidden, as JSON (sf_hang)
  if ([what isEqual:@"hang"]) {
    sf_hang(sf_ns_string(a_), @"ui_hang");
    return 0;
  }
  if ([what isEqual:@"hang_summary"]) {
    sf_hang(sf_ns_string(a_), @"ui_hang_summary");
    return 0;
  }
  return 0;
}
#endif
