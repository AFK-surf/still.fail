// The core's engine on Apple's systems, for an app's native stub to #include (moon.pkg cannot pick stubs per OS, and
// cc-link-flags go only on a main package, so the app links it: src/coredemo/core_engine.m, src/stillfail/core_engine.m;
// moon does not track this file: touch the app's stub after changing it). JavaScriptCore on the Rust shell
// (src/host/apple_core.m with out/core/<target>/libstillfail_shell.a) and the browser session that brings a sign-in
// back (src/host/apple_auth.m), handed to mbui/core as the app loads.
#include "../host/apple_core.m"
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

static const mbc_engine jsc_engine = {mb_core_start, mb_core_send, mb_core_stop, core_data_dir, mb_web_auth};

__attribute__((constructor)) static void use_jsc_engine(void) { mbc_use(&jsc_engine); }
