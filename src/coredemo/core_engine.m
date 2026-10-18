// The core's engine, linked into this app alone so the default demo stays without the 57 MB shell: JavaScriptCore on
// the Rust shell (src/host/apple_core.m with out/core/<target>/libstillfail_shell.a) and the browser session that
// brings a sign-in back (src/host/apple_auth.m), and loopback listeners (src/host/apple_listen.m), handed to mbui/core
// as the app loads.
#include "../host/apple_core.m"
#include "../host/apple_auth.m"
#include "../host/apple_listen.m"
#include <spawn.h>
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

static const mbc_engine jsc_engine = {mb_core_start, mb_core_send,   mb_core_stop,      core_data_dir,
                                      mb_web_auth,   mb_listen_open, mb_listen_respond, mb_listen_close};

__attribute__((constructor)) static void use_jsc_engine(void) { mbc_use(&jsc_engine); }

// An environment variable for the app's MoonBit (MBUI_CORE_SIGNIN), "" when unset.
moonbit_string_t mb_coredemo_env(moonbit_string_t name) {
  const char *v = getenv(mb_ns_from_string(name).UTF8String);
  return mb_string_from_ns(v ? @(v) : @"");
}

// Opens `url` in a browser, as a command-line tool does: $BROWSER (its first entry, when it lists several) with the
// URL, else `open` from PATH (the default browser). A station's login sets BROWSER and puts an `open` of its own first
// on PATH, both taking the page instead of opening it (ember docs/remote-login.md). 1 when one was started.
extern char **environ;
int32_t mb_coredemo_open_url(moonbit_string_t url) {
  NSString *u = mb_ns_from_string(url);
  const char *browser = getenv("BROWSER");
  NSString *program = browser && *browser ? [@(browser) componentsSeparatedByString:@":"].firstObject : @"open";
  if (program.length == 0) program = @"open";
  char *argv[] = {(char *)program.UTF8String, (char *)u.UTF8String, NULL};
  pid_t pid;
  // Not waited for: `open` returns at once; a browser started directly keeps running after us.
  return posix_spawnp(&pid, argv[0], NULL, NULL, argv, environ) == 0;
}
