// The native shell of a program run in classic Wasm (the user, 2026-11-03: no C compiled for an app in development):
// the C host linked as the native program links it, and the program, an app's .wasm, run by wasmtime over it. Its
// imports are the host's C calls (wasm_thunks.c, written by tools/wasmhost), what its calls of the host give and take
// (mbw_take_string, mbw_take_bytes: mbui/wasmrt), and what MoonBit's own runtime asks (a line written, an exit, the
// time, the process's arguments and environment). The program's main runs as the native program's does: the host's
// run (mb_host_run) does not come back while the app is up, the program called into from inside it.
//
//     SHELL PROGRAM.wasm [ARGS…]      (MBUI_WASM_APP: PROGRAM.wasm, where no argument says; PROGRAM.cwasm: compiled
//                                     ahead for this machine by wasmtime's command line, a device's)
#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE  // (pthread_getattr_np)
#endif
#include "wasmhost.h"
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#if defined(__ANDROID__) || defined(__linux__)
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <ucontext.h>
#include <unistd.h>
#define MBW_CRASH 1
#endif
#ifdef __APPLE__
#include <TargetConditionals.h>
#include <mach-o/dyld.h>
#endif
#ifdef __ANDROID__
#include <android/log.h>
// (Android's Java starts the program as it starts the native one: mbui_main, android_host.c's Native.start)
#define main mbui_main
#endif

// A word of the shell's: on stderr, on Android the system's log (an app's process has no stderr)
static void say(const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
#ifdef __ANDROID__
  __android_log_vprint(ANDROID_LOG_ERROR, "mbui", fmt, ap);
#else
  vfprintf(stderr, fmt, ap);
#endif
  va_end(ap);
}

static wasmtime_context_t *ctx;
static wasmtime_memory_t memory;
static wasmtime_func_t export_string, export_bytes;
static int has_string, has_bytes;
static moonbit_string_t kept_string;
static moonbit_bytes_t kept_bytes;
static int shell_argc;
// (the program's end: proc_exit)
static int exiting, exit_code;
static char **shell_argv;

// What MoonBit's native runtime calls on an error of its own (moonc writes it into a native program; the shell is not
// one of moonc's)
void moonbit_panic(void) {
  say("wasm shell: the native runtime panicked\n");
  abort();
}

// How deep the program's own stack may go (wasmtime's max_wasm_stack: MBUI_WASM_STACK, in bytes, else wasmtime's own)
static size_t wasm_stack_max;
// Where the program's compiled code lies (wasmtime_module_image_range): a fault's pc said as an offset in it
static uintptr_t code_start, code_end;

#ifdef MBW_CRASH
// The crash file, open from the start (a fatal signal's report written to it without opening anything): crash.txt in an
// Android app's files, else MBUI_CRASH_FILE where said
static int crash_fd = -1;

// The stack of the thread calling: [lo, hi), and how much of it is used as `here` lies (the stack grows down)
static void thread_stack(uintptr_t *lo, uintptr_t *hi) {
  *lo = *hi = 0;
  pthread_attr_t a;
  if (pthread_getattr_np(pthread_self(), &a) != 0) return;
  void *addr = NULL;
  size_t size = 0;
  if (pthread_attr_getstack(&a, &addr, &size) == 0) {
    *lo = (uintptr_t)addr;
    *hi = *lo + size;
  }
  pthread_attr_destroy(&a);
}
#endif

// A line of the crash report: the system's log (say), and the crash file
static void report(const char *fmt, ...) {
  char line[1024];
  va_list ap;
  va_start(ap, fmt);
  int n = vsnprintf(line, sizeof line, fmt, ap);
  va_end(ap);
  if (n < 0) return;
  if ((size_t)n >= sizeof line) n = sizeof line - 1;
  say("%s", line);
#ifdef MBW_CRASH
  if (crash_fd >= 0) {
    ssize_t w = write(crash_fd, line, (size_t)n);
    (void)w;
  }
#endif
}

