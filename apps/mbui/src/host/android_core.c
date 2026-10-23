// The still.fail client core on Android (core_api.h): the app's engine (apps/mbui/engine, its C API engine.h, prebuilt as
// libstillfail_hermes.so: Hermes 0.81.4 with its JSI, the core's thread, its tasks and timers on CLOCK_BOOTTIME,
// `__native`, on the Rust shell libstillfail_shell.so), the one Windows' app runs too. scripts/android.sh takes both
// from `node scripts/native.ts path engine|shell android-arm64` and Hermes from React Native's hermes-android, and puts
// the core, as Hermes bytecode, in the APK's assets (core.hbc: scripts/core.sh hermes).
//
// What the core says comes straight here, on the core's thread, through core_native.c into mbui's queue (mb_post),
// which asks for the frame that takes it; the calls only the app does (`secure.*`: the Android Keystore; `listen.*`: a
// loopback listener, dev.mbui.Loopback; `picked.*`: a picked file read a part at a time) go to a dev.mbui.CoreHost
// (android/), which answers on threads of its own through the engine's sf_engine_complete.
//
// MB_CORE_TRACE=1 in the app's environment says what the core says (its first 400 bytes) and the app's calls in the
// log.
//
// mb_core_start/send/stop come from the UI's (GL) thread; on_message runs on the core's. A push delivered with no core
// running (the app's process started for it: dev.mbui.Push) starts one alone (CoreHost.startAlone, FCM's thread), which
// the app takes as its own if it starts meanwhile (its on_message set then), else is stopped once the push is handled
// (CoreHost.stopAlone), as still.fail's PushService starts its StillFailCore.
#include <jni.h>
#include <pthread.h>
#include <android/log.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include "core_api.h"
#include "engine.h"

#define CORE_LOG(...) __android_log_print(ANDROID_LOG_INFO, "mbui", __VA_ARGS__)

JavaVM *mb_android_vm(void);  // android_host.c

static struct {
  int ready;
  jclass host, core_host, string, adb_core;
  jmethodID adb_says;
  jmethodID data_dir, asset, init, started, closing, string_init, secure_test, on_app, get_bytes;
  jstring utf8_name;
  jobject listener;  // this core's CoreHost
  sf_engine *engine;
  mb_core_message_fn on_message;
  void *ctx;
  int alone;  // started for a push, no app's yet
} A;

// starting, taking and stopping a core: the app's (GL) thread and a push's
static pthread_mutex_t A_lock = PTHREAD_MUTEX_INITIALIZER;

// A thread this attached to the VM (the core's, as it first calls the app) is detached as it ends: a thread that ends
// attached aborts the process.
static pthread_key_t A_attached;
static pthread_once_t A_attached_once = PTHREAD_ONCE_INIT;

static void detach_thread(void *unused) {
  (void)unused;
  JavaVM *vm = mb_android_vm();
  (*vm)->DetachCurrentThread(vm);
}

static void attached_key(void) { pthread_key_create(&A_attached, detach_thread); }

static JNIEnv *core_env(void) {
  JavaVM *vm = mb_android_vm();
  JNIEnv *env = NULL;
  if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) {
    (*vm)->AttachCurrentThread(vm, &env, NULL);
    pthread_once(&A_attached_once, attached_key);
    pthread_setspecific(A_attached, (void *)1);
  }
  return env;
}

static int cleared(JNIEnv *env) {
  if (!(*env)->ExceptionCheck(env)) return 0;
  (*env)->ExceptionDescribe(env);
  (*env)->ExceptionClear(env);
  return 1;
}

// A Java String of UTF-8 (NewStringUTF takes modified UTF-8, which an emoji is not).
static jstring jstring_utf8(JNIEnv *env, const char *p, size_t n) {
  jbyteArray b = (*env)->NewByteArray(env, (jsize)n);
  (*env)->SetByteArrayRegion(env, b, 0, (jsize)n, (const jbyte *)p);
  jstring s = (jstring)(*env)->NewObject(env, A.string, A.string_init, b, A.utf8_name);
  (*env)->DeleteLocalRef(env, b);
  return s;
}

