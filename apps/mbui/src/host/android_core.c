// The still.fail client core on Android (core_api.h), the way still.fail's own app runs it: ember's engine, prebuilt
// (apps/android/core/src/main/cpp/engine.cpp as libstillfail_hermes.so: Hermes 0.81.4 with its JSI, the core's thread,
// its tasks and timers on CLOCK_BOOTTIME, `__native`, on the Rust shell libstillfail_shell.so). scripts/android.sh
// takes both from ember's `node scripts/native.ts path engine|shell android-arm64` and Hermes from React Native's
// hermes-android, and puts the core, as Hermes bytecode, in the APK's assets (core.hbc: scripts/core.sh hermes).
//
// The engine's JNI entry points (fail.still.core.HermesNative's) are called here as the C functions they are: none of
// them looks at its `this`. What it calls back goes to a dev.mbui.CoreHost (android/): what the core says (onBytes,
// onFrame) comes straight back here, through core_native.c into mbui's queue (mb_post), which asks for the frame that
// takes it; the calls only the app does (`secure.*`: the Android Keystore; `listen.*`: a loopback
// listener, dev.mbui.Loopback) CoreHost answers on threads of its own through the engine's `complete`.
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

#define CORE_LOG(...) __android_log_print(ANDROID_LOG_INFO, "mbui", __VA_ARGS__)

JNIEXPORT jlong JNICALL Java_fail_still_core_HermesNative_start(JNIEnv *, jobject, jbyteArray script, jstring url,
                                                               jstring data_dir, jstring cloud_origin, jboolean beta,
                                                               jobject listener);
JNIEXPORT jlong JNICALL Java_fail_still_core_HermesNative_connect(JNIEnv *, jobject, jlong handle);
JNIEXPORT void JNICALL Java_fail_still_core_HermesNative_receive(JNIEnv *, jobject, jlong handle, jlong client,
                                                                jstring json);
JNIEXPORT void JNICALL Java_fail_still_core_HermesNative_receiveBytes(JNIEnv *, jobject, jlong handle, jlong client,
                                                                     jstring json, jbyteArray bytes);
JNIEXPORT void JNICALL Java_fail_still_core_HermesNative_complete(JNIEnv *, jobject, jlong handle, jlong id,
                                                                 jstring json, jstring error, jbyteArray bytes);
JNIEXPORT void JNICALL Java_fail_still_core_HermesNative_close(JNIEnv *, jobject, jlong handle);
JNIEXPORT void JNICALL Java_fail_still_core_HermesNative_profile(JNIEnv *, jobject, jint seconds, jstring path);
JNIEXPORT jstring JNICALL Java_fail_still_core_HermesNative_shellStats(JNIEnv *, jobject);

JavaVM *mb_android_vm(void);  // android_host.c

static struct {
  int ready;
  jclass host, core_host, string, adb_core;
  jmethodID adb_says;
  jmethodID data_dir, asset, init, started, closing, string_init, secure_test;
  jstring utf8_name;
  jobject listener;  // this core's CoreHost
  jlong handle, client;
  mb_core_message_fn on_message;
  void *ctx;
  int alone;  // started for a push, no app's yet
} A;

// starting, taking and stopping a core: the app's (GL) thread and a push's
static pthread_mutex_t A_lock = PTHREAD_MUTEX_INITIALIZER;

static JNIEnv *core_env(void) {
  JavaVM *vm = mb_android_vm();
  JNIEnv *env = NULL;
  if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) (*vm)->AttachCurrentThread(vm, &env, NULL);
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

// ── what the engine calls back, on the core's thread (CoreHost's natives) ──

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

static void JNICALL on_bytes(JNIEnv *env, jobject self, jbyteArray json) {
  jsize n = (*env)->GetArrayLength(env, json);
  jbyte *p = (*env)->GetByteArrayElements(env, json, NULL);
  if (tracing()) CORE_LOG("core says %.*s%s", n < 400 ? (int)n : 400, (const char *)p, n > 400 ? "…" : "");
  int java = java_said((const char *)p, (size_t)n);
  if (!java && A.on_message) A.on_message((const char *)p, (size_t)n, NULL, 0, A.ctx);
  (*env)->ReleaseByteArrayElements(env, json, p, JNI_ABORT);
  if (java) to_java(env, json);
}

// What the app's Java asks the core (AdbCore.send): the UI's client, the core's thread takes it in order.
static void JNICALL java_send(JNIEnv *env, jclass cls, jstring json) {
  if (!A.handle || !json) return;
  Java_fail_still_core_HermesNative_receive(env, NULL, A.handle, A.client, json);
}