// How deep the program and the thread are, and the host's last PERF lines (android_host.c's mb_host_recent): what a
// trap's report says beside its stack
#ifdef __ANDROID__
void mb_host_recent(void (*each)(const char *line));
static void recent_line(const char *line) { report("  %s\n", line); }
#endif
// (`sp`: where the thread's stack was when it went wrong, a fault's; 0: here)
static void report_depth(size_t frames, uintptr_t sp) {
#ifdef MBW_CRASH
  uintptr_t lo, hi, here = sp ? sp : (uintptr_t)&lo;
  thread_stack(&lo, &hi);
  report("wasm shell: max_wasm_stack %zu bytes; the program %zu frames deep; this thread's stack %zu bytes, %zu used\n",
         wasm_stack_max, frames, (size_t)(hi - lo), hi > here ? (size_t)(hi - here) : (size_t)0);
#else
  (void)sp;
  report("wasm shell: max_wasm_stack %zu bytes; the program %zu frames deep\n", wasm_stack_max, frames);
#endif
#ifdef __ANDROID__
  report("wasm shell: the last lines said:\n");
  mb_host_recent(recent_line);
#endif
}

// A trap's stack, by the program's functions (their names where the program kept them: its name section), innermost
// first: the first 48 and the last 16 where it is deeper
static size_t report_trace(wasm_trap_t *trap) {
  wasm_frame_vec_t frames = {0};
  wasm_trap_trace(trap, &frames);
  for (size_t k = 0; k < frames.size; k++) {
    if (k == 48 && frames.size > 64) {
      report("  … %zu more …\n", frames.size - 64);
      k = frames.size - 16;
    }
    const wasm_frame_t *f = frames.data[k];
    const wasm_name_t *name = wasmtime_frame_func_name(f);
    report("  #%zu %.*s (function %u, +0x%zx)\n", k, name ? (int)name->size : 1, name ? name->data : "?",
           wasm_frame_func_index(f), wasm_frame_module_offset(f));
  }
  size_t n = frames.size;
  wasm_frame_vec_delete(&frames);
  return n;
}

static void die(const char *what, wasmtime_error_t *err, wasm_trap_t *trap) {
  wasm_byte_vec_t msg = {0};
  if (err) wasmtime_error_message(err, &msg);
  else if (trap) wasm_trap_message(trap, &msg);
  // (said a line at a time: wasmtime's message holds the whole of the program's stack, each frame a line)
  report("wasm shell: %s%s", what, msg.size ? ": " : "\n");
  for (size_t at = 0; at < msg.size;) {
    size_t end = at;
    while (end < msg.size && msg.data[end] != '\n') end++;
    report("%.*s\n", (int)(end - at), msg.data + at);
    at = end + 1;
  }
  if (trap) {
    wasmtime_trap_code_t code;
    if (wasmtime_trap_code(trap, &code)) report("wasm shell: trap code %d\n", (int)code);
    report_depth(report_trace(trap), 0);
  }
  exit(1);
}

#ifdef MBW_CRASH
// A fatal signal no handler before it took (wasmtime's takes a trap of the program's and the call returns it: die):
// said, where it was and how deep, to the log and the crash file, then the process ends as the signal would end it
static struct sigaction fatal_before[32];

static void fatal(int sig, siginfo_t *info, void *uc) {
  // (wasmtime's first, as it was before this: a trap of the program's it takes, unwinding to the call, never back here)
  struct sigaction *b = &fatal_before[sig];
  if (b->sa_flags & SA_SIGINFO) {
    if (b->sa_sigaction) b->sa_sigaction(sig, info, uc);
  } else if (b->sa_handler != SIG_DFL && b->sa_handler != SIG_IGN && b->sa_handler) {
    b->sa_handler(sig);
  }
  uintptr_t pc = 0, sp = 0;
#if defined(__aarch64__)
  pc = (uintptr_t)((ucontext_t *)uc)->uc_mcontext.pc;
  sp = (uintptr_t)((ucontext_t *)uc)->uc_mcontext.sp;
#elif defined(__x86_64__)
  pc = (uintptr_t)((ucontext_t *)uc)->uc_mcontext.gregs[REG_RIP];
  sp = (uintptr_t)((ucontext_t *)uc)->uc_mcontext.gregs[REG_RSP];
#endif
  report("wasm shell: fatal signal %d (code %d) at pc %p, address %p\n", sig, info ? info->si_code : 0, (void *)pc,
         info ? info->si_addr : NULL);
  if (pc >= code_start && pc < code_end)
    report("wasm shell: in the program's code, +0x%zx of %zu bytes (a trap no handler took)\n",
           (size_t)(pc - code_start), (size_t)(code_end - code_start));
  report_depth(0, sp);
  signal(sig, SIG_DFL);
}

