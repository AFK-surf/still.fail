// src/host/avc.h's tests, those of still.fail's Android AvcTest.kt (the conversion its hosts share):
//   cc -I src/host scripts/avc_test.c -o out/avc_test && out/avc_test
#include <stdio.h>
#include <stdlib.h>
#include "avc.h"

static int failed;

#define CHECK(c)                                                  \
  do {                                                            \
    if (!(c)) {                                                   \
      fprintf(stderr, "%s:%d: failed: %s\n", __FILE__, __LINE__, #c); \
      failed = 1;                                                 \
    }                                                             \
  } while (0)

static int same(const uint8_t *a, size_t an, const uint8_t *b, size_t bn) { return an == bn && memcmp(a, b, an) == 0; }

// An avcC as encoders write it: version 1, profile 66 (baseline), level 31, 4-byte lengths (0xff: 6 reserved bits set,
// lengthSizeMinusOne 3), one SPS (0xe1: 3 reserved bits, 1 set), one PPS.
static const uint8_t sps[] = {0x67, 0x42, 0xc0, 0x1f, 0xda, 0x01};
static const uint8_t pps[] = {0x68, 0xce, 0x3c, 0x80};
static uint8_t avcc[64];
static size_t avcc_n;

static void make_avcc(void) {
  const uint8_t head[] = {1, 0x42, 0xc0, 0x1f, 0xff, 0xe1, 0, sizeof sps};
  memcpy(avcc, head, sizeof head);
  avcc_n = sizeof head;
  memcpy(avcc + avcc_n, sps, sizeof sps);
  avcc_n += sizeof sps;
  avcc[avcc_n++] = 1;
  avcc[avcc_n++] = 0;
  avcc[avcc_n++] = sizeof pps;
  memcpy(avcc + avcc_n, pps, sizeof pps);
  avcc_n += sizeof pps;
}

static void avcc_makes_the_csd_with_start_codes(void) {
  mb_avc_config c;
  CHECK(mb_avc_parse(avcc, avcc_n, &c));
  CHECK(c.length_size == 4);
  uint8_t out[64], want[64];
  size_t n = mb_avc_csd(&c, 0, out, sizeof out);
  memcpy(want, "\0\0\0\1", 4);
  memcpy(want + 4, sps, sizeof sps);
  CHECK(same(out, n, want, 4 + sizeof sps));
  n = mb_avc_csd(&c, 1, out, sizeof out);
  memcpy(want + 4, pps, sizeof pps);
  CHECK(same(out, n, want, 4 + sizeof pps));
  // no room: nothing written, what it takes said
  CHECK(mb_avc_csd(&c, 0, out, 3) == 4 + sizeof sps);
}

static void an_avcc_that_is_not_one_is_none(void) {
  mb_avc_config c;
  CHECK(!mb_avc_parse(avcc, 0, &c));
  uint8_t other[64];
  memcpy(other, avcc, avcc_n);
  other[0] = 0;
  CHECK(!mb_avc_parse(other, avcc_n, &c));
  // a set that runs past its end
  CHECK(!mb_avc_parse(avcc, avcc_n - 2, &c));
  // 3-byte lengths
  memcpy(other, avcc, avcc_n);
  other[4] = 0xfe;
  CHECK(!mb_avc_parse(other, avcc_n, &c));
}

static void an_access_unit_has_start_codes_in_place_of_its_lengths(void) {
  const uint8_t idr[] = {0x65, 0x88, 0x84, 0x00, 0x33};
  const uint8_t sei[] = {0x06, 0x05};
  uint8_t au[32], want[32], out[32];
  size_t n = 0, w = 0;
  const uint8_t l4s[] = {0, 0, 0, sizeof sei}, l4i[] = {0, 0, 0, sizeof idr};
  memcpy(au + n, l4s, 4); n += 4;
  memcpy(au + n, sei, sizeof sei); n += sizeof sei;
  memcpy(au + n, l4i, 4); n += 4;
  memcpy(au + n, idr, sizeof idr); n += sizeof idr;
  memcpy(want + w, "\0\0\0\1", 4); w += 4;
  memcpy(want + w, sei, sizeof sei); w += sizeof sei;
  memcpy(want + w, "\0\0\0\1", 4); w += 4;
  memcpy(want + w, idr, sizeof idr); w += sizeof idr;
  long got = mb_avc_annexb(au, n, 4, out, sizeof out);
  CHECK(got >= 0 && same(out, (size_t)got, want, w));
  // two-byte lengths take the start codes' extra room
  n = 0;
  au[n++] = 0; au[n++] = sizeof sei;
  memcpy(au + n, sei, sizeof sei); n += sizeof sei;
  au[n++] = 0; au[n++] = sizeof idr;
  memcpy(au + n, idr, sizeof idr); n += sizeof idr;
  got = mb_avc_annexb(au, n, 2, out, sizeof out);
  CHECK(got >= 0 && same(out, (size_t)got, want, w));
  CHECK(mb_avc_annexb_size(au, n, 2) == (long)w);
}

static void a_broken_access_unit_puts_nothing(void) {
  const uint8_t au[] = {0, 0, 0, 9, 0x65, 0x88};
  uint8_t out[64];
  memset(out, 0xaa, sizeof out);
  CHECK(mb_avc_annexb_size(au, sizeof au, 4) == -1);
  CHECK(mb_avc_annexb(au, sizeof au, 4, out, sizeof out) == -1);
  CHECK(out[0] == 0xaa);
  // one that does not fit the decoder's buffer either
  const uint8_t fits[] = {0, 0, 0, 2, 0x65, 0x88};
  CHECK(mb_avc_annexb(fits, sizeof fits, 4, out, 3) == -1);
  CHECK(out[0] == 0xaa);
  // nothing at all is no access unit
  CHECK(mb_avc_annexb_size(au, 0, 4) == -1);
}

int main(void) {
  make_avcc();
  avcc_makes_the_csd_with_start_codes();
  an_avcc_that_is_not_one_is_none();
  an_access_unit_has_start_codes_in_place_of_its_lengths();
  a_broken_access_unit_puts_nothing();
  if (failed) return 1;
  printf("avc_test: 4 tests passed\n");
  return 0;
}
