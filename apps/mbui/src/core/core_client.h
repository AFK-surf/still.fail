// What an app's engine gives mbui/core (core_native.c): the core (core_api.h) and what only the platform does. The
// engine is linked only into apps that run the core (src/coredemo on macOS), which hand it over as they load
// (mbc_use, from a constructor), so mbui/core builds, tests and links without the 57 MB shell.
#pragma once
#include "../host/core_api.h"

#ifdef __cplusplus
extern "C" {
#endif

/// The end of a browser session: the URL it was sent back to, or why not (one of the two is NULL).
typedef void (*mbc_auth_done)(const char *callback_url, const char *error, void *ctx);

typedef struct {
  void (*start)(const char *data_dir, const char *cloud_origin, int beta, mb_core_message_fn on_message, void *ctx);
  void (*send)(const char *json, size_t len, const uint8_t *bytes, size_t blen);
  void (*stop)(void);
  /// Where the core keeps its files when the app does not say (UTF-8, kept by the engine); NULL: none.
  const char *(*data_dir)(void);
  /// Opens `url` in the system's browser session and calls `done` (on any thread) with the URL it is sent to on
  /// `scheme`; NULL when the platform has none.
  void (*web_auth)(const char *url, const char *scheme, mbc_auth_done done, void *ctx);
  /// mbui's queue for the next frame (its host's: mb_post, mb_post_drop below), which the core's messages are posted
  /// to: given with the engine, as the app links both, so mbui/core's own tests link no host.
  void (*post)(const char *channel, const char *json, size_t len, const uint8_t *bytes, size_t blen);
  void (*post_drop)(const char *channel);
} mbc_engine;

// mbui's (its src/host/post_api.h, the host's own file): for an engine to hand over (`post`, `post_drop`)
void mb_post(const char *channel, const char *json, size_t len, const uint8_t *bytes, size_t blen);
void mb_post_drop(const char *channel);

void mbc_use(const mbc_engine *engine);

#ifdef __cplusplus
}
#endif
