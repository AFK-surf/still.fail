// Breadcrumbs of work which has STARTED, including work that never returns. The window's thread publishes only
// integers and times; the log writer reads them without taking a lock or asking the window to answer. No text from
// the app, keys, URLs or screen contents. Kept only in the existing, bounded local log when Windows finds a hang.
// A changing slot is skipped, never waited for. Every concurrently accessed field uses an Interlocked operation.
#pragma once
#include <windows.h>
#include <stdint.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif
// 0..23 are hostapi/work_stage.mbt's portable stages. Native stages are separate: a native wait can be reported
// together with the UI phase that called it. detail is a numeric message/glyph/stream id, never a pointer or text.
enum {
  WH_IDLE = 100, WH_MESSAGE, WH_CALLBACK, WH_FRAME, WH_OUTSIDE, WH_PRESENT, WH_GPU_SUBMIT, WH_GPU_PRESENT,
  WH_GLYPH_WAIT, WH_GLYPH_DRAW, WH_STREAM_OPEN, WH_STREAM_CLOSE
};
typedef struct { int stage, detail; } wh_scope;
wh_scope mb_win_hang_enter(int stage, int detail);
void mb_win_hang_leave(wh_scope scope);
#ifdef __cplusplus
}
#endif

#ifdef MB_WIN_HANG_IMPLEMENTATION
#define WH_CAP 64
#define WH_EVENTS 8
typedef struct {
  volatile LONG published, stage, detail;
  volatile LONG64 at;
} wh_slot;
typedef struct { LONG seq; int stage, detail; ULONGLONG at; } wh_note;
static wh_slot wh_recent[WH_CAP], wh_events[WH_EVENTS], wh_native, wh_work;
static volatile LONG wh_sequence, wh_event_sequence, wh_owner;
static PVOID volatile wh_thread;

