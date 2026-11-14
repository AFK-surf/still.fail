// The app's own native calls, handed to mbui's host as the app starts (mbui's app_calls.h): this machine's station on
// the desktops, `local_station` (what it is, as JSON; "" none) and `local_station_act` (something done to it), read by
// sfbase's local_station.mbt through @hostapi.app_said and app_tell. Included by a desktop's engine file
// (src/stillfail/core_engine.m on macOS, win_engine.c, linux_engine.c) after its station's file, which defines
// sf_station_said and sf_station_act.
#ifndef SF_STATION_CALLS_H
#define SF_STATION_CALLS_H
#include "moonbit.h"

typedef moonbit_string_t (*sf_said_fn)(moonbit_string_t name);
typedef void (*sf_tell_fn)(moonbit_string_t name, moonbit_string_t arg);
void mb_host_app_calls(sf_said_fn said, sf_tell_fn tell);

// whether MoonBit's words `s` are the ASCII `name`
static int sf_call_is(moonbit_string_t s, const char *name) {
  int32_t n = Moonbit_array_length(s);
  for (int32_t i = 0; i < n; i++)
    if (!name[i] || s[i] != (uint16_t)(unsigned char)name[i]) return 0;
  return name[n] == 0;
}

static moonbit_string_t sf_app_said(moonbit_string_t name) {
  if (sf_call_is(name, "local_station")) return sf_station_said();
  return moonbit_make_string_raw(0);
}

static void sf_app_tell(moonbit_string_t name, moonbit_string_t arg) {
  if (sf_call_is(name, "local_station_act")) sf_station_act(arg);
}

// handed over: by a constructor where the C has them, by main.mbt's mb_stillfail_core_linked on Windows
static void sf_app_calls_use(void) { mb_host_app_calls(sf_app_said, sf_app_tell); }
#ifndef _MSC_VER
__attribute__((constructor)) static void sf_app_calls_at_start(void) { sf_app_calls_use(); }
#endif

#endif
