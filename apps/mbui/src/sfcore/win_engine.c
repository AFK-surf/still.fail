// The core's engine on Windows, for an app's Windows stub to #include (mbui's scripts/win.sh puts src/<app>/win_engine.c
// in place of the app's Apple stubs; moon does not track this file: touch the app's stub after changing it): the core in
// Hermes on the Rust shell (src/host/win_core.c on the prebuilt stillfail_engine.dll), handed to mbui/core as the app
// starts it. No browser session (web_auth NULL): the app signs in on @hostapi.browser_login (a loopback listener and the
// system's browser, mbui's win_browser_login.c).
#include <stdlib.h>
#include <string.h>
#include "moonbit.h"
#include "../host/win_core.c"
#include "../core/core_client.h"

static const mbc_engine hermes_engine = {mb_core_start, mb_core_send, mb_core_stop, mb_core_data_dir, NULL, mb_post, mb_post_drop};

// (MSVC's C has no constructor attribute: the app hands it over itself, before it starts the core, src/stillfail/win_engine.c)
static void use_hermes_engine(void) { mbc_use(&hermes_engine); }