// A Java String's UTF-8 (its getBytes("UTF-8"): GetStringUTFChars is modified UTF-8), malloc'd, NUL-terminated.
static char *utf8_of(JNIEnv *env, jstring s, size_t *len) {
  jbyteArray b = (jbyteArray)(*env)->CallObjectMethod(env, s, A.get_bytes, A.utf8_name);
  if (cleared(env) || !b) {
    *len = 0;
    return NULL;
  }
  jsize n = (*env)->GetArrayLength(env, b);
  char *out = malloc((size_t)n + 1);
  if (out) {
    (*env)->GetByteArrayRegion(env, b, 0, n, (jbyte *)out);
    out[n] = 0;
  }
  (*env)->DeleteLocalRef(env, b);
  *len = out ? (size_t)n : 0;
  return out;
}

static jbyteArray jbytes(JNIEnv *env, const void *p, size_t n) {
  jbyteArray b = (*env)->NewByteArray(env, (jsize)n);
  if (n) (*env)->SetByteArrayRegion(env, b, 0, (jsize)n, (const jbyte *)p);
  return b;
}

// ── what the engine calls back, on the core's thread (sf_engine_host) ──

static int tracing(void) {
  const char *t = getenv("MB_CORE_TRACE");
  return t && t[0] == '1';
}

// The app's Java (dev.mbui.AdbCore: 共享调试's service, which goes on while the app is behind and its frames stop)
// asks the core on the UI's own client with ids of its own, from java_ids on; what the core says to those (it writes
// the id first: client/core-ts protocol.ts) goes to AdbCore.says, not to the app.
#define JAVA_IDS 1000000000LL

static int java_said(const char *p, size_t n) {
  static const char head[] = "{\"id\":";
  size_t h = sizeof head - 1;
  if (n <= h || memcmp(p, head, h) != 0) return 0;
  long long id = 0;
  size_t i = h;
  if (i < n && p[i] == '-') return 0;
  for (; i < n && p[i] >= '0' && p[i] <= '9' && i < h + 19; i++) id = id * 10 + (p[i] - '0');
  return id >= JAVA_IDS;
}

static void to_java(JNIEnv *env, jbyteArray json) {
  if (!A.adb_core) return;
  (*env)->CallStaticVoidMethod(env, A.adb_core, A.adb_says, json);
  cleared(env);
}

// What the core says: to the app, or (an answer to the app's Java) to AdbCore; a frame's bytes beside its JSON.
static void engine_say(void *ctx, const char *json, size_t len, const uint8_t *bytes, size_t blen) {
  (void)ctx;
  static const uint8_t none = 0;
  if (bytes) {
    if (A.on_message) A.on_message(json, len, blen ? bytes : &none, blen, A.ctx);
    return;
  }
  if (tracing()) CORE_LOG("core says %.*s%s", len < 400 ? (int)len : 400, json, len > 400 ? "…" : "");
  if (java_said(json, len)) {
    JNIEnv *env = core_env();
    jbyteArray b = jbytes(env, json, len);
    to_java(env, b);
    (*env)->DeleteLocalRef(env, b);
    return;
  }
  if (A.on_message) A.on_message(json, len, NULL, 0, A.ctx);
}

// A call only the app does, to its CoreHost (onApp), which answers through complete; one it does not take, failed.
static void engine_app_call(void *ctx, uint64_t id, const char *op, const char *json, size_t len, const uint8_t *bytes,
                            size_t blen) {
  (void)ctx;
  JNIEnv *env = core_env();
  jstring name = (*env)->NewStringUTF(env, op);
  jbyteArray head = jbytes(env, json, len);
  jbyteArray b = bytes ? jbytes(env, bytes, blen) : NULL;
  (*env)->CallVoidMethod(env, A.listener, A.on_app, (jlong)id, name, head, b);
  (*env)->DeleteLocalRef(env, name);
  (*env)->DeleteLocalRef(env, head);
  if (b) (*env)->DeleteLocalRef(env, b);
  if (cleared(env) && A.engine) {
    char why[160];
    int n = snprintf(why, sizeof why, "the app did not take %s", op);
    sf_engine_complete(A.engine, id, NULL, 0, why, (size_t)n, NULL, 0);
  }
}

// The core's log, as still.fail's app had it in logcat (StillFailCore).
static void engine_log(void *ctx, int level, const char *text, size_t len) {
  (void)ctx;
  int priority = level >= 3 ? ANDROID_LOG_ERROR : level == 2 ? ANDROID_LOG_WARN : level == 1 ? ANDROID_LOG_INFO : ANDROID_LOG_DEBUG;
  __android_log_print(priority, "StillFailCore", "%.*s", (int)len, text);
}

