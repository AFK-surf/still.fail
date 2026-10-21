// The few host functions the tests call for real on Linux (CI's native tests: scripts/linux_host.py gives every other
// extern of the hosts an answer of nothing, as the tests run against the fake host). Not built on any other target.

#include <errno.h>
#include <iconv.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "moonbit.h"

// a charset's name as iconv takes it (ASCII, NUL-terminated); the caller frees it
static char *ascii_of(moonbit_string_t s) {
  int32_t n = Moonbit_array_length(s);
  char *out = malloc((size_t)n + 1);
  for (int32_t i = 0; i < n; i++) out[i] = (char)(s[i] < 128 ? s[i] : '?');
  out[n] = 0;
  return out;
}

// Text in a legacy encoding (charset.mbt): glibc's iconv to UTF-16 as MoonBit's strings hold it; a byte it cannot map
// becomes U+FFFD, as the other hosts do.
int32_t mb_host_charset_known(moonbit_string_t charset) {
  char *name = ascii_of(charset);
  iconv_t cd = iconv_open("UTF-16LE", name);
  free(name);
  if (cd == (iconv_t)-1) return 0;
  iconv_close(cd);
  return 1;
}

moonbit_string_t mb_host_charset_decode(moonbit_bytes_t data, moonbit_string_t charset) {
  char *name = ascii_of(charset);
  iconv_t cd = iconv_open("UTF-16LE", name);
  free(name);
  int32_t len = Moonbit_array_length(data);
  if (cd == (iconv_t)-1 || len == 0) {
    if (cd != (iconv_t)-1) iconv_close(cd);
    return moonbit_make_string(0, 0);
  }
  // at most one UTF-16 unit pair a byte
  size_t cap = (size_t)len * 4 + 4;
  uint16_t *buf = malloc(cap);
  char *in = (char *)data, *out = (char *)buf;
  size_t left = (size_t)len, room = cap;
  while (left > 0) {
    if (iconv(cd, &in, &left, &out, &room) != (size_t)-1) break;
    if (errno == EILSEQ || errno == EINVAL) {
      if (room < 2) break;
      *(uint16_t *)out = 0xFFFD;
      out += 2;
      room -= 2;
      in++;
      left--;
    } else {
      break;
    }
  }
  iconv_close(cd);
  int32_t units = (int32_t)((cap - room) / 2);
  moonbit_string_t s = moonbit_make_string(units, 0);
  memcpy(s, buf, (size_t)units * 2);
  free(buf);
  return s;
}
