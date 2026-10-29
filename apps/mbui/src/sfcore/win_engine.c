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

// (a remote screen's frames acknowledged straight to its station by the shell: mb_core_screen_ack)
static const mbc_engine hermes_engine = {mb_core_start, mb_core_send, mb_core_stop, mb_core_data_dir, NULL, mb_post, mb_post_drop, mb_core_screen_ack};

// The computer's name (设置 › 系统 › 系统信息: its device name) in MBUI_DEVICE_NAME, the machine the core names this
// device by where the person's devices are listed (signin.mbt tell_device): which of their computers it is. Not over
// one given.
static void device_name(void) {
  WCHAR name[256];
  DWORD n = 256;
  if (_wgetenv(L"MBUI_DEVICE_NAME") || !GetComputerNameExW(ComputerNamePhysicalDnsHostname, name, &n) || n == 0) return;
  _wputenv_s(L"MBUI_DEVICE_NAME", name);
}

// mbui's (win_stream.cpp): a remote screen's records taken straight from the shell into the stream the app routed them
// to, and how what it took is acknowledged to the station
int mb_stream_route_take(uint64_t route, int kind, int key, uint64_t seq, uint64_t ts, const uint8_t *bytes, size_t len);
void mb_stream_route_acks(int (*ack)(double route, double ts));

// (MSVC's C has no constructor attribute: the app hands it over itself, before it starts the core, src/stillfail/win_engine.c)
static void use_hermes_engine(void) {
  device_name();
  mbc_use(&hermes_engine);
  // a remote screen's frames the shell reads itself go to the stream the app routed them to, past its queue (mbui's
  // win_stream.cpp), acknowledged to the station through the shell
  mb_core_route_media(mb_stream_route_take);
  mb_stream_route_acks(mb_core_screen_ack);
}