static void fatal_watch(void) {
  int sigs[] = {SIGILL, SIGSEGV, SIGBUS, SIGFPE, SIGTRAP};
  for (size_t k = 0; k < sizeof sigs / sizeof sigs[0]; k++) {
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = fatal;
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigemptyset(&sa.sa_mask);
    sigaction(sigs[k], &sa, &fatal_before[sigs[k]]);
  }
}
#endif

static int has_memory;

// (the program's start runs as it is made, its imports called before the shell has its exports: the memory taken from
// the first call's caller then)
uint8_t *mbw_memory(wasmtime_caller_t *caller) {
  if (!has_memory) {
    wasmtime_extern_t item;
    if (!caller || !wasmtime_caller_export_get(caller, "memory", 6, &item) || item.kind != WASMTIME_EXTERN_MEMORY) {
      say("wasm shell: the program exports no memory\n");
      exit(1);
    }
    memory = item.of.memory;
    has_memory = 1;
  }
  return wasmtime_memory_data(ctx, &memory);
}

int mbw_keep(wasmtime_func_t *slot, const wasmtime_val_t *v) {
  if (wasmtime_funcref_is_null(&v->of.funcref)) return 0;
  *slot = v->of.funcref;
  return 1;
}

#ifdef __ANDROID__
// A crash made on purpose, to see its report (a development build's check: `crash-test` in the app's files says which:
// "trap", a program's trap; "stack", its stack overflowing; "segv", a fault of the shell's own), made once, on the
// thread that calls the program, as its first call comes: a module of its own, named functions in it
static char crash_test[16];
static wasm_engine_t *crash_engine;

static void crash_test_now(void) {
  char what[16];
  memcpy(what, crash_test, sizeof what);
  crash_test[0] = 0;
  if (strcmp(what, "segv") == 0) {
    report("wasm shell: a fault made on purpose (crash-test)\n");
    volatile int *nowhere = (volatile int *)(uintptr_t)16;
    *nowhere = 1;
    return;
  }
  const char *wat = "(module (func $deeper (param i32) (result i32) local.get 0 i32.const 1 i32.add call $deeper)"
                    " (func $made_to_trap unreachable) (func $calls_it call $made_to_trap)"
                    " (export \"trap\" (func $calls_it)) (export \"stack\" (func $deeper)))";
  wasm_byte_vec_t bin;
  wasmtime_error_t *err = wasmtime_wat2wasm(wat, strlen(wat), &bin);
  if (err) die("crash-test: no module", err, NULL);
  wasmtime_module_t *m = NULL;
  err = wasmtime_module_new(crash_engine, (const uint8_t *)bin.data, bin.size, &m);
  wasm_byte_vec_delete(&bin);
  if (err) die("crash-test: no module", err, NULL);
  wasmtime_instance_t inst;
  wasm_trap_t *trap = NULL;
  err = wasmtime_instance_new(ctx, m, NULL, 0, &inst, &trap);
  if (err || trap) die("crash-test: no instance", err, trap);
  wasmtime_extern_t item;
  int stack = strcmp(what, "stack") == 0;
  if (!wasmtime_instance_export_get(ctx, &inst, stack ? "stack" : "trap", stack ? 5 : 4, &item)) return;
  report("wasm shell: a %s made on purpose (crash-test)\n", stack ? "stack overflow" : "trap");
  wasmtime_val_t arg = {.kind = WASMTIME_I32, .of.i32 = 0}, res;
  err = wasmtime_func_call(ctx, &item.of.func, &arg, stack ? 1 : 0, &res, stack ? 1 : 0, &trap);
  if (err || trap) die("the program trapped", err, trap);
}
#endif

void mbw_call(const wasmtime_func_t *f, wasmtime_val_t *args, size_t n, wasmtime_val_t *res, size_t nr) {
#ifdef __ANDROID__
  if (crash_test[0]) crash_test_now();
#endif
  wasm_trap_t *trap = NULL;
  wasmtime_error_t *err = wasmtime_func_call(ctx, f, args, n, res, nr, &trap);
  if (exiting) exit(exit_code);
  if (err || trap) die("the program trapped", err, trap);
}

// A fresh object of the program's, `n` long (its export's), where it lies.
static int32_t made(wasmtime_func_t *f, int32_t n) {
  wasmtime_val_t arg = {.kind = WASMTIME_I32, .of.i32 = n}, res;
  mbw_call(f, &arg, 1, &res, 1);
  return res.of.i32;
}

