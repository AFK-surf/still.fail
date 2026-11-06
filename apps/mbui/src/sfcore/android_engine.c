// The core's engine on Android, for an app's Android source to #include (scripts/android.sh compiles
// src/<app>/android_engine.c for the apps with the core; moon never sees these files): the core in still.fail's Hermes
// engine (src/host/android_core.c), handed to mbui/core as the library loads, with the shell's remote screens' frames
// handed to mbui's streams (mb_stream_route_take). Its browser session (web_auth) is mbui's android_host.c
// mb_host_web_auth: a Custom Tab the browser comes back from on the app's own scheme, its package's, as an intent the
// system hands the app (thawing it first: a loopback listener left in the background is frozen by some vendors' systems
// and the browser's way back hangs).
#include <stdlib.h>
#include <string.h>
#include "moonbit.h"
#include "../host/android_core.c"
#include "../core/core_client.h"

// mbui's android_host.c: the system's browser session, and the scheme it comes back on
void mb_host_web_auth(const char *url, const char *scheme, void (*done)(const char *, const char *, void *), void *ctx);
const char *mb_host_app_scheme(void);

static const mbc_engine hermes_engine = {mb_core_start, mb_core_send, mb_core_stop, mb_core_data_dir, mb_host_web_auth, mb_post, mb_post_drop, mb_core_screen_ack, mb_host_app_scheme};

// mbui's android_host.c: a remote screen's frames taken straight to the stream the app routed them to
int mb_stream_route_take(uint64_t route, int kind, int key, uint64_t seq, uint64_t ts, const uint8_t *bytes, size_t len);
void mb_stream_route_acks(int (*ack)(double route, double ts));

__attribute__((constructor)) static void use_hermes_engine(void) {
  mbc_use(&hermes_engine);
  // a remote screen's frames the shell reads itself go to the stream the app routed them to, past its queue (mbui's
  // Streams.java: decoded onto the stream's own surface), acknowledged to the station through the shell
  mb_core_route_media(mb_stream_route_take);
  mb_stream_route_acks(mb_core_screen_ack);
}
