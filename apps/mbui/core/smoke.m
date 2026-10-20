// A headless run of the core (src/host/apple_core.mm) against still.fail cloud: subscribe to the accounts, ask for a
// login URL (printed, never opened: nobody logs in), stop. Built and run by `scripts/core.sh smoke`.
//   smoke <data dir> [cloud origin]        (MB_CORE_BUNDLE: the core's script)
// Exit 0 when the accounts came and auth.begin answered with a URL.
#import <Foundation/Foundation.h>
#include <mach/mach.h>
#include <time.h>
#include "core_api.h"

static double t0;
static dispatch_semaphore_t got_accounts, got_auth;
static int accounts_ok, auth_ok, failed;
static double first_ms = -1, accounts_ms = -1, auth_ms = -1;
static NSString *auth_url;

static double now_ms(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (double)t.tv_sec * 1000.0 + (double)t.tv_nsec / 1e6;
}

static double footprint_mb(void) {
  task_vm_info_data_t info;
  mach_msg_type_number_t n = TASK_VM_INFO_COUNT;
  if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &n) != KERN_SUCCESS) return -1;
  return info.phys_footprint / 1048576.0;
}

static NSString *find_url(id v) {
  if ([v isKindOfClass:NSString.class]) return [v hasPrefix:@"http"] ? v : nil;
  if ([v isKindOfClass:NSDictionary.class]) {
    for (id k in v) {
      NSString *u = find_url(v[k]);
      if (u) return u;
    }
  }
  if ([v isKindOfClass:NSArray.class]) {
    for (id x in v) {
      NSString *u = find_url(x);
      if (u) return u;
    }
  }
  return nil;
}

static void on_message(const char *json, size_t len, const uint8_t *bytes, size_t blen, void *ctx) {
  double at = now_ms() - t0;
  if (first_ms < 0) first_ms = at;
  NSString *text = [[NSString alloc] initWithBytes:json length:len encoding:NSUTF8StringEncoding];
  printf("[%8.1f ms] <- %s%s\n", at, text.length > 600 ? [[text substringToIndex:600] stringByAppendingString:@"…"].UTF8String : text.UTF8String,
         bytes ? [NSString stringWithFormat:@" (+%zu bytes)", blen].UTF8String : "");
  fflush(stdout);
  NSDictionary *m = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:json length:len] options:0 error:nil];
  if (![m isKindOfClass:NSDictionary.class]) return;
  if (m[@"fatal"]) {
    failed = 1;
    dispatch_semaphore_signal(got_accounts);
    dispatch_semaphore_signal(got_auth);
    return;
  }
  NSNumber *id_ = m[@"id"];
  if (id_.intValue == 1 && (m[@"value"] || m[@"error"]) && accounts_ms < 0) {
    accounts_ms = at;
    accounts_ok = m[@"value"] != nil;
    dispatch_semaphore_signal(got_accounts);
  } else if (id_.intValue == 2 && auth_ms < 0) {
    auth_ms = at;
    auth_url = m[@"ok"] ? find_url(m[@"ok"]) : nil;
    auth_ok = auth_url != nil;
    dispatch_semaphore_signal(got_auth);
  }
}

static void tell(NSString *json) {
  printf("[%8.1f ms] -> %s\n", now_ms() - t0, json.UTF8String);
  NSData *d = [json dataUsingEncoding:NSUTF8StringEncoding];
  mb_core_send(d.bytes, d.length, NULL, 0);
}

int main(int argc, char **argv) {
  @autoreleasepool {
    if (argc < 2) {
      fprintf(stderr, "usage: smoke <data dir> [cloud origin]\n");
      return 2;
    }
    const char *cloud = argc > 2 ? argv[2] : "https://app.still.fail";
    got_accounts = dispatch_semaphore_create(0);
    got_auth = dispatch_semaphore_create(0);
    double before = footprint_mb();
    t0 = now_ms();
    mb_core_start(argv[1], cloud, 0, on_message, NULL);
    printf("[%8.1f ms] core thread up (data %s, cloud %s)\n", now_ms() - t0, argv[1], cloud);
    tell(@"{\"id\":1,\"subscribe\":{\"topic\":\"accounts\"}}");
    long late = dispatch_semaphore_wait(got_accounts, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
    if (!late && !failed) {
      tell(@"{\"id\":2,\"call\":\"auth.begin\",\"params\":{\"redirect_uri\":\"stillfail://auth/callback\",\"return_to\":\"/\"}}");
      dispatch_semaphore_wait(got_auth, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
    }
    // A moment more for what the core started on its own (the changelog's fetch: bytes from the shell into the JS).
    const char *linger = getenv("MB_SMOKE_LINGER_MS");
    double linger_ms = linger ? atof(linger) : 1500;
    dispatch_semaphore_wait(dispatch_semaphore_create(0), dispatch_time(DISPATCH_TIME_NOW, (int64_t)(linger_ms * NSEC_PER_MSEC)));
    double running = footprint_mb();
    double t_stop = now_ms();
    mb_core_stop();
    printf("\n== smoke ==\n");
    printf("first message      %.1f ms after mb_core_start\n", first_ms);
    printf("accounts value     %s (%.1f ms)\n", accounts_ok ? "yes" : "NO", accounts_ms);
    printf("auth.begin URL     %s (%.1f ms)\n", auth_url ? auth_url.UTF8String : "NONE", auth_ms);
    printf("stop               %.1f ms\n", now_ms() - t_stop);
    printf("footprint          %.1f MB before start, %.1f MB running (%.0f ms after auth.begin), %.1f MB after stop\n", before, running, linger_ms, footprint_mb());
    int ok = accounts_ok && auth_ok && !failed;
    printf("result             %s\n", ok ? "OK" : "FAILED");
    return ok ? 0 : 1;
  }
}