int32_t mbw_give_string(moonbit_string_t s) {
  if (!has_string) die("the program exports no mbw_string", NULL, NULL);
  int32_t n = Moonbit_array_length(s);
  int32_t at = made(&export_string, n);
  memcpy(wasmtime_memory_data(ctx, &memory) + at, s, (size_t)n * 2);
  moonbit_decref(s);
  return at;
}

int32_t mbw_give_bytes(moonbit_bytes_t b) {
  if (!has_bytes) die("the program exports no mbw_bytes", NULL, NULL);
  int32_t n = Moonbit_array_length(b);
  int32_t at = made(&export_bytes, n);
  memcpy(wasmtime_memory_data(ctx, &memory) + at, b, (size_t)n);
  moonbit_decref(b);
  return at;
}

static int32_t length_at(uint8_t *m, int32_t at) { return *(int32_t *)(m + at - 4); }

moonbit_string_t mbw_copy_string(uint8_t *m, int32_t at) {
  int32_t n = length_at(m, at);
  moonbit_string_t s = moonbit_make_string(n, 0);
  memcpy(s, m + at, (size_t)n * 2);
  return s;
}

moonbit_bytes_t mbw_copy_bytes(uint8_t *m, int32_t at) {
  int32_t n = length_at(m, at);
  moonbit_bytes_t b = moonbit_make_bytes(n, 0);
  memcpy(b, m + at, (size_t)n);
  return b;
}

int32_t mbw_keep_string(moonbit_string_t s) {
  if (kept_string) moonbit_decref(kept_string);
  kept_string = s;
  return s ? Moonbit_array_length(s) : 0;
}

int32_t mbw_keep_bytes(moonbit_bytes_t b) {
  if (kept_bytes) moonbit_decref(kept_bytes);
  kept_bytes = b;
  return b ? Moonbit_array_length(b) : 0;
}

// mbui/wasmrt's take_string, take_bytes: what was kept copied where the program made room for it
static wasm_trap_t *take_string(void *env, wasmtime_caller_t *caller, const wasmtime_val_t *a, size_t na,
                                wasmtime_val_t *r, size_t nr) {
  (void)env; (void)na; (void)r; (void)nr;
  if (kept_string) {
    memcpy(mbw_memory(caller) + a[0].of.i32, kept_string, (size_t)Moonbit_array_length(kept_string) * 2);
    moonbit_decref(kept_string);
    kept_string = NULL;
  }
  return NULL;
}

static wasm_trap_t *take_bytes(void *env, wasmtime_caller_t *caller, const wasmtime_val_t *a, size_t na,
                               wasmtime_val_t *r, size_t nr) {
  (void)env; (void)na; (void)r; (void)nr;
  if (kept_bytes) {
    memcpy(mbw_memory(caller) + a[0].of.i32, kept_bytes, (size_t)Moonbit_array_length(kept_bytes));
    moonbit_decref(kept_bytes);
    kept_bytes = NULL;
  }
  return NULL;
}

// MoonBit's own: println's line (WASI's fd_write), abort's and exit's end (WASI's proc_exit)
static wasm_trap_t *fd_write(void *env, wasmtime_caller_t *caller, const wasmtime_val_t *a, size_t na,
                             wasmtime_val_t *r, size_t nr) {
  (void)env; (void)na; (void)nr;
  uint8_t *m = mbw_memory(caller);
  int32_t fd = a[0].of.i32, iovs = a[1].of.i32, count = a[2].of.i32, written = a[3].of.i32, total = 0;
  for (int32_t i = 0; i < count; i++) {
    uint32_t ptr = *(uint32_t *)(m + iovs + i * 8), len = *(uint32_t *)(m + iovs + i * 8 + 4);
#ifdef __ANDROID__
    __android_log_print(fd == 2 ? ANDROID_LOG_ERROR : ANDROID_LOG_INFO, "mbui", "%.*s", (int)len, (const char *)(m + ptr));
#else
    fwrite(m + ptr, 1, len, fd == 2 ? stderr : stdout);
#endif
    total += (int32_t)len;
  }
  fflush(fd == 2 ? stderr : stdout);
  *(int32_t *)(m + written) = total;
  r[0].kind = WASMTIME_I32;
  r[0].of.i32 = 0;
  return NULL;
}

