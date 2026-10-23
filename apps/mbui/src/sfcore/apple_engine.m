// The core's engine on Apple's systems, for an app's native stub to #include (moon.pkg cannot pick stubs per OS, and
// cc-link-flags go only on a main package, so the app links it: src/coredemo/core_engine.m, src/stillfail/core_engine.m;
// moon does not track this file: touch the app's stub after changing it). Hermes on the Rust shell (src/host/apple_core.mm,
// built by scripts/core.sh engine into out/core/<target>/libmbui_core.a, which the app links with
// out/core/<target>/libstillfail_shell.a and Hermes's framework) and, on iOS, the browser session that brings a sign-in
// back (src/host/apple_auth.m), handed to mbui/core as the app loads. On macOS none (web_auth NULL): the app signs in on
// @hostapi.browser_login (a loopback listener and the default browser, as the desktop app's), not in
// ASWebAuthenticationSession's, which is Safari's whatever the browser chosen.
#include "../host/apple_auth.m"
#include "../core/core_client.h"
#include "../host/apple.h"

// $MBUI_CORE_DATA, else ~/Library/Application Support/<bundle id, or mbui>/core: the app's own, never the installed
// still.fail app's.
static const char *core_data_dir(void) {
  static char *dir;
  if (dir) return dir;
  const char *env = getenv("MBUI_CORE_DATA");
  NSString *path = env && *env ? @(env) : nil;
  if (!path) {
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSString *app = NSBundle.mainBundle.bundleIdentifier ?: @"mbui";
    path = [[support.path stringByAppendingPathComponent:app] stringByAppendingPathComponent:@"core"];
  }
  [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
  dir = strdup(path.fileSystemRepresentation);
  return dir;
}

#if TARGET_OS_IPHONE
static const mbc_engine hermes_engine = {mb_core_start, mb_core_send, mb_core_stop, core_data_dir, mb_web_auth, mb_post, mb_post_drop};
#else
static const mbc_engine hermes_engine = {mb_core_start, mb_core_send, mb_core_stop, core_data_dir, NULL, mb_post, mb_post_drop};
#endif

__attribute__((constructor)) static void use_hermes_engine(void) { mbc_use(&hermes_engine); }

#if TARGET_OS_IPHONE
#include <sys/utsname.h>
// The phone's model, as Android's CoreHost.java puts its maker's and model in MBUI_DEVICE_MODEL (the device's name the
// core makes: signin.mbt tell_device): its machine identifier (iPhone17,1; the simulator's the device it plays).
__attribute__((constructor)) static void device_model(void) {
  const char *sim = getenv("SIMULATOR_MODEL_IDENTIFIER");
  struct utsname u;
  if (!sim && uname(&u) != 0) return;
  setenv("MBUI_DEVICE_MODEL", sim ? sim : u.machine, 0);
}
#endif
