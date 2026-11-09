// src/host/apple_reports.m's tests: a report MetricKit gave (its JSON, as MXCrashDiagnostic's and MXHangDiagnostic's
// JSONRepresentation have it) turned into the `$exception` event PostHog is sent. Run on a Mac by
// scripts/ios-reports-test.sh (Foundation's alone: no MetricKit, no device).
#define SF_REPORTS_PURE 1
#include "../src/host/apple_reports.m"

static int failed;

#define CHECK(c)                                                      \
  do {                                                                \
    if (!(c)) {                                                       \
      fprintf(stderr, "%s:%d: failed: %s\n", __FILE__, __LINE__, #c); \
      failed = 1;                                                     \
    }                                                                 \
  } while (0)
#define SAME(got, want)                                                                                         \
  do {                                                                                                          \
    id got_ = (got), want_ = (want);                                                                            \
    if (!(got_ == want_ || [got_ isEqual:want_])) {                                                             \
      fprintf(stderr, "%s:%d: %s\n  gave %s\n  want %s\n", __FILE__, __LINE__, #got, [got_ description].UTF8String, \
              [want_ description].UTF8String);                                                                  \
      failed = 1;                                                                                               \
    }                                                                                                           \
  } while (0)

static NSDictionary *frame(NSString *binary, NSString *uuid, long long offset, long long address, NSDictionary *caller) {
  NSMutableDictionary *f = [@{@"binaryName" : binary, @"binaryUUID" : uuid, @"offsetIntoBinaryTextSegment" : @(offset),
                              @"address" : @(address), @"sampleCount" : @1} mutableCopy];
  if (caller) f[@"subFrames"] = @[ caller ];
  return f;
}

static NSString *const APP_UUID = @"0B6F2A54-3A1C-3C61-9D0E-5C2B7D3B8A11";
static NSString *const KERNEL_UUID = @"A1B2C3D4-0000-3000-8000-0000000000AA";

// A crash as build 37 on an iPhone18,2 sent it: SIGSEGV in the app's own binary, called from UIKit; another thread's
// stack first in the list, not the crashed one.
static NSDictionary *segv(void) {
  NSDictionary *crashed = frame(@"mbui", APP_UUID, 0x1234, 0x100001234,
                                frame(@"mbui", APP_UUID, 0x5678, 0x100005678, frame(@"UIKitCore", KERNEL_UUID, 0x9abc, 0x18f009abc, nil)));
  NSDictionary *other = frame(@"libsystem_kernel.dylib", KERNEL_UUID, 0x10, 0x1e0000010, nil);
  return @{
    @"version" : @"1.0.0",
    @"callStackTree" : @{
      @"callStackPerThread" : @YES,
      @"callStacks" : @[ @{@"threadAttributed" : @NO, @"callStackRootFrames" : @[ other ]},
                         @{@"threadAttributed" : @YES, @"callStackRootFrames" : @[ crashed ]} ],
    },
    @"diagnosticMetaData" : @{
      @"appVersion" : @"0.1.0",
      @"appBuildVersion" : @"37",
      @"osVersion" : @"iPhone OS 27.2 (24C101)",
      @"deviceType" : @"iPhone18,2",
      @"platformArchitecture" : @"arm64e",
      @"bundleIdentifier" : @"fail.still.iphone",
      @"isTestFlightApp" : @YES,
      @"exceptionType" : @1,
      @"exceptionCode" : @0,
      @"signal" : @11,
      @"terminationReason" : @"Namespace SIGNAL, Code 11 Segmentation fault: 11",
      @"virtualMemoryRegionInfo" : @"0 is not in any region.",
    },
  };
}

static NSDictionary *const_here(void) {
  return @{@"app" : @"ios", @"$lib" : @"stillfail-ios", @"release" : @"0.1.0 (38)", @"$os" : @"iOS", @"$device_manufacturer" : @"Apple"};
}

int main(void) {
  @autoreleasepool {
    NSString *rid = sf_report_id(@"crash", segv());
    // the id: 16 bytes of hex, the same for the same report however its dictionary was made, another for a hang's
    CHECK(rid.length == 32);
    NSMutableDictionary *again = [NSMutableDictionary dictionary];
    for (NSString *k in [segv().allKeys reverseObjectEnumerator]) again[k] = segv()[k];
    SAME(sf_report_id(@"crash", again), rid);
    CHECK(![sf_report_id(@"hang", segv()) isEqual:rid]);
    // its uuid: of the id, a name's (version 5, RFC 4122's variant)
    NSString *uuid = sf_report_uuid(rid);
    CHECK([[NSUUID alloc] initWithUUIDString:uuid] != nil);
    SAME([uuid substringWithRange:NSMakeRange(14, 1)], @"5");
    CHECK([@"89ab" containsString:[uuid substringWithRange:NSMakeRange(19, 1)]]);
    SAME(sf_report_uuid(rid), uuid);

    NSDictionary *e = sf_report_event(@{@"kind" : @"crash", @"at" : @1794030000123.0, @"diagnostic" : segv()}, rid, @"108123", const_here());
    SAME(e[@"event"], @"$exception");
    SAME(e[@"distinct_id"], @"108123");
    SAME(e[@"uuid"], uuid);
    SAME(e[@"timestamp"], @"2026-11-07T05:40:00.123Z");
    NSDictionary *p = e[@"properties"];
    SAME(p[@"$exception_level"], @"fatal");
    SAME(p[@"reason"], @"crash");
    NSDictionary *x = [p[@"$exception_list"] firstObject];
    SAME(x[@"type"], @"SIGSEGV");
    SAME(x[@"value"], @"EXC_BAD_ACCESS: Namespace SIGNAL, Code 11 Segmentation fault: 11");
    SAME(x[@"mechanism"][@"handled"], @NO);
    SAME(x[@"mechanism"][@"type"], @"signalhandler");
    // the build and device the report says, over the app's now
    SAME(p[@"release"], @"0.1.0 (37)");
    SAME(p[@"$app_version"], @"0.1.0");
    SAME(p[@"$app_build"], @"37");
    SAME(p[@"$os_version"], @"27.2");
    SAME(p[@"os_build"], @"iPhone OS 27.2 (24C101)");
    SAME(p[@"$device_model"], @"iPhone18,2");
    SAME(p[@"app"], @"ios");
    SAME(p[@"$lib"], @"stillfail-ios");
    SAME(p[@"testflight"], @YES);
    SAME(p[@"signal"], @"SIGSEGV");
    SAME(p[@"exception_type"], @"EXC_BAD_ACCESS");
    SAME(p[@"exception_code"], @0);
    SAME(p[@"vm_region"], @"0 is not in any region.");
    // the attributed thread's frames, innermost first, each with what the dSYM is read by
    NSArray *frames = p[@"frames"];
    SAME(@(frames.count), @3);
    SAME(frames[0], (@{@"binary" : @"mbui", @"uuid" : APP_UUID, @"offset" : @0x1234, @"address" : @0x100001234}));
    SAME(frames[2][@"binary"], @"UIKitCore");
    SAME(p[@"$exception_fingerprint"], @"ios:SIGSEGV:mbui + 0x1234|mbui + 0x5678|UIKitCore + 0x9abc");
    NSString *trace = p[@"trace"];
    CHECK([trace hasPrefix:@"EXC_BAD_ACCESS (SIGSEGV)\nCrashed thread:\n0   mbui"]);
    CHECK([trace containsString:@"0x100005678 + 22136 (0B6F2A54-3A1C-3C61-9D0E-5C2B7D3B8A11)"]);
    CHECK(![trace containsString:@"libsystem_kernel"]);

    // an Objective-C exception not caught: its name the type, its message said
    NSMutableDictionary *objc = segv().mutableCopy, *meta = [segv()[@"diagnosticMetaData"] mutableCopy];
    meta[@"signal"] = @6;
    meta[@"exceptionType"] = @10;
    meta[@"terminationReason"] = nil;
    meta[@"objectiveCexceptionReason"] = @{@"exceptionName" : @"NSInvalidArgumentException", @"composedMessage" : @"-[__NSCFNumber length]: unrecognized selector"};
    objc[@"diagnosticMetaData"] = meta;
    NSDictionary *o = sf_report_event(@{@"kind" : @"crash", @"at" : @0, @"diagnostic" : objc}, sf_report_id(@"crash", objc), @"108123", const_here())[@"properties"];
    SAME([o[@"$exception_list"] firstObject][@"type"], @"NSInvalidArgumentException");
    SAME([o[@"$exception_list"] firstObject][@"value"], @"EXC_CRASH (SIGABRT): -[__NSCFNumber length]: unrecognized selector");
    SAME(o[@"objc_exception"], @"NSInvalidArgumentException");
    CHECK([o[@"$exception_fingerprint"] hasPrefix:@"ios:NSInvalidArgumentException:mbui + 0x1234|"]);

    // a hang: the main thread's frames, an error, how long
    NSMutableDictionary *hang = segv().mutableCopy;
    hang[@"diagnosticMetaData"] = @{@"appVersion" : @"0.1.0", @"appBuildVersion" : @"37", @"hangDuration" : @"3.25 sec"};
    NSDictionary *h = sf_report_event(@{@"kind" : @"hang", @"at" : @0, @"hang_ms" : @3250, @"diagnostic" : hang}, sf_report_id(@"hang", hang), @"108123", const_here())[@"properties"];
    SAME(h[@"$exception_level"], @"error");
    SAME(h[@"reason"], @"hang");
    SAME(h[@"hang_ms"], @3250);
    SAME([h[@"$exception_list"] firstObject][@"type"], @"Hang");
    SAME([h[@"$exception_list"] firstObject][@"value"], @"the main thread hung 3.2 s");
    SAME([h[@"$exception_list"] firstObject][@"mechanism"][@"type"], @"hang");
    CHECK([h[@"$exception_fingerprint"] hasPrefix:@"ios:Hang:mbui + 0x1234|"]);
    CHECK([h[@"trace"] containsString:@"Main thread:\n"]);

    // what is not a report this makes: no account, a kind of its own, no diagnostic, no id
    CHECK(sf_report_event(@{@"kind" : @"crash", @"at" : @0, @"diagnostic" : segv()}, rid, @"", const_here()) == nil);
    CHECK(sf_report_event(@{@"kind" : @"cpu", @"at" : @0, @"diagnostic" : segv()}, rid, @"108123", const_here()) == nil);
    CHECK(sf_report_event(@{@"kind" : @"crash", @"at" : @0}, rid, @"108123", const_here()) == nil);
    CHECK(sf_report_event(@{@"kind" : @"crash", @"at" : @0, @"diagnostic" : segv()}, @"short", @"108123", const_here()) == nil);
    // a report with no stacks: still an event, with no fingerprint (PostHog groups it by its type)
    NSDictionary *bare = sf_report_event(@{@"kind" : @"crash", @"at" : @0, @"diagnostic" : @{@"diagnosticMetaData" : @{@"signal" : @9}}}, rid, @"108123", const_here());
    SAME([bare[@"properties"][@"$exception_list"] firstObject][@"type"], @"SIGKILL");
    CHECK(bare[@"properties"][@"$exception_fingerprint"] == nil);
    SAME(bare[@"properties"][@"release"], @"0.1.0 (38)");
    // the whole event is JSON PostHog takes
    CHECK([NSJSONSerialization isValidJSONObject:e]);
  }
  if (!failed) printf("ios reports: ok\n");
  return failed;
}