static LONG wh_load(volatile LONG *v) { return InterlockedCompareExchange(v, 0, 0); }
static void wh_write(wh_slot *slot, LONG seq, int stage, int detail, ULONGLONG at) {
  InterlockedExchange(&slot->published, 0);
  InterlockedExchange(&slot->stage, stage);
  InterlockedExchange(&slot->detail, detail);
  InterlockedExchange64(&slot->at, (LONG64)at);
  InterlockedExchange(&slot->published, seq);
}
static int wh_read(wh_slot *slot, wh_note *out) {
  LONG seq = wh_load(&slot->published);
  if (!seq) return 0;
  out->seq = seq;
  out->stage = (int)wh_load(&slot->stage);
  out->detail = (int)wh_load(&slot->detail);
  out->at = (ULONGLONG)InterlockedCompareExchange64(&slot->at, 0, 0);
  return wh_load(&slot->published) == seq;
}
static void wh_mark_at(int stage, int detail, ULONGLONG at) {
  LONG seq = InterlockedIncrement(&wh_sequence);
  if (!seq) seq = InterlockedIncrement(&wh_sequence);
  wh_write(&wh_recent[(uint32_t)seq % WH_CAP], seq, stage, detail, at);
  wh_write(stage >= WH_IDLE ? &wh_native : &wh_work, seq, stage, detail, at);
  // Navigation/screen lifecycle breadcrumbs have their own ring, so ordinary frames cannot overwrite them.
  if (stage >= 20 && stage <= 23) {
    LONG ev = InterlockedIncrement(&wh_event_sequence);
    if (!ev) ev = InterlockedIncrement(&wh_event_sequence);
    wh_write(&wh_events[(uint32_t)ev % WH_EVENTS], ev, stage, detail, at);
  }
}
static void wh_begin(void) {
  InterlockedExchange(&wh_owner, (LONG)GetCurrentThreadId());
  InterlockedExchangePointer(&wh_thread, OpenThread(THREAD_QUERY_LIMITED_INFORMATION, FALSE, GetCurrentThreadId()));
  wh_mark_at(WH_IDLE, 0, GetTickCount64());
  wh_mark_at(0, 0, GetTickCount64());
}
wh_scope mb_win_hang_enter(int stage, int detail) {
  wh_scope old = {0, 0};
  if ((DWORD)wh_load(&wh_owner) != GetCurrentThreadId()) return old;
  old.stage = (int)wh_load(&wh_native.stage);
  old.detail = (int)wh_load(&wh_native.detail);
  wh_mark_at(stage, detail, GetTickCount64());
  return old;
}
void mb_win_hang_leave(wh_scope old) {
  if (old.stage) wh_mark_at(old.stage, old.detail, GetTickCount64());
}
int32_t mb_host_work_stage(int32_t stage) {
  if ((DWORD)wh_load(&wh_owner) != GetCurrentThreadId()) return 0;
  int old = (int)wh_load(&wh_work.stage);
  wh_mark_at(stage, 0, GetTickCount64());
  return old;
}
static double wh_cpu_ms(void) {
  FILETIME made, ended, kernel, user;
  HANDLE thread = InterlockedCompareExchangePointer(&wh_thread, NULL, NULL);
  if (!thread || !GetThreadTimes(thread, &made, &ended, &kernel, &user)) return -1;
  return (double)((((uint64_t)kernel.dwHighDateTime << 32) | kernel.dwLowDateTime) +
                  (((uint64_t)user.dwHighDateTime << 32) | user.dwLowDateTime)) / 10000.0;
}
static const char *wh_name(int stage) {
  switch (stage) {
    case 0: return "idle";
    case 1: return "frame-start";
    case 2: return "tree";
    case 3: return "messages";
    case 4: return "build";
    case 5: return "layout";
    case 6: return "after-build";
    case 7: return "paint";
    case 8: return "present";
    case 9: return "after-frame";
    case 10: return "event";
    case 20: return "chat-switch";
    case 21: return "screen-open";
    case 22: return "screen-state";
    case 23: return "screen-close";
    case WH_IDLE: return "message-loop";
    case WH_MESSAGE: return "window-message";
    case WH_CALLBACK: return "callback";
    case WH_FRAME: return "frame";
    case WH_OUTSIDE: return "outside";
    case WH_PRESENT: return "render";
    case WH_GPU_SUBMIT: return "gpu-submit";
    case WH_GPU_PRESENT: return "gpu-present";
    case WH_GLYPH_WAIT: return "glyph-wait";
    case WH_GLYPH_DRAW: return "glyph-draw";
    case WH_STREAM_OPEN: return "stream-open";
    case WH_STREAM_CLOSE: return "stream-close";
    default: return "unknown";
  }
}
typedef void (*wh_say)(const char *, size_t);
static void wh_say_note(const char *kind, wh_note n, ULONGLONG at, wh_say say) {
  char line[240];
  int len = snprintf(line, sizeof line, "win: hang %s seq=%lu stage=%s(%d) detail=%d age_ms=%llu",
                     kind, (unsigned long)(uint32_t)n.seq, wh_name(n.stage), n.stage, n.detail,
                     (unsigned long long)(at >= n.at ? at - n.at : 0));
  say(line, (size_t)len);
}
static void wh_report(ULONGLONG at, wh_say say) {
  char line[160];
  int len = snprintf(line, sizeof line, "win: hang snapshot pid=%lu window_tid=%lu", GetCurrentProcessId(),
                     (DWORD)wh_load(&wh_owner));
  say(line, (size_t)len);
  wh_note note;
  if (wh_read(&wh_native, &note)) wh_say_note("native", note, at, say);
  if (wh_read(&wh_work, &note)) wh_say_note("work", note, at, say);
  uint32_t end = (uint32_t)wh_load(&wh_event_sequence);
  for (uint32_t i = 0; i < WH_EVENTS; i++) {
    uint32_t seq = end - (WH_EVENTS - 1) + i;
    if (wh_read(&wh_events[seq % WH_EVENTS], &note) && (uint32_t)note.seq == seq)
      wh_say_note("event", note, at, say);
  }
  end = (uint32_t)wh_load(&wh_sequence);
  for (uint32_t i = 0; i < WH_CAP; i++) {
    uint32_t seq = end - (WH_CAP - 1) + i;
    if (wh_read(&wh_recent[seq % WH_CAP], &note) && (uint32_t)note.seq == seq)
      wh_say_note("recent", note, at, say);
  }
}
#endif
