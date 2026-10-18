// A small HTTP listener on a loopback address (on macOS and iOS: apple_listen.m): a login's browser coming back to
// http://127.0.0.1:<port>/… (core/README.md, Login). Two users: the core's `listen.*` (apple_core.m: taking a
// station's login callback on this device, `canRelay`) and an app's own sign-in (mbui/core `listen`, core_native.c).
//
// Each request is read whole (head up to 64 KB, body up to 1 MB, 15 s at most) and handed on once; it is answered once
// with mb_listen_respond, which closes its connection. Nothing else is answered: a request nobody answers waits until
// the listener closes.
#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// A request that came: `json` is {"request": n, "method", "path" (with its query), "headers": [[name, value], …]}
/// (UTF-8, `len` bytes) and `body` its body; or, once, json NULL: the listener has closed and nothing more comes.
/// Called on the listener's own queue; the pointers are valid only during the call.
typedef void (*mb_listen_fn)(void *ctx, const char *json, size_t len, const uint8_t *body, size_t blen);

/// Listens on `host` (127.0.0.1 or ::1) at `port` (0: one the system picks). Returns the listener's id (> 0) and the
/// port in `*bound`; 0 when it cannot, with why in `why` (the port taken: "Address already in use"). Any thread.
int mb_listen_open(const char *host, int port, mb_listen_fn fn, void *ctx, int *bound, char *why, size_t why_len);

/// Answers request `request` of listener `id`: `status`, `headers` (`n` names and values, alternating), `body`. The
/// connection closes after it. Nothing happens when the request was answered already or the listener is closed.
void mb_listen_respond(int id, long request, int status, const char *const *headers, int n, const uint8_t *body, size_t blen);

/// Stops listening: what is unanswered is closed unanswered, and `fn` is told (json NULL). Any thread.
void mb_listen_close(int id);

#ifdef __cplusplus
}
#endif
