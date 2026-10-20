// core_engine.m's Android twin, compiled by scripts/android.sh for APP=coredemo (moon never sees this file): the core
// in ember's Hermes engine (src/sfcore/android_engine.c). MBUI_AUTH_BEGIN=1 and the other variables come from the
// intent's `env` extra (MainActivity: `am start … --es env MBUI_AUTH_BEGIN=1`).
#include "../sfcore/android_engine.c"

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

// MBUI_SECURE_TEST=1: secure.* round-tripped through the host (android_core.c); 1 when it was started.
int32_t mb_coredemo_secure_test(void) { return mb_core_secure_test(); }
