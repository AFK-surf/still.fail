// cl -nologo -W3 -Isrc/host scripts/win_hang_test.c -Feout/win_hang_test.exe
// No real hang or timing assertion: explicit publications and timestamps, including a writer stopped mid-slot.
#define MB_WIN_HANG_IMPLEMENTATION
#include "win_hang.h"
#include <assert.h>
#include <string.h>
static char output[24000];
static size_t used;
static void say(const char *s, size_t n) {
  assert(used + n + 2 < sizeof output);
  memcpy(output + used, s, n);
  used += n;
  output[used++] = '\n';
  output[used] = 0;
}
static DWORD WINAPI other_thread(void *unused) {
  (void)unused;
  assert(mb_host_work_stage(23) == 0);
  wh_scope scope = mb_win_hang_enter(WH_STREAM_CLOSE, 99);
  mb_win_hang_leave(scope);
  return 0;
}
int main(void) {
  wh_begin();
  wh_mark_at(20, 0, 100);
  wh_mark_at(21, 0, 110);
  wh_mark_at(22, 0, 120);
  for (int i = 0; i < WH_CAP * 3; i++) wh_mark_at(4, i, 200 + i);
  wh_mark_at(5, 0, 500);
  wh_scope scope = mb_win_hang_enter(WH_GLYPH_WAIT, 42);
  wh_note note;
  assert(wh_read(&wh_native, &note) && note.stage == WH_GLYPH_WAIT && note.detail == 42);
  mb_win_hang_leave(scope);
  assert(wh_read(&wh_native, &note) && note.stage == WH_IDLE);
  wh_mark_at(WH_GLYPH_WAIT, 42, 501);
  wh_report(1501, say);
  assert(strstr(output, "stage=layout(5) detail=0 age_ms=1001"));
  assert(strstr(output, "stage=glyph-wait(108) detail=42 age_ms=1000"));
  assert(strstr(output, "stage=chat-switch(20) detail=0 age_ms=1401"));
  assert(strstr(output, "stage=screen-state(22)"));
  // The UI is stalled halfway through a write: the watcher must not spin on it or print torn fields.
  InterlockedExchange(&wh_work.published, 0);
  used = 0; output[0] = 0;
  wh_report(2000, say);
  assert(!strstr(output, "hang work"));
  assert(strstr(output, "hang native"));
  wh_mark_at(5, 0, 500);
  LONG before = wh_load(&wh_sequence);
  HANDLE worker = CreateThread(NULL, 0, other_thread, NULL, 0, NULL);
  assert(worker);
  assert(WaitForSingleObject(worker, INFINITE) == WAIT_OBJECT_0);
  CloseHandle(worker);
  assert(wh_load(&wh_sequence) == before); // a decoder worker must not overwrite the window's phase
  assert(wh_cpu_ms() >= 0);
  CloseHandle(InterlockedExchangePointer(&wh_thread, NULL));
  puts("win_hang: ok (live phase, nested restore, bounded history, retained events, interrupted writer, owner thread)");
  return 0;
}
