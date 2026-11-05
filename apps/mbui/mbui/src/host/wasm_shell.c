// The native shell of a program run in classic Wasm (the user, 2026-11-03: no C compiled for an app in development):
// the C host linked as the native program links it, and the program, an app's .wasm, run by wasmtime over it. Its
// imports are the host's C calls (wasm_thunks.c, written by tools/wasmhost), what its calls of the host give and take
// (mbw_take_string, mbw_take_bytes: mbui/wasmrt), and what MoonBit's own runtime asks (a line written, an exit, the
// time, the process's arguments and environment). The program's main runs as the native program's does: the host's
// run (mb_host_run) does not come back while the app is up, the program called into from inside it.
//
//     SHELL PROGRAM.wasm [ARGS…]      (MBUI_WASM_APP: PROGRAM.wasm, where no argument says; PROGRAM.cwasm: compiled
//                                     ahead for this machine by wasmtime's command line, a device's)
#include "wasmhost.h"
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
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

static void die(const char *what, wasmtime_error_t *err, wasm_trap_t *trap) {
  wasm_byte_vec_t msg = {0};
  if (err) wasmtime_error_message(err, &msg);
  else if (trap) wasm_trap_message(trap, &msg);
  say("wasm shell: %s%s%.*s\n", what, msg.size ? ": " : "", (int)msg.size, msg.data ? msg.data : "");
  exit(1);
}

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