// The core's thread, attached to the VM before Hermes runs there (engine.h `thread`): Hermes answers String's
// normalize, Intl and the rest in Java, through fbjni, which takes the thread's JNIEnv as it is.
static void engine_thread(void *ctx) {
  (void)ctx;
  core_env();
}

// What the app's Java asks the core (AdbCore.send): the UI's client, the core's thread takes it in order.
static void JNICALL java_send(JNIEnv *env, jclass cls, jstring json) {
  if (!A.engine || !json) return;
  size_t n = 0;
  char *s = utf8_of(env, json, &n);
  if (s) sf_engine_receive(A.engine, s, n, NULL, 0);
  free(s);
}

// CoreHost's answer to a call it was handed: `error` null when it succeeded. Never after closing (CoreHost.answer).
static void JNICALL host_complete(JNIEnv *env, jclass cls, jlong handle, jlong id, jstring json, jstring error,
                                  jbyteArray bytes) {
  sf_engine *e = (sf_engine *)(intptr_t)handle;
  if (!e) return;
  size_t jn = 0, en = 0;
  char *j = json ? utf8_of(env, json, &jn) : NULL;
  char *er = error ? utf8_of(env, error, &en) : NULL;
  jsize bn = bytes ? (*env)->GetArrayLength(env, bytes) : 0;
  jbyte *b = bytes ? (*env)->GetByteArrayElements(env, bytes, NULL) : NULL;
  static const uint8_t none = 0;
  sf_engine_complete(e, (uint64_t)id, j ? j : "", jn, er, er ? en : 0, bytes ? (b && bn ? (const uint8_t *)b : &none) : NULL,
                     (size_t)bn);
  if (b) (*env)->ReleaseByteArrayElements(env, bytes, b, JNI_ABORT);
  free(j);
  free(er);
}

// The core's JS sampled for `seconds`, its trace written to `path` (CoreProfile.sample).
static void JNICALL profile_sample(JNIEnv *env, jclass cls, jint seconds, jstring path) {
  size_t n = 0;
  char *p = utf8_of(env, path, &n);
  if (p) sf_engine_profile((int)seconds, p);
  free(p);
}

// What the shell has been asked so far, as JSON (CoreProfile.shellStats).
static jstring JNICALL profile_shell_stats(JNIEnv *env, jclass cls) {
  size_t n = 0;
  char *stats = sf_engine_shell_stats(&n);
  jstring s = stats ? jstring_utf8(env, stats, n) : NULL;
  free(stats);
  return s;
}

