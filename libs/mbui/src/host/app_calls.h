// The app's own native calls (@hostapi.app_said, app_tell): what an app does natively that is its own and not a
// platform's (a service of its own on this machine, a file only it keeps). The app hands them over as it starts, before
// its first frame (a constructor of its stub, or its main's own call where the C has none: MSVC's), and mbui passes
// each call on as it is: `said` answers a name with text the app reads, `tell` asks it to do something. Before that,
// and in an app that hands none, `said` is "" and `tell` does nothing. Included once by each platform's host.
#ifndef MB_APP_CALLS_H
#define MB_APP_CALLS_H

#include "moonbit.h"

typedef moonbit_string_t (*mb_app_said_fn)(moonbit_string_t name);
typedef void (*mb_app_tell_fn)(moonbit_string_t name, moonbit_string_t arg);

static mb_app_said_fn mb_app_said_to;
static mb_app_tell_fn mb_app_tell_to;

#if defined(_WIN32)
__declspec(dllexport)
#else
__attribute__((visibility("default")))
#endif
void mb_host_app_calls(mb_app_said_fn said, mb_app_tell_fn tell) {
  mb_app_said_to = said;
  mb_app_tell_to = tell;
}

// (name and arg borrowed: host_native.mbt's #borrow; what `said` gives is the caller's)
moonbit_string_t mb_host_app_said(moonbit_string_t name) {
  return mb_app_said_to ? mb_app_said_to(name) : moonbit_make_string(0, 0);
}

void mb_host_app_tell(moonbit_string_t name, moonbit_string_t arg) {
  if (mb_app_tell_to) mb_app_tell_to(name, arg);
}

#endif