void mbw_call(const wasmtime_func_t *f, wasmtime_val_t *args, size_t n, wasmtime_val_t *res, size_t nr) {
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

static wasm_trap_t *print_char(void *env, wasmtime_caller_t *caller, const wasmtime_val_t *a, size_t na,
                               wasmtime_val_t *r, size_t nr) {
  (void)env; (void)caller; (void)na; (void)r; (void)nr;
  char c = (char)a[0].of.i32;
  fwrite(&c, 1, 1, stdout);
  return NULL;
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

// A film's bench run here (mbui/src/film/bench.mbt, still.fail's src/sfbench): the file it reads (its script), the
// clock its work is timed by; what it draws not drawn (its frames' work the program's own, timed by it: no renderer
// here), each step answered done.
static wasm_trap_t *film_read(void *env, wasmtime_caller_t *caller, const wasmtime_val_t *a, size_t na,
                              wasmtime_val_t *r, size_t nr) {
  (void)env; (void)caller; (void)a; (void)na; (void)r; (void)nr;
  char *path = film_text();
  FILE *f = fopen(path, "rb");
  free(path);
  free(film_got);
  film_got = NULL;
  film_got_n = 0;
  if (!f) return NULL;
  fseek(f, 0, SEEK_END);
  long n = ftell(f);
  fseek(f, 0, SEEK_SET);
  unsigned char *v = malloc((size_t)n + 1);
  size_t got = fread(v, 1, (size_t)n, f);
  fclose(f);
  film_got = malloc((got + 1) * 2);
  for (size_t i = 0; i < got;) {
    unsigned char c = v[i];
    uint32_t u;
    if (c < 0x80) { u = c; i += 1; }
    else if (c < 0xe0 && i + 1 < got) { u = (uint32_t)(c & 31) << 6 | (v[i + 1] & 63); i += 2; }
    else if (c < 0xf0 && i + 2 < got) { u = (uint32_t)(c & 15) << 12 | (uint32_t)(v[i + 1] & 63) << 6 | (v[i + 2] & 63); i += 3; }
    else { u = 0xfffd; i += 1; }
    film_got[film_got_n++] = (uint16_t)u;
  }
  free(v);
  return NULL;
}

static wasm_trap_t *film_now(void *env, wasmtime_caller_t *caller, const wasmtime_val_t *a, size_t na,
                             wasmtime_val_t *r, size_t nr) {
  (void)env; (void)caller; (void)a; (void)na; (void)nr;
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  r[0].kind = WASMTIME_F64;
  r[0].of.f64 = (double)t.tv_sec * 1000.0 + (double)t.tv_nsec / 1e6;
  return NULL;
}

static wasm_trap_t *film_done(void *env, wasmtime_caller_t *caller, const wasmtime_val_t *a, size_t na,
                              wasmtime_val_t *r, size_t nr) {
  (void)env; (void)caller; (void)a; (void)na;
  if (nr > 0) {
    r[0].kind = WASMTIME_I32;
    r[0].of.i32 = 1;
  }
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
// Where an Android app's program lies, unless MBUI_WASM_APP says: app.cwasm in its files (the package's, as the process
// is named: scripts/wasm-app.sh compiles it for the device and puts it there)
static const char *android_program(void) {
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
  snprintf(path, sizeof path, "/data/data/%s/files/app.cwasm", name);
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
  // (MBUI_WASM_STACK: how deep the program's own stack may go, in bytes, wasmtime's default 512 KiB otherwise: what a
  // run measures the stack a step takes by)
  if (getenv("MBUI_WASM_STACK") && *getenv("MBUI_WASM_STACK")) {
    wasmtime_config_max_wasm_stack_set(config, (size_t)strtoull(getenv("MBUI_WASM_STACK"), NULL, 10));
  }
  // (a program built for Wasm GC as well as a classic one: its objects the engine's, its values crossing in a memory the
  // shell gives it, mbui/wasmrt's wasmrt_gc.mbt)
  wasmtime_config_wasm_gc_set(config, true);
  wasmtime_config_wasm_function_references_set(config, true);
  wasm_engine_t *engine = wasm_engine_new_with_config(config);
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
  // (each by the type the program asks it as: a Wasm GC program's function references are typed, (ref $f), which a
  // function of the shell's own type, funcref, does not match)
  wasm_importtype_vec_t asked;
  wasmtime_module_imports(module, &asked);
  for (const mbw_import *i = mbw_imports; i->name; i++) {
    wasm_functype_t *ty = NULL;
    for (size_t k = 0; k < asked.size && !ty; k++) {
      const wasm_name_t *m = wasm_importtype_module(asked.data[k]);
      const wasm_name_t *n = wasm_importtype_name(asked.data[k]);
      const wasm_functype_t *f = wasm_externtype_as_functype_const(wasm_importtype_type(asked.data[k]));
      if (f && m->size == 6 && memcmp(m->data, "mbhost", 6) == 0 && n->size == strlen(i->name) &&
          memcmp(n->data, i->name, n->size) == 0)
        ty = wasm_functype_copy(f);
    }
    define(linker, "mbhost", i->name, i->fn, NULL, ty ? ty : functype(i->np, i->p, i->nr, i->r));
  }
  wasm_importtype_vec_delete(&asked);
  wasm_valkind_t i32[4] = {WASM_I32, WASM_I32, WASM_I32, WASM_I32};
  define(linker, "mbhost", "mbw_take_string", take_string, NULL, functype(1, i32, 0, NULL));
  define(linker, "mbhost", "mbw_take_bytes", take_bytes, NULL, functype(1, i32, 0, NULL));
  define(linker, "wasi_snapshot_preview1", "fd_write", fd_write, NULL, functype(4, i32, 1, i32));
  // (a Wasm GC program's print: a character a call)
  define(linker, "spectest", "print_char", print_char, NULL, functype(1, i32, 0, NULL));
  define(linker, "wasi_snapshot_preview1", "proc_exit", proc_exit, NULL, functype(1, i32, 0, NULL));
  define(linker, "film", "arg", film_arg, NULL, functype(0, NULL, 0, NULL));
  define(linker, "film", "gotLength", film_got_length, NULL, functype(0, NULL, 1, i32));
  define(linker, "film", "gotUnit", film_got_unit, NULL, functype(1, i32, 1, i32));
  define(linker, "film", "say", film_say, NULL, functype(0, NULL, 0, NULL));
  define(linker, "film", "exit", proc_exit, NULL, functype(1, i32, 0, NULL));
  {
    wasm_valkind_t f64[3] = {WASM_F64, WASM_F64, WASM_F64};
    wasm_valkind_t dddd[4] = {WASM_I32, WASM_F64, WASM_F64, WASM_F64};
    define(linker, "film", "read", film_read, NULL, functype(0, NULL, 0, NULL));
    define(linker, "film", "now", film_now, NULL, functype(0, NULL, 1, f64));
    define(linker, "film", "hold", film_done, NULL, functype(0, NULL, 0, NULL));
    define(linker, "film", "write", film_done, NULL, functype(0, NULL, 1, i32));
    define(linker, "film", "init", film_done, NULL, functype(3, f64, 0, NULL));
    define(linker, "film", "view", film_done, NULL, functype(3, f64, 0, NULL));
    define(linker, "film", "open", film_done, NULL, functype(3, i32, 1, i32));
    define(linker, "film", "draw", film_done, NULL, functype(4, dddd, 1, i32));
    define(linker, "film", "put", film_done, NULL, functype(1, i32, 1, i32));
    define(linker, "film", "close", film_done, NULL, functype(1, i32, 1, i32));
    define(linker, "film", "finish", film_done, NULL, functype(1, i32, 1, i32));
    define(linker, "film", "snapshot", film_done, NULL, functype(1, i32, 1, i32));
    define(linker, "film", "spin", film_done, NULL, functype(1, f64, 0, NULL));
  }
  // what else the program imports, a function that ends it saying which as it is called; the memory a Wasm GC program
  // asks for (env.memory), the shell's
  wasm_importtype_vec_t imports;
  wasmtime_module_imports(module, &imports);
  for (size_t k = 0; k < imports.size; k++) {
    const wasm_name_t *mod = wasm_importtype_module(imports.data[k]);
    const wasm_name_t *name = wasm_importtype_name(imports.data[k]);
    const wasm_externtype_t *ty = wasm_importtype_type(imports.data[k]);
    const wasm_memorytype_t *mty = wasm_externtype_as_memorytype_const(ty);
    if (mty && !has_memory) {
      wasmtime_error_t *merr = wasmtime_memory_new(ctx, mty, &memory);
      if (merr) die("no memory for the program", merr, NULL);
      wasmtime_extern_t given = {.kind = WASMTIME_EXTERN_MEMORY, .of.memory = memory};
      merr = wasmtime_linker_define(linker, ctx, mod->data, mod->size, name->data, name->size, &given);
      if (merr) die("the program's memory", merr, NULL);
      has_memory = 1;
      continue;
    }
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
  wasmtime_instance_t instance;
  wasm_trap_t *trap = NULL;
  err = wasmtime_linker_instantiate(linker, ctx, module, &instance, &trap);
  if (err || trap) die("the program could not start", err, trap);
  wasmtime_extern_t item;
  if (!has_memory) {
    if (!wasmtime_instance_export_get(ctx, &instance, "memory", 6, &item) || item.kind != WASMTIME_EXTERN_MEMORY)
      die("the program exports no memory", NULL, NULL);
    memory = item.of.memory;
    has_memory = 1;
  }
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
