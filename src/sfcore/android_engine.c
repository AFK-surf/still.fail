// The core's engine on Android, for an app's Android source to #include (scripts/android.sh compiles
// src/<app>/android_engine.c for the apps with the core; moon never sees these files): the core in ember's Hermes
// engine (src/host/android_core.c), handed to mbui/core as the library loads. No browser session (web_auth NULL):
// apps sign in on @host.browser_login instead (a loopback listener and a Custom Tab, android_host.c).
#include <stdlib.h>
#include <string.h>
#include "moonbit.h"
#include "../host/android_core.c"
#include "../core/core_client.h"

static const mbc_engine hermes_engine = {mb_core_start, mb_core_send, mb_core_stop, mb_core_data_dir, NULL};

__attribute__((constructor)) static void use_hermes_engine(void) { mbc_use(&hermes_engine); }