// (the program's end unwinds it, a trap of the shell's own, and is then the process's: its main's end, which MoonBit's
// _start ends with as it ends, is no end of the app where the host's run came back with it up, Android's)
static wasm_trap_t *proc_exit(void *env, wasmtime_caller_t *caller, const wasmtime_val_t *a, size_t na,
                              wasmtime_val_t *r, size_t nr) {
  (void)env; (void)caller; (void)na; (void)r; (void)nr;
  exiting = 1;
  exit_code = a[0].of.i32;
  if (getenv("MBUI_WASM_TRACE")) say("wasm shell: the program ended (%d)\n", exit_code);
  return wasmtime_trap_new("the program ended", 17);
}

// mbui/film's process needs on Wasm (src/film/film_wasm.mbt), for a scene's program run here (its preview): its
// arguments (the environment's), a line said, its end. What it asks is read through its exports film_text_length,
// film_text_unit; what is answered taken back a unit at a time.
static wasmtime_func_t export_text_length, export_text_unit;
static int has_film_text;
static uint16_t *film_got;
static size_t film_got_n;

static char *film_text(void) {
  if (!has_film_text) {
    say("wasm shell: the program exports no film_text_length, film_text_unit\n");
    exit(1);
  }
  wasmtime_val_t res, arg = {.kind = WASMTIME_I32};
  mbw_call(&export_text_length, NULL, 0, &res, 1);
  int32_t n = res.of.i32;
  char *out = malloc((size_t)n * 3 + 1);
  size_t k = 0;
  for (int32_t i = 0; i < n; i++) {
    arg.of.i32 = i;
    mbw_call(&export_text_unit, &arg, 1, &res, 1);
    uint32_t c = (uint32_t)res.of.i32;
    // (UTF-16 to UTF-8, a surrogate's half as it is: the names asked are ASCII)
    if (c < 0x80) out[k++] = (char)c;
    else if (c < 0x800) { out[k++] = (char)(0xc0 | c >> 6); out[k++] = (char)(0x80 | (c & 63)); }
    else { out[k++] = (char)(0xe0 | c >> 12); out[k++] = (char)(0x80 | (c >> 6 & 63)); out[k++] = (char)(0x80 | (c & 63)); }
  }
  out[k] = 0;
  return out;
}

static wasm_trap_t *film_arg(void *env, wasmtime_caller_t *caller, const wasmtime_val_t *a, size_t na,
                             wasmtime_val_t *r, size_t nr) {
  (void)env; (void)caller; (void)a; (void)na; (void)r; (void)nr;
  char *name = film_text();
  const char *v = getenv(name);
  free(name);
  free(film_got);
  film_got_n = 0;
  size_t n = v ? strlen(v) : 0;
  film_got = malloc((n + 1) * 2);
  // (UTF-8 to UTF-16, the environment's values being words of either)
  for (size_t i = 0; i < n;) {
    unsigned char c = (unsigned char)v[i];
    uint32_t u;
    if (c < 0x80) { u = c; i += 1; }
    else if (c < 0xe0 && i + 1 < n) { u = (uint32_t)(c & 31) << 6 | (v[i + 1] & 63); i += 2; }
    else if (c < 0xf0 && i + 2 < n) { u = (uint32_t)(c & 15) << 12 | (uint32_t)(v[i + 1] & 63) << 6 | (v[i + 2] & 63); i += 3; }
    else { u = 0xfffd; i += 1; }
    film_got[film_got_n++] = (uint16_t)u;
  }
  return NULL;
}

static wasm_trap_t *film_got_length(void *env, wasmtime_caller_t *caller, const wasmtime_val_t *a, size_t na,
                                    wasmtime_val_t *r, size_t nr) {
  (void)env; (void)caller; (void)a; (void)na; (void)nr;
  r[0].kind = WASMTIME_I32;
  r[0].of.i32 = (int32_t)film_got_n;
  return NULL;
}

static wasm_trap_t *film_got_unit(void *env, wasmtime_caller_t *caller, const wasmtime_val_t *a, size_t na,
                                  wasmtime_val_t *r, size_t nr) {
  (void)env; (void)caller; (void)na; (void)nr;
  r[0].kind = WASMTIME_I32;
  r[0].of.i32 = (size_t)a[0].of.i32 < film_got_n ? film_got[a[0].of.i32] : 0;
  return NULL;
}

