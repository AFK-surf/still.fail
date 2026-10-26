// The core's engine on Linux, for an app's Linux stub to #include (mbui's scripts/linux.sh puts src/<app>/linux_engine.c
// in place of the app's Apple stubs; moon does not track this file: touch the app's stub after changing it): the core in
// Hermes on the Rust shell (src/host/linux_core.c on the prebuilt libstillfail_engine.so), handed to mbui/core as the
// app loads. No browser session (web_auth NULL): the app signs in on @hostapi.browser_login (a loopback listener and the
// system's browser, mbui's linux_browser_login.c).
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "moonbit.h"
#include "../host/linux_core.c"
#include "../core/core_client.h"

static const mbc_engine hermes_engine = {mb_core_start, mb_core_send, mb_core_stop, mb_core_data_dir, NULL, mb_post, mb_post_drop};

__attribute__((constructor)) static void use_hermes_engine(void) { mbc_use(&hermes_engine); }

// The device's language for the app's words until the core says (src/sf/lang.mbt), and the core's when none is chosen
// (signin.mbt tell_device): MBUI_LOCALE, as Android's CoreHost.java puts it, from the session's locale (LC_ALL,
// LC_MESSAGES, LANG: zh_CN.UTF-8 said as zh-CN); not over one given.
__attribute__((constructor)) static void device_locale(void) {
  const char *l = getenv("LC_ALL");
  if (!l || !*l) l = getenv("LC_MESSAGES");
  if (!l || !*l) l = getenv("LANG");
  if (!l || !*l || !strcmp(l, "C") || !strcmp(l, "POSIX")) return;
  char tag[32];
  size_t n = 0;
  for (; l[n] && l[n] != '.' && l[n] != '@' && n + 1 < sizeof tag; n++) tag[n] = l[n] == '_' ? '-' : l[n];
  tag[n] = 0;
  if (n) setenv("MBUI_LOCALE", tag, 0);
}

// The machine's name (its host name) in MBUI_DEVICE_NAME, the machine the core names this device by where the person's
// devices are listed (signin.mbt tell_device); not over one given.
__attribute__((constructor)) static void device_name(void) {
  char name[256];
  if (gethostname(name, sizeof name) != 0) return;
  name[sizeof name - 1] = 0;
  if (*name) setenv("MBUI_DEVICE_NAME", name, 0);
}
