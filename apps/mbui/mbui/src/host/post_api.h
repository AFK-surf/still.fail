// A message from outside the frames handed to the framework, from any thread (src/host/post.h; docs/determinism.md):
// what a core says, posted on its channel ("core") as its JSON (UTF-8, `len` bytes, not NUL-terminated) with the
// bytes beside it (NULL: none). Copied. The window's next frame takes it, in the order posted, and hands it to the
// app's handler for its channel (@ui.on_message); the first posted since a frame took the last asks for that frame.
#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void mb_post(const char *channel, const char *json, size_t len, const uint8_t *bytes, size_t blen);

/// What is posted on `channel` and not handed to the app yet, dropped (a core stopped: what it said last is not the
/// next one's). From the UI's thread.
void mb_post_drop(const char *channel);

#ifdef __cplusplus
}
#endif
