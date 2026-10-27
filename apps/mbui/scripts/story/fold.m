// fold: asks the simulator's SpringBoard (iOS 27.1, iPhone Duo) to swap its screens, folded to open or back, as its
// own display tool does (SBSDisplayToolService, SpringBoardServices): `fold swap [seconds]`. Its entitlement is in its
// __TEXT,__entitlements (scripts/story/fold.ent), as the simulator reads an app's. It ends once SpringBoard answers.
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <unistd.h>
// the settings' layout as SpringBoardServices has it ({?=qdqqBqdd}): duration, orientation and profile as it logs them
typedef struct { long long a; double duration; long long orientation; long long profile; BOOL wait; long long f; double g; double h; } Swap;
int main(int argc, char **argv) {
  dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
  id s = [[NSClassFromString(@"SBSDisplayToolService") alloc] init];
  Swap w = {0};
  w.duration = argc > 2 ? atof(argv[2]) : 0.64;
  w.wait = YES;
  // (what the other fields say is being found out: `fold swap S A ORIENTATION PROFILE F`)
  if (argc > 3) w.a = atoll(argv[3]);
  if (argc > 4) w.orientation = atoll(argv[4]);
  if (argc > 5) w.profile = atoll(argv[5]);
  if (argc > 6) w.f = atoll(argv[6]);
  SEL sel = NSSelectorFromString(@"swapDisplayWithSettings:completion:");
  void (*send)(id, SEL, Swap, void (^)(void)) = (void *)dlsym(RTLD_DEFAULT, "objc_msgSend");
  send(s, sel, w, ^{ printf("fold: swapped\n"); fflush(stdout); _exit(0); });
  sleep(15);
  printf("fold: no answer in 15 s\n");
  _exit(1);
}
