// A terminal's screen, kept by the host (src/hostapi/terminal.mbt says what is asked and what comes back). Included by
// each host's C after post.h (its post_string). Where a host is built with libghostty-vt (MB_GHOSTTY, its library
// linked), the screen is that library's; elsewhere none is kept (opening one answers 0) and the app shows no terminal.
#ifndef MB_TERM_H
#define MB_TERM_H

#ifndef MB_GHOSTTY

int32_t mb_host_term_open(int32_t cols, int32_t rows) { (void)cols; (void)rows; return 0; }
void mb_host_term_write(int32_t id, moonbit_bytes_t data) { (void)id; (void)data; }
void mb_host_term_resize(int32_t id, int32_t cols, int32_t rows) { (void)id; (void)cols; (void)rows; }
moonbit_string_t mb_host_term_lines(int32_t id) { (void)id; return post_string("", 0); }
void mb_host_term_close(int32_t id) { (void)id; }

#endif
#endif
