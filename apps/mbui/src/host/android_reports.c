// still.fail's own host's side of src/stillfail/reports.mbt on Android (src/stillfail/android_engine.c includes it,
// after android_core.c): what the app tells it handed to dev.mbui.Reports.tell (android/app/src/main/java/dev/mbui:
// Crashes.java, BarTiming.java), on the UI's (GL) thread it is called from, whose class loader finds dev.mbui.*.
#include <jni.h>
#include "moonbit.h"

static jclass reports_class;
static jmethodID reports_tell;

static jstring reports_string(JNIEnv *env, moonbit_string_t s) {
  return (*env)->NewString(env, (const jchar *)s, (jsize)Moonbit_array_length(s));
}

/// Reports.tell(what, a, b, n, m): what it answers (0 when there is no Reports to tell).
int32_t mb_stillfail_tell(moonbit_string_t what, moonbit_string_t a, moonbit_string_t b, int32_t n, int32_t m) {
  JNIEnv *env = core_env();
  if (!reports_tell) {
    jclass c = (*env)->FindClass(env, "dev/mbui/Reports");
    if (cleared(env) || !c) return 0;
    jmethodID tell = (*env)->GetStaticMethodID(env, c, "tell",
                                               "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;II)I");
    if (cleared(env) || !tell) return 0;
    reports_class = (*env)->NewGlobalRef(env, c);
    (*env)->DeleteLocalRef(env, c);
    reports_tell = tell;
  }
  jstring jw = reports_string(env, what), ja = reports_string(env, a), jb = reports_string(env, b);
  jint r = (*env)->CallStaticIntMethod(env, reports_class, reports_tell, jw, ja, jb, (jint)n, (jint)m);
  if (cleared(env)) r = 0;
  (*env)->DeleteLocalRef(env, jw);
  (*env)->DeleteLocalRef(env, ja);
  (*env)->DeleteLocalRef(env, jb);
  return (int32_t)r;
}
