// H.264 as a remote screen sends it (still.fail's docs/remote-screens.md, its Android app's remote/Avc.kt): a config's
// avcC (ISO/IEC 14496-15 AVCDecoderConfigurationRecord), then access units in AVCC, each NAL after its length. What a
// decoder takes of them: Android's MediaCodec the parameter sets as csd-0 (SPS) and csd-1 (PPS) and each access unit in
// Annex B (a start code in place of each length); Apple's VideoToolbox the sets themselves and the access units as they
// are, once known sound. Shared by the hosts that decode it (android_host.c, apple_stream.m), tested by
// scripts/avc_test.c. Plain C, no allocation: what is read points into the bytes given.
#pragma once
#include <stddef.h>
#include <stdint.h>
#include <string.h>

// the most parameter sets of a kind kept (an avcC has 1 SPS and 1 PPS as encoders write it; 31 and 255 at most)
#define MB_AVC_SETS 8

typedef struct {
  int length_size;  // how long a NAL's length is in the access units: 1, 2 or 4
  int nsps, npps;
  const uint8_t *sps[MB_AVC_SETS], *pps[MB_AVC_SETS];
  size_t sps_len[MB_AVC_SETS], pps_len[MB_AVC_SETS];
} mb_avc_config;

// Reads an avcC: 1 when it is one, 0 when not (too short, another version, a length size of 3, a set that runs past its
// end or is empty, no SPS, more sets than kept).
static inline int mb_avc_parse(const uint8_t *b, size_t n, mb_avc_config *c) {
  memset(c, 0, sizeof *c);
  if (n < 7 || b[0] != 1) return 0;
  c->length_size = (b[4] & 3) + 1;
  if (c->length_size == 3) return 0;
  size_t at = 5;
  for (int kind = 0; kind < 2; kind++) {
    if (at >= n) return 0;
    int count = kind == 0 ? (b[at] & 0x1f) : b[at];
    at++;
    if (count > MB_AVC_SETS) return 0;
    for (int i = 0; i < count; i++) {
      if (at + 2 > n) return 0;
      size_t len = ((size_t)b[at] << 8) | b[at + 1];
      at += 2;
      if (len == 0 || at + len > n) return 0;
      if (kind == 0) {
        c->sps[i] = b + at;
        c->sps_len[i] = len;
      } else {
        c->pps[i] = b + at;
        c->pps_len[i] = len;
      }
      at += len;
    }
    if (kind == 0) {
      c->nsps = count;
      if (count == 0) return 0;
    } else {
      c->npps = count;
    }
  }
  return 1;
}

// The sets of a kind (0 the SPS, 1 the PPS), each after a start code, into out (room for cap bytes): how many bytes
// that is (none written when it does not fit: answers what it would take).
static inline size_t mb_avc_csd(const mb_avc_config *c, int kind, uint8_t *out, size_t cap) {
  int n = kind == 0 ? c->nsps : c->npps;
  size_t size = 0;
  for (int i = 0; i < n; i++) size += 4 + (kind == 0 ? c->sps_len[i] : c->pps_len[i]);
  if (size > cap) return size;
  size_t at = 0;
  for (int i = 0; i < n; i++) {
    const uint8_t *u = kind == 0 ? c->sps[i] : c->pps[i];
    size_t len = kind == 0 ? c->sps_len[i] : c->pps_len[i];
    out[at] = 0; out[at + 1] = 0; out[at + 2] = 0; out[at + 3] = 1;
    memcpy(out + at + 4, u, len);
    at += 4 + len;
  }
  return size;
}

// How long the access unit is in Annex B: -1 when it is not a sound AVCC one (a NAL that runs past its end, an empty
// one, a length cut short, none at all). Its NALs each a start code and the NAL: as long as itself when the lengths are
// 4 bytes.
static inline long mb_avc_annexb_size(const uint8_t *f, size_t n, int length_size) {
  if (length_size != 1 && length_size != 2 && length_size != 4) return -1;
  size_t at = 0;
  long size = 0;
  int units = 0;
  while (at < n) {
    if (at + (size_t)length_size > n) return -1;
    uint64_t len = 0;
    for (int i = 0; i < length_size; i++) len = (len << 8) | f[at + i];
    at += (size_t)length_size;
    if (len == 0 || len > n - at) return -1;
    at += (size_t)len;
    size += 4 + (long)len;
    units++;
  }
  return units > 0 ? size : -1;
}

// Puts the access unit into out (room for cap bytes) in Annex B: how many bytes it put, or -1 when the frame is not a
// sound AVCC one or does not fit (nothing put then).
static inline long mb_avc_annexb(const uint8_t *f, size_t n, int length_size, uint8_t *out, size_t cap) {
  long size = mb_avc_annexb_size(f, n, length_size);
  if (size < 0 || (size_t)size > cap) return -1;
  size_t at = 0, o = 0;
  while (at < n) {
    size_t len = 0;
    for (int i = 0; i < length_size; i++) len = (len << 8) | f[at + i];
    at += (size_t)length_size;
    out[o] = 0; out[o + 1] = 0; out[o + 2] = 0; out[o + 3] = 1;
    memcpy(out + o + 4, f + at, len);
    o += 4 + len;
    at += len;
  }
  return (long)o;
}
