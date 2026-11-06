// Exercise the host's synchronous answer across the actual engine DLL, whose CRT is separate from the app's.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "engine.h"
#include "win_collate.h"

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "stillfail_engine.lib")

static HANDLE done;
static int passed;

static char *answer(void *ctx, const char *op, const char *json, size_t len) {
  (void)ctx;
  return strcmp(op, "text.collate") == 0 ? win_collate_shared_answer(json, len, L"en-US") : NULL;
}

static void say(void *ctx, const char *json, size_t len, const uint8_t *bytes, size_t blen) {
  (void)ctx; (void)bytes; (void)blen;
  passed = len == 2 && memcmp(json, "ok", 2) == 0;
  SetEvent(done);
}

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  const char *script = "globalThis.__stillfail={start:function(){for(let i=0;i<1000;i++){"
    "if(__native.callSync('text.collate','{\"names\":[\"b\",\"a\"]}')!=='{\"value\":[1,0]}')"
    "throw Error('wrong order');}__native.emit(0,'ok');},connect:function(){return 1;}};";
  done = CreateEventW(NULL, TRUE, FALSE, NULL);
  if (!done) return 2;
  sf_engine_host host = {NULL, say, NULL, NULL, NULL, answer, NULL};
  sf_engine *engine = sf_engine_start((const uint8_t *)script, strlen(script), "engine-sync.js", argv[1], "http://localhost", 0, "windows", &host);
  if (!engine) { CloseHandle(done); return 2; }
  DWORD result = WaitForSingleObject(done, 30000);
  sf_engine_stop(engine);
  CloseHandle(done);
  if (result != WAIT_OBJECT_0 || !passed) { fprintf(stderr, "engine sync: no correct answer\n"); return 1; }
  puts("engine sync: 1000 answers crossed the DLL boundary");
  return 0;
}
