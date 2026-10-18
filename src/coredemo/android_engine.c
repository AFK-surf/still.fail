// core_engine.m's Android twin, compiled by scripts/android.sh for APP=coredemo (moon.pkg cannot pick stubs per OS,
// so moon never sees this file): the core in ember's Hermes engine (src/host/android_core.c), handed to mbui/core as
// the library loads. No browser session yet (web_auth NULL: @core.sign_in says so); MBUI_AUTH_BEGIN=1 and the other
// variables come from the intent's `env` extra (MainActivity: `am start … --es env MBUI_AUTH_BEGIN=1`).
#include <stdlib.h>
#include <string.h>
#include "moonbit.h"
#include "../host/android_core.c"
#include "../core/core_client.h"

static const mbc_engine hermes_engine = {mb_core_start, mb_core_send, mb_core_stop, mb_core_data_dir, NULL};

__attribute__((constructor)) static void use_hermes_engine(void) { mbc_use(&hermes_engine); }

// An environment variable for the app's MoonBit, "" when unset (names and values ASCII; anything else becomes '?').
moonbit_string_t mb_coredemo_env(moonbit_string_t name) {
  int32_t n = Moonbit_array_length(name);
  char key[128];
  if (n >= (int32_t)sizeof key) return moonbit_make_string_raw(0);
  for (int32_t i = 0; i < n; i++) key[i] = name[i] < 0x80 ? (char)name[i] : '?';
  key[n] = 0;
  const char *v = getenv(key);
  if (!v) return moonbit_make_string_raw(0);
  int32_t m = (int32_t)strlen(v);
  moonbit_string_t out = moonbit_make_string_raw(m);
  for (int32_t i = 0; i < m; i++) out[i] = (unsigned char)v[i] < 0x80 ? (uint16_t)v[i] : '?';
  return out;
}

// The engine's name, for the header.
moonbit_string_t mb_coredemo_engine(void) {
  static const char name[] = "Hermes";
  moonbit_string_t out = moonbit_make_string_raw((int32_t)sizeof name - 1);
  for (int32_t i = 0; i < (int32_t)sizeof name - 1; i++) out[i] = (uint16_t)name[i];
  return out;
}
