// What asks the person on iOS for a told story (sffixture's story_ask_person): the system's prompt, as the core's host
// asks it to unlock a vault (src/host/apple_core.mm person_ask: LocalAuthentication's device owner policy, Touch ID or
// Face ID, the reason in it). Begun here, its answer read as it comes (0 not yet, 1 yes, 2 no).
#import <Foundation/Foundation.h>
#import <LocalAuthentication/LocalAuthentication.h>
#include <stdatomic.h>
#include "moonbit.h"

static _Atomic int32_t answered = 0;

void mb_sffix_ask_person(moonbit_bytes_t reason) {
  NSString *why = [[NSString alloc] initWithBytes:reason length:Moonbit_array_length(reason) encoding:NSUTF8StringEncoding];
  atomic_store(&answered, 0);
  LAContext *ask = [LAContext new];
  [ask evaluatePolicy:LAPolicyDeviceOwnerAuthentication localizedReason:why.length ? why : @"unlock"
                reply:^(BOOL yes, NSError *e) { atomic_store(&answered, yes ? 1 : 2); }];
}

int32_t mb_sffix_person_answered(void) { return atomic_load(&answered); }

// Readied as the app starts: the system's first prompt otherwise comes up seconds after it is asked for.
void mb_sffix_person_ready(void) {
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *e = nil;
    [[LAContext new] canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:&e];
  });
}