// The classes and methods, once, from the UI's thread (a thread of the app's, whose class loader finds dev.mbui.*).
static int core_init(JNIEnv *env) {
  if (A.ready) return 1;
  jclass host = (*env)->FindClass(env, "dev/mbui/Host");
  jclass ch = (*env)->FindClass(env, "dev/mbui/CoreHost");
  if (cleared(env) || !host || !ch) return 0;
  A.host = (*env)->NewGlobalRef(env, host);
  A.core_host = (*env)->NewGlobalRef(env, ch);
  A.string = (*env)->NewGlobalRef(env, (*env)->FindClass(env, "java/lang/String"));
  A.string_init = (*env)->GetMethodID(env, A.string, "<init>", "([BLjava/lang/String;)V");
  A.utf8_name = (*env)->NewGlobalRef(env, (*env)->NewStringUTF(env, "UTF-8"));
  A.data_dir = (*env)->GetStaticMethodID(env, A.core_host, "dataDir", "()Ljava/lang/String;");
  A.asset = (*env)->GetStaticMethodID(env, A.core_host, "asset", "(Ljava/lang/String;)[B");
  A.init = (*env)->GetMethodID(env, A.core_host, "<init>", "(Ljava/lang/String;)V");
  A.started = (*env)->GetMethodID(env, A.core_host, "started", "(J)V");
  A.closing = (*env)->GetMethodID(env, A.core_host, "closing", "()V");
  A.secure_test = (*env)->GetStaticMethodID(env, A.core_host, "secureTest", "()V");
  A.on_app = (*env)->GetMethodID(env, A.core_host, "onApp", "(JLjava/lang/String;[B[B)V");
  A.get_bytes = (*env)->GetMethodID(env, A.string, "getBytes", "(Ljava/lang/String;)[B");
  JNINativeMethod natives[] = {
      {"complete", "(JJLjava/lang/String;Ljava/lang/String;[B)V", (void *)host_complete},
  };
  (*env)->RegisterNatives(env, A.core_host, natives, 1);
  if (cleared(env)) return 0;
  // 共享调试's own client (dev.mbui.AdbCore), where the app has it
  jclass adb = (*env)->FindClass(env, "dev/mbui/AdbCore");
  if (!cleared(env) && adb) {
    JNINativeMethod sends[] = {{"send", "(Ljava/lang/String;)V", (void *)java_send}};
    (*env)->RegisterNatives(env, adb, sends, 1);
    A.adb_says = (*env)->GetStaticMethodID(env, adb, "says", "([B)V");
    if (!cleared(env)) A.adb_core = (*env)->NewGlobalRef(env, adb);
    (*env)->DeleteLocalRef(env, adb);
  }
  // the core's JS sampled, and what the shell was asked (the engine's, as still.fail's CoreProfile.kt has them):
  // dev.mbui.CoreProfile's, for CoreProfileReceiver and MemoryWatch (their `this` is the class, which neither reads)
  jclass profile = (*env)->FindClass(env, "dev/mbui/CoreProfile");
  if (!cleared(env) && profile) {
    JNINativeMethod sampling[] = {
        {"sample", "(ILjava/lang/String;)V", (void *)profile_sample},
        {"shellStats", "()Ljava/lang/String;", (void *)profile_shell_stats},
    };
    (*env)->RegisterNatives(env, profile, sampling, 2);
    cleared(env);
    (*env)->DeleteLocalRef(env, profile);
  }
  A.ready = 1;
  return 1;
}

static void say_fatal(const char *why) {
  char buf[512];
  int n = snprintf(buf, sizeof buf, "{\"fatal\":\"%s\"}", why);
  CORE_LOG("core: %s", why);
  if (A.on_message) A.on_message(buf, (size_t)n, NULL, 0, A.ctx);
}

/// The app's files' `core` directory (engine->data_dir in core_client.h): kept once asked.
const char *mb_core_data_dir(void) {
  static char *dir;
  if (dir) return dir;
  JNIEnv *env = core_env();
  if (!core_init(env)) return NULL;
  jstring s = (jstring)(*env)->CallStaticObjectMethod(env, A.core_host, A.data_dir);
  if (cleared(env) || !s) return NULL;
  const char *c = (*env)->GetStringUTFChars(env, s, NULL);
  dir = strdup(c);
  (*env)->ReleaseStringUTFChars(env, s, c);
  (*env)->DeleteLocalRef(env, s);
  return dir;
}

static void core_start(const char *data_dir, const char *cloud_origin, int beta, mb_core_message_fn on_message, void *ctx) {
  A.on_message = on_message;
  A.ctx = ctx;
  JNIEnv *env = core_env();
  if (!core_init(env)) {
    say_fatal("the app has no dev.mbui.CoreHost");
    return;
  }
  jstring name = (*env)->NewStringUTF(env, "core.hbc");
  jbyteArray script = (jbyteArray)(*env)->CallStaticObjectMethod(env, A.core_host, A.asset, name);
  if (cleared(env) || !script) {
    (*env)->DeleteLocalRef(env, name);
    say_fatal("no core script (core.hbc in the app's assets: scripts/android.sh build with APP=coredemo)");
    return;
  }
  if (mkdir(data_dir, 0700) != 0 && errno != EEXIST) CORE_LOG("core: mkdir %s: %s", data_dir, strerror(errno));
  jstring dir = jstring_utf8(env, data_dir, strlen(data_dir));
  jobject listener = (*env)->NewObject(env, A.core_host, A.init, dir);
  A.listener = (*env)->NewGlobalRef(env, listener);
  jsize size = (*env)->GetArrayLength(env, script);
  jbyte *code = (*env)->GetByteArrayElements(env, script, NULL);
  sf_engine_host host = {NULL, engine_say, engine_app_call, engine_log, engine_thread};
  A.engine = sf_engine_start((const uint8_t *)code, (size_t)size, "core.hbc", data_dir, cloud_origin, beta, "android", &host);
  (*env)->ReleaseByteArrayElements(env, script, code, JNI_ABORT);
  if (!A.engine) {
    (*env)->DeleteGlobalRef(env, A.listener);
    A.listener = NULL;
    say_fatal("the core's thread did not start");
  } else {
    (*env)->CallVoidMethod(env, A.listener, A.started, (jlong)(intptr_t)A.engine);
    cleared(env);
    CORE_LOG("core: started in Hermes (%d bytes of bytecode), its files in %s, cloud %s%s", (int)size, data_dir,
             cloud_origin, beta ? " (beta)" : "");
  }
  (*env)->DeleteLocalRef(env, listener);
  (*env)->DeleteLocalRef(env, script);
  (*env)->DeleteLocalRef(env, name);
  (*env)->DeleteLocalRef(env, dir);
}