static wasm_trap_t *film_say(void *env, wasmtime_caller_t *caller, const wasmtime_val_t *a, size_t na,
                             wasmtime_val_t *r, size_t nr) {
  (void)env; (void)caller; (void)a; (void)na; (void)r; (void)nr;
  char *s = film_text();
  say("%s\n", s);
  free(s);
  return NULL;
}

// An import the shell has not: the program runs until it is called, then ends saying which.
static wasm_trap_t *missing(void *env, wasmtime_caller_t *caller, const wasmtime_val_t *a, size_t na,
                            wasmtime_val_t *r, size_t nr) {
  (void)caller; (void)a; (void)na; (void)r; (void)nr;
  say("wasm shell: the program called %s, which this shell has not\n", (const char *)env);
  exit(1);
}

// (strndup's, which MSVC's C library has not)
static char *copy_n(const char *s, size_t n) {
  char *out = malloc(n + 1);
  memcpy(out, s, n);
  out[n] = 0;
  return out;
}

static wasm_functype_t *functype(int np, const wasm_valkind_t *p, int nr, const wasm_valkind_t *r) {
  wasm_valtype_vec_t params, results;
  wasm_valtype_t *ps[16], *rs[1];
  for (int i = 0; i < np; i++) ps[i] = wasm_valtype_new(p[i]);
  for (int i = 0; i < nr; i++) rs[i] = wasm_valtype_new(r[i]);
  wasm_valtype_vec_new(&params, (size_t)np, ps);
  wasm_valtype_vec_new(&results, (size_t)nr, rs);
  return wasm_functype_new(&params, &results);
}

static void define(wasmtime_linker_t *linker, const char *mod, const char *name, wasmtime_func_callback_t fn,
                   void *env, wasm_functype_t *ty) {
  wasmtime_error_t *err =
      wasmtime_linker_define_func(linker, mod, strlen(mod), name, strlen(name), ty, fn, env, NULL);
  wasm_functype_delete(ty);
  if (err) die(name, err, NULL);
}

static wasm_byte_vec_t read_file(const char *path) {
  wasm_byte_vec_t out = {0};
  FILE *f = fopen(path, "rb");
  if (!f) {
    say("wasm shell: cannot read %s\n", path);
    exit(2);
  }
  fseek(f, 0, SEEK_END);
  long n = ftell(f);
  fseek(f, 0, SEEK_SET);
  wasm_byte_vec_new_uninitialized(&out, (size_t)n);
  if (fread(out.data, 1, (size_t)n, f) != (size_t)n) {
    say("wasm shell: cannot read %s\n", path);
    exit(2);
  }
  fclose(f);
  return out;
}

#ifdef __ANDROID__
// An Android app's files (the package's, as the process is named), `file` in them
static const char *android_file(const char *file) {
  static char path[512];
  char name[256] = {0};
  FILE *f = fopen("/proc/self/cmdline", "rb");
  if (!f) return NULL;
  size_t n = fread(name, 1, sizeof name - 1, f);
  fclose(f);
  name[n] = 0;
  // (a process of its own, "package:name", is the package's still)
  char *colon = strchr(name, ':');
  if (colon) *colon = 0;
  snprintf(path, sizeof path, "/data/data/%s/files/%s", name, file);
  return path;
}

// Where an Android app's program lies, unless MBUI_WASM_APP says: app.cwasm in its files (scripts/wasm-app.sh compiles it
// for the device and puts it there)
static const char *android_program(void) {
  // (its own copy: android_file's is said again for the crash file and the crash test)
  static char path[512];
  snprintf(path, sizeof path, "%s", android_file("app.cwasm"));
  return path;
}
#endif

#ifdef __APPLE__
// Where an iOS device's program lies, unless MBUI_WASM_APP says: app.cwasm beside the program, in its bundle
static const char *beside_program(void) {
  static char path[4096];
  uint32_t n = sizeof path;
  if (_NSGetExecutablePath(path, &n) != 0) return NULL;
  char *slash = strrchr(path, '/');
  if (!slash || (size_t)(slash - path) + 10 > sizeof path) return NULL;
  strcpy(slash + 1, "app.cwasm");
  return path;
}
#endif

