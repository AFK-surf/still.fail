// Streams on Linux (src/hostapi/stream.mbt, @ui's Stream): none yet (stream_open answers 0).
#include <stdint.h>
#include "linux.h"

int32_t mb_host_stream_open(void) { return 0; }
void mb_host_stream_h264(int32_t id, moonbit_bytes_t avcc, int32_t w, int32_t h) {
  (void)id, (void)avcc, (void)w, (void)h;
}
void mb_host_stream_frame(int32_t id, moonbit_bytes_t data, int32_t key, double ts) {
  (void)id, (void)data, (void)key, (void)ts;
}
void mb_host_stream_jpeg(int32_t id, moonbit_bytes_t data, double ts) { (void)id, (void)data, (void)ts; }
moonbit_string_t mb_host_stream_next(int32_t id) {
  (void)id;
  return moonbit_make_string_raw(0);
}
void mb_host_stream_show(int32_t id, double ts) { (void)id, (void)ts; }
void mb_host_stream_close(int32_t id) { (void)id; }
int32_t mb_host_h264_here(void) { return 0; }
int32_t mb_host_stream_feeds(void) { return 0; }
void mb_host_stream_codec(int32_t id, moonbit_string_t cmd, moonbit_bytes_t data) { (void)id, (void)cmd, (void)data; }

unsigned mb_stream_tex(int id) {
  (void)id;
  return 0;
}
void mb_streams_upload(void) {}
void mb_streams_lost(void) {}