void mb_core_start(const char *data_dir, const char *cloud_origin, int beta, mb_core_message_fn on_message, void *ctx) {
  pthread_mutex_lock(&A_lock);
  if (!A.engine) {
    core_start(data_dir, cloud_origin, beta, on_message, ctx);
  } else if (!A.on_message) {
    // one started for a push: the app's from now on
    A.on_message = on_message;
    A.ctx = ctx;
    A.alone = 0;
    CORE_LOG("core: the one started for a push taken by the app");
  }
  pthread_mutex_unlock(&A_lock);
}

void mb_core_send(const char *json, size_t len, const uint8_t *bytes, size_t blen) {
  if (!A.engine) return;
  static const uint8_t none = 0;
  sf_engine_receive(A.engine, json, len, bytes ? (blen ? bytes : &none) : NULL, blen);
}

static void core_stop(void) {
  JNIEnv *env = core_env();
  (*env)->CallVoidMethod(env, A.listener, A.closing);
  cleared(env);
  sf_engine_stop(A.engine);  // joins the core's thread
  A.engine = NULL;
  A.on_message = NULL;
  (*env)->DeleteGlobalRef(env, A.listener);
  A.listener = NULL;
  CORE_LOG("core: stopped");
}

void mb_core_stop(void) {
  pthread_mutex_lock(&A_lock);
  if (A.engine) core_stop();
  A.alone = 0;
  pthread_mutex_unlock(&A_lock);
}

// A push's core (dev.mbui.Push, on FCM's thread): the one running, else one started here with no app's client yet (its
// files where the app keeps them, still.fail cloud at `cloud`). True when one runs.
JNIEXPORT jboolean JNICALL Java_dev_mbui_CoreHost_startAlone(JNIEnv *env, jclass c, jstring cloud, jboolean beta) {
  pthread_mutex_lock(&A_lock);
  if (!A.engine) {
    const char *dir = mb_core_data_dir();
    const char *origin = (*env)->GetStringUTFChars(env, cloud, NULL);
    if (dir && origin) {
      core_start(dir, origin, beta ? 1 : 0, NULL, NULL);
      A.alone = A.engine != NULL;
    }
    if (origin) (*env)->ReleaseStringUTFChars(env, cloud, origin);
  }
  jboolean running = A.engine != NULL;
  pthread_mutex_unlock(&A_lock);
  return running;
}

// The push handled: the core started for it stopped, unless the app has taken it.
JNIEXPORT void JNICALL Java_dev_mbui_CoreHost_stopAlone(JNIEnv *env, jclass c) {
  pthread_mutex_lock(&A_lock);
  if (A.engine && A.alone && !A.on_message) core_stop();
  A.alone = 0;
  pthread_mutex_unlock(&A_lock);
}

// Whether a core runs in this process (the app's, or one a push started).
JNIEXPORT jboolean JNICALL Java_dev_mbui_CoreHost_running(JNIEnv *env, jclass c) { return A.engine != NULL; }

/// secure.set/get/delete round-tripped through CoreHost's own answers (MBUI_SECURE_TEST=1 in src/coredemo); the
/// outcome goes to the log (SECURE_TEST …). Returns at once: 0 when there is no CoreHost.
int mb_core_secure_test(void) {
  JNIEnv *env = core_env();
  if (!core_init(env)) return 0;
  (*env)->CallStaticVoidMethod(env, A.core_host, A.secure_test);
  return !cleared(env);
}