static void JNICALL on_frame(JNIEnv *env, jobject self, jbyteArray json, jbyteArray bytes) {
  static const uint8_t none = 0;
  jsize n = (*env)->GetArrayLength(env, json), bn = bytes ? (*env)->GetArrayLength(env, bytes) : 0;
  jbyte *p = (*env)->GetByteArrayElements(env, json, NULL);
  jbyte *b = bytes ? (*env)->GetByteArrayElements(env, bytes, NULL) : NULL;
  if (A.on_message) A.on_message((const char *)p, (size_t)n, b ? (const uint8_t *)b : &none, (size_t)bn, A.ctx);
  if (b) (*env)->ReleaseByteArrayElements(env, bytes, b, JNI_ABORT);
  (*env)->ReleaseByteArrayElements(env, json, p, JNI_ABORT);
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
  JNINativeMethod natives[] = {
      {"onBytes", "([B)V", (void *)on_bytes},
      {"onFrame", "([B[B)V", (void *)on_frame},
      {"complete", "(JJLjava/lang/String;Ljava/lang/String;[B)V", (void *)Java_fail_still_core_HermesNative_complete},
  };
  (*env)->RegisterNatives(env, A.core_host, natives, 3);
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
        {"sample", "(ILjava/lang/String;)V", (void *)Java_fail_still_core_HermesNative_profile},
        {"shellStats", "()Ljava/lang/String;", (void *)Java_fail_still_core_HermesNative_shellStats},
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
  jstring cloud = jstring_utf8(env, cloud_origin, strlen(cloud_origin));
  jobject listener = (*env)->NewObject(env, A.core_host, A.init, dir);
  A.listener = (*env)->NewGlobalRef(env, listener);
  jsize size = (*env)->GetArrayLength(env, script);
  A.handle = Java_fail_still_core_HermesNative_start(env, NULL, script, name, dir, cloud, beta ? JNI_TRUE : JNI_FALSE,
                                                     A.listener);
  A.client = Java_fail_still_core_HermesNative_connect(env, NULL, A.handle);
  (*env)->CallVoidMethod(env, A.listener, A.started, A.handle);
  cleared(env);
  CORE_LOG("core: started in Hermes (%d bytes of bytecode), its files in %s, cloud %s%s", (int)size, data_dir,
           cloud_origin, beta ? " (beta)" : "");
  (*env)->DeleteLocalRef(env, listener);
  (*env)->DeleteLocalRef(env, script);
  (*env)->DeleteLocalRef(env, name);
  (*env)->DeleteLocalRef(env, dir);
  (*env)->DeleteLocalRef(env, cloud);
}

void mb_core_start(const char *data_dir, const char *cloud_origin, int beta, mb_core_message_fn on_message, void *ctx) {
  pthread_mutex_lock(&A_lock);
  if (!A.handle) {
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
  if (!A.handle) return;
  JNIEnv *env = core_env();
  jstring s = jstring_utf8(env, json, len);
  if (bytes) {
    jbyteArray b = (*env)->NewByteArray(env, (jsize)blen);
    (*env)->SetByteArrayRegion(env, b, 0, (jsize)blen, (const jbyte *)bytes);
    Java_fail_still_core_HermesNative_receiveBytes(env, NULL, A.handle, A.client, s, b);
    (*env)->DeleteLocalRef(env, b);
  } else {
    Java_fail_still_core_HermesNative_receive(env, NULL, A.handle, A.client, s);
  }
  (*env)->DeleteLocalRef(env, s);
}

static void core_stop(void) {
  JNIEnv *env = core_env();
  (*env)->CallVoidMethod(env, A.listener, A.closing);
  cleared(env);
  Java_fail_still_core_HermesNative_close(env, NULL, A.handle);  // joins the core's thread
  A.handle = 0;
  A.on_message = NULL;
  (*env)->DeleteGlobalRef(env, A.listener);
  A.listener = NULL;
  CORE_LOG("core: stopped");
}

void mb_core_stop(void) {
  pthread_mutex_lock(&A_lock);
  if (A.handle) core_stop();
  A.alone = 0;
  pthread_mutex_unlock(&A_lock);
}

// A push's core (dev.mbui.Push, on FCM's thread): the one running, else one started here with no app's client yet (its
// files where the app keeps them, still.fail cloud at `cloud`). True when one runs.
JNIEXPORT jboolean JNICALL Java_dev_mbui_CoreHost_startAlone(JNIEnv *env, jclass c, jstring cloud, jboolean beta) {
  pthread_mutex_lock(&A_lock);
  if (!A.handle) {
    const char *dir = mb_core_data_dir();
    const char *origin = (*env)->GetStringUTFChars(env, cloud, NULL);
    if (dir && origin) {
      core_start(dir, origin, beta ? 1 : 0, NULL, NULL);
      A.alone = A.handle != 0;
    }
    if (origin) (*env)->ReleaseStringUTFChars(env, cloud, origin);
  }
  jboolean running = A.handle != 0;
  pthread_mutex_unlock(&A_lock);
  return running;
}

// The push handled: the core started for it stopped, unless the app has taken it.
JNIEXPORT void JNICALL Java_dev_mbui_CoreHost_stopAlone(JNIEnv *env, jclass c) {
  pthread_mutex_lock(&A_lock);
  if (A.handle && A.alone && !A.on_message) core_stop();
  A.alone = 0;
  pthread_mutex_unlock(&A_lock);
}

// Whether a core runs in this process (the app's, or one a push started).
JNIEXPORT jboolean JNICALL Java_dev_mbui_CoreHost_running(JNIEnv *env, jclass c) { return A.handle != 0; }

/// secure.set/get/delete round-tripped through CoreHost's own answers (MBUI_SECURE_TEST=1 in src/coredemo); the
/// outcome goes to the log (SECURE_TEST …). Returns at once: 0 when there is no CoreHost.
int mb_core_secure_test(void) {
  JNIEnv *env = core_env();
  if (!core_init(env)) return 0;
  (*env)->CallStaticVoidMethod(env, A.core_host, A.secure_test);
  return !cleared(env);
}
