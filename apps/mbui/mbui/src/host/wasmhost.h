// The native shell's side of a program run in classic Wasm (wasm_shell.c): what the calls tools/wasmhost writes
//  ask of it. The program's memory holds its values as the native program's heap does ([rc][length],
// then what it holds), so a borrowed one is given to the C host where it lies.
#ifndef MBUI_WASMHOST_H
#define MBUI_WASMHOST_H
#include <stdint.h>
#include <stddef.h>
#include <wasmtime.h>
#include "moonbit.h"

// An import the shell defines: its name ("mbhost" its module), its callback, its parameters' and results' kinds.
typedef struct {
  const char *name;
  wasmtime_func_callback_t fn;
  int np;
  wasm_valkind_t p[16];
  int nr;
  wasm_valkind_t r[1];
} mbw_import;
extern const mbw_import mbw_imports[];

// The program's memory as it is now (it may move as it grows: never kept across a call into the program).
uint8_t *mbw_memory(wasmtime_caller_t *caller);
// A function of the program the C host is given, kept to be called later; whether there was one.
int mbw_keep(wasmtime_func_t *slot, const wasmtime_val_t *v);
// A kept function of the program called (a trampoline's): a trap said and the program ended.
void mbw_call(const wasmtime_func_t *f, wasmtime_val_t *args, size_t n, wasmtime_val_t *res, size_t nr);
// A string or bytes of the native heap made the program's (its export mbw_string, mbw_bytes) and let go of: where
// it lies there.
int32_t mbw_give_string(moonbit_string_t s);
int32_t mbw_give_bytes(moonbit_bytes_t b);
// The program's string or bytes at `at` copied into the native heap, for a C call that takes it (owned).
moonbit_string_t mbw_copy_string(uint8_t *m, int32_t at);
moonbit_bytes_t mbw_copy_bytes(uint8_t *m, int32_t at);
// A string or bytes the C host answered, kept for the program to take (mbui/wasmrt's take_*): its length.
int32_t mbw_keep_string(moonbit_string_t s);
int32_t mbw_keep_bytes(moonbit_bytes_t b);
#endif
