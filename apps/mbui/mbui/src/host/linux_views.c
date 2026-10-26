// Native views over the canvas (host_native.mbt's view_*) on Linux: none yet (WebKitGTK's web views are a later
// step): view_open answers 0 and the app says it cannot show it.
#include <stdint.h>
#include "linux.h"

int32_t mb_host_view_open(int32_t kind, moonbit_string_t arg) {
  (void)kind, (void)arg;
  return 0;
}
void mb_host_view_place(int32_t id, double x, double y, double w, double h, double cx0, double cy0, double cx1,
                        double cy1, double radius, int32_t shown) {
  (void)id, (void)x, (void)y, (void)w, (void)h, (void)cx0, (void)cy0, (void)cx1, (void)cy1, (void)radius, (void)shown;
}
void mb_host_view_close(int32_t id) { (void)id; }
void mb_host_view_control(int32_t id, int32_t op, double value) { (void)id, (void)op, (void)value; }
int32_t mb_host_view_info(int32_t id, double *out) {
  (void)id, (void)out;
  return -1;
}
int32_t mb_host_view_read_next(int32_t id, double *out) {
  (void)id, (void)out;
  return -1;
}
void mb_host_view_read_answer(int32_t id, int32_t req, moonbit_bytes_t data, double total, int32_t more) {
  (void)id, (void)req, (void)data, (void)total, (void)more;
}
moonbit_string_t mb_host_view_site_next(int32_t id) {
  (void)id;
  return moonbit_make_string_raw(0);
}
moonbit_bytes_t mb_host_view_site_body(int32_t id, int32_t req) {
  (void)id, (void)req;
  return moonbit_make_bytes(0, 0);
}
void mb_host_view_site_head(int32_t id, int32_t req, int32_t status, moonbit_string_t headers) {
  (void)id, (void)req, (void)status, (void)headers;
}
void mb_host_view_site_chunk(int32_t id, int32_t req, moonbit_bytes_t data) { (void)id, (void)req, (void)data; }
void mb_host_view_site_end(int32_t id, int32_t req, moonbit_string_t error) { (void)id, (void)req, (void)error; }
moonbit_string_t mb_host_view_site_state(int32_t id) {
  (void)id;
  return moonbit_make_string_raw(0);
}
void mb_host_view_site_load(int32_t id, moonbit_string_t path) { (void)id, (void)path; }
void mb_host_view_tell(int32_t id, int32_t what, moonbit_string_t text) { (void)id, (void)what, (void)text; }
moonbit_string_t mb_host_view_text(int32_t id, int32_t what) {
  (void)id, (void)what;
  return moonbit_make_string_raw(0);
}
int32_t mb_host_view_text_known(int32_t id, int32_t what) {
  (void)id, (void)what;
  return 0;
}
moonbit_bytes_t mb_host_view_still(int32_t id) {
  (void)id;
  return moonbit_make_bytes(0, 0);
}