int main(int argc, char **argv) {
  const char *path = argc > 1 ? argv[1] : getenv("MBUI_WASM_APP");
#ifdef __ANDROID__
  if (!path || !*path) path = android_program();
#elif defined(__APPLE__) && TARGET_OS_IPHONE
  if (!path || !*path) path = beside_program();
#endif
  if (!path || !*path) {
    say("usage: %s PROGRAM.wasm [ARGS…]\n", argv[0]);
    return 2;
  }
  shell_argc = argc;
  shell_argv = argv;
  wasm_config_t *config = wasm_config_new();
  // (an iOS device runs no code an app made: the program run by Pulley, wasmtime's interpreter; MBUI_WASM_PULLEY=1
  // the same on a simulator, whose wasmtime has it too, for what a device runs)
  int pulley = getenv("MBUI_WASM_PULLEY") && *getenv("MBUI_WASM_PULLEY") == '1';
#if defined(__APPLE__) && TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  pulley = 1;
#endif
  if (pulley) {
    wasmtime_error_t *target_err = wasmtime_config_target_set(config, "pulley64");
    if (target_err) die("no Pulley", target_err, NULL);
  }
  // (how deep the program's own stack may go: said in a trap's report, beside how deep it was and the thread's stack)
  const char *stack = getenv("MBUI_WASM_STACK");
  wasm_stack_max = stack && *stack ? (size_t)strtoull(stack, NULL, 10) : (size_t)512 * 1024;
  wasmtime_config_max_wasm_stack_set(config, wasm_stack_max);
#ifdef __ANDROID__
  // (on Android a trap by a signal is never taken by wasmtime's handler, ART's in the way (2026-11-05: an `unreachable`
  // and the stack's limit each ended the process with SIGILL): the program's traps checked in its code instead, each
  // returned to its call as any trap is (die, its stack said); the program compiled to match (scripts/wasm-app.sh)
  wasmtime_config_signals_based_traps_set(config, false);
#endif
#ifdef MBW_CRASH
  {
#ifdef __ANDROID__
    const char *crash = android_file("crash.txt");
#else
    const char *crash = getenv("MBUI_CRASH_FILE");
#endif
    if (crash && *crash) crash_fd = open(crash, O_WRONLY | O_CREAT | O_TRUNC, 0644);
  }
#endif
  wasm_engine_t *engine = wasm_engine_new_with_config(config);
#ifdef __ANDROID__
  {
    crash_engine = engine;
    FILE *t = fopen(android_file("crash-test"), "rb");
    if (t) {
      size_t got = fread(crash_test, 1, sizeof crash_test - 1, t);
      fclose(t);
      crash_test[got] = 0;
      for (size_t k = 0; k < got; k++)
        if (crash_test[k] == '\n' || crash_test[k] == '\r') crash_test[k] = 0;
      remove(android_file("crash-test"));
    }
  }
#endif
  wasmtime_store_t *store = wasmtime_store_new(engine, NULL, NULL);
  ctx = wasmtime_store_context(store);
  wasmtime_module_t *module = NULL;
  wasmtime_error_t *err;
  size_t len = strlen(path);
  if (len > 6 && strcmp(path + len - 6, ".cwasm") == 0) {
    // (compiled ahead for this machine by wasmtime's command line, as this wasmtime would: a device's)
    err = wasmtime_module_deserialize_file(engine, path, &module);
    if (err) die("the program is not one compiled for this shell", err, NULL);
  } else {
    wasm_byte_vec_t wasm = read_file(path);
    err = wasmtime_module_new(engine, (const uint8_t *)wasm.data, wasm.size, &module);
    wasm_byte_vec_delete(&wasm);
    if (err) die("the program is not a module", err, NULL);
  }
  wasmtime_linker_t *linker = wasmtime_linker_new(engine);
  for (const mbw_import *i = mbw_imports; i->name; i++)
    define(linker, "mbhost", i->name, i->fn, NULL, functype(i->np, i->p, i->nr, i->r));
  wasm_valkind_t i32[4] = {WASM_I32, WASM_I32, WASM_I32, WASM_I32};
  define(linker, "mbhost", "mbw_take_string", take_string, NULL, functype(1, i32, 0, NULL));
  define(linker, "mbhost", "mbw_take_bytes", take_bytes, NULL, functype(1, i32, 0, NULL));
  define(linker, "wasi_snapshot_preview1", "fd_write", fd_write, NULL, functype(4, i32, 1, i32));
  define(linker, "wasi_snapshot_preview1", "proc_exit", proc_exit, NULL, functype(1, i32, 0, NULL));
  define(linker, "film", "arg", film_arg, NULL, functype(0, NULL, 0, NULL));
  define(linker, "film", "gotLength", film_got_length, NULL, functype(0, NULL, 1, i32));
  define(linker, "film", "gotUnit", film_got_unit, NULL, functype(1, i32, 1, i32));
  define(linker, "film", "say", film_say, NULL, functype(0, NULL, 0, NULL));
  define(linker, "film", "exit", proc_exit, NULL, functype(1, i32, 0, NULL));
  // what else the program imports, a function that ends it saying which as it is called
  wasm_importtype_vec_t imports;
  wasmtime_module_imports(module, &imports);
  for (size_t k = 0; k < imports.size; k++) {
    const wasm_name_t *mod = wasm_importtype_module(imports.data[k]);
    const wasm_name_t *name = wasm_importtype_name(imports.data[k]);
    const wasm_externtype_t *ty = wasm_importtype_type(imports.data[k]);
    wasmtime_extern_t found;
    if (wasmtime_linker_get(linker, ctx, mod->data, mod->size, name->data, name->size, &found)) continue;
    const wasm_functype_t *fty = wasm_externtype_as_functype_const(ty);
    if (!fty) continue;
    char *label = malloc(mod->size + name->size + 2);
    snprintf(label, mod->size + name->size + 2, "%.*s.%.*s", (int)mod->size, mod->data, (int)name->size, name->data);
    char *n = copy_n(name->data, name->size), *m = copy_n(mod->data, mod->size);
    define(linker, m, n, missing, label, wasm_functype_copy(fty));
    free(n);
    free(m);
  }
  wasm_importtype_vec_delete(&imports);
  {
    void *start = NULL, *end = NULL;
    wasmtime_module_image_range(module, &start, &end);
    code_start = (uintptr_t)start;
    code_end = (uintptr_t)end;
  }
#ifdef MBW_CRASH
  // (after wasmtime's own: its first, then this one, for what it does not take)
  fatal_watch();
#endif
  wasmtime_instance_t instance;
  wasm_trap_t *trap = NULL;
  err = wasmtime_linker_instantiate(linker, ctx, module, &instance, &trap);
  if (err || trap) die("the program could not start", err, trap);
  wasmtime_extern_t item;
  if (!wasmtime_instance_export_get(ctx, &instance, "memory", 6, &item) || item.kind != WASMTIME_EXTERN_MEMORY)
    die("the program exports no memory", NULL, NULL);
  memory = item.of.memory;
  has_memory = 1;
  if (wasmtime_instance_export_get(ctx, &instance, "mbw_string", 10, &item) && item.kind == WASMTIME_EXTERN_FUNC) {
    export_string = item.of.func;
    has_string = 1;
  }
  if (wasmtime_instance_export_get(ctx, &instance, "mbw_bytes", 9, &item) && item.kind == WASMTIME_EXTERN_FUNC) {
    export_bytes = item.of.func;
    has_bytes = 1;
  }
  if (wasmtime_instance_export_get(ctx, &instance, "film_text_length", 16, &item) && item.kind == WASMTIME_EXTERN_FUNC) {
    export_text_length = item.of.func;
    if (wasmtime_instance_export_get(ctx, &instance, "film_text_unit", 14, &item) && item.kind == WASMTIME_EXTERN_FUNC) {
      export_text_unit = item.of.func;
      has_film_text = 1;
    }
  }
  if (!wasmtime_instance_export_get(ctx, &instance, "_start", 6, &item) || item.kind != WASMTIME_EXTERN_FUNC)
    die("the program has no main (_start)", NULL, NULL);
  if (getenv("MBUI_WASM_TRACE")) say("wasm shell: started %s\n", path);
  trap = NULL;
  err = wasmtime_func_call(ctx, &item.of.func, NULL, 0, NULL, 0, &trap);
  // (its main's end: the app goes on where the host's run came back, as the native program's main returns)
  if (getenv("MBUI_WASM_TRACE")) say("wasm shell: its main came back (%s %d)\n", exiting ? "ended" : "returned", exit_code);
  if (exiting && exit_code == 0) return 0;
  if (exiting) exit(exit_code);
  if (err || trap) die("the program trapped", err, trap);
  return 0;
}
