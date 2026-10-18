// The still.fail client core (client/core-ts of ember) in JavaScriptCore on its Rust shell (client/shell), for the
// macOS and iOS hosts: apple_core.m. See core/README.md.
//
// One core, one UI client. What the UI says goes in with mb_core_send as the protocol's JSON (protocol.ts:
// {id, call, params}, {id, subscribe: {topic, ...}}, {id, unsubscribe: true}, ...), with bytes beside it when a call
// carries some; what the core says comes back through on_message ({id, ok|error}, {id, value}, {id, delta}, and
// {fatal} once the core has failed: start another then).
#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// A message from the core: its JSON (UTF-8, not NUL-terminated) and, for a message with bytes beside it (a screen
/// view's frame, a file read), the bytes; `bytes` is NULL when it has none. Both are valid only during the call.
/// Called on the core's own thread: the host copies what it keeps and hops to its UI thread itself (and must not
/// block there on its UI thread, which may be waiting in mb_core_stop).
typedef void (*mb_core_message_fn)(const char *json, size_t len, const uint8_t *bytes, size_t blen, void *ctx);

/// Starts the core: its files (accounts, sign-ins, databases) in `data_dir`, still.fail cloud at `cloud_origin`
/// (https://app.still.fail), `beta` the test channel. The script is $MB_CORE_BUNDLE, else core.js in the app's
/// bundle. Returns once the core's thread is up (the script still loading): mb_core_send can follow at once.
/// A failure to start (no script, the files' directory) comes as {"fatal": ...}.
void mb_core_start(const char *data_dir, const char *cloud_origin, int beta, mb_core_message_fn on_message, void *ctx);

/// Something the UI says (`json`: UTF-8, `len` bytes; `bytes`/`blen` beside it, or NULL). Copied; any thread.
void mb_core_send(const char *json, size_t len, const uint8_t *bytes, size_t blen);

/// Ends the core and waits for its thread; no message comes after it returns. Not from the core's thread.
void mb_core_stop(void);

#ifdef __cplusplus
}
#endif
