// Android host: the C side of android/ (dev.mbui.*). Java owns the
// Activity, the GLSurfaceView, input and the input method; this file owns the
// GLES3 renderer and forwards between Java and the MoonBit callbacks. All
// MoonBit code runs on the GL thread. Built by scripts/android.sh.
#include <jni.h>
#include <GLES3/gl3.h>
#include <android/log.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "moonbit.h"

#define LOG(...) __android_log_print(ANDROID_LOG_INFO, "mbui", __VA_ARGS__)

typedef void (*mb_frame_fn)(double, double, double, double);
typedef void (*mb_pointer_fn)(int32_t, double, double, int32_t);
typedef void (*mb_wheel_fn)(double, double, double, double, int32_t);
typedef void (*mb_key_fn)(int32_t, int32_t);
typedef void (*mb_text_fn)(int32_t, moonbit_string_t, int32_t, int32_t);

static struct {
  mb_frame_fn frame;
  mb_pointer_fn pointer;
  mb_wheel_fn wheel;
  mb_key_fn key;
  mb_text_fn text;
} cb;

static JavaVM *vm;
static jclass host_cls, text_cls;
static jmethodID m_request_frame, m_wake_after, m_set_ime, m_clipboard, m_log, m_bench,
    m_exit, m_metrics, m_shape, m_glyph, m_generation;
static jdoubleArray shape_buf, small_buf;
static int want_frame;

int mbui_main(int argc, char **argv);  // the MoonBit program's main (renamed)

static JNIEnv *env_(void) {
  JNIEnv *env = NULL;
  (*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6);
  return env;
}

JNIEXPORT jint JNI_OnLoad(JavaVM *v, void *reserved) {
  vm = v;
  JNIEnv *env = env_();
  host_cls = (*env)->NewGlobalRef(env, (*env)->FindClass(env, "dev/mbui/Host"));
  text_cls = (*env)->NewGlobalRef(env, (*env)->FindClass(env, "dev/mbui/MBText"));
  m_request_frame = (*env)->GetStaticMethodID(env, host_cls, "requestFrame", "()V");
  m_wake_after = (*env)->GetStaticMethodID(env, host_cls, "wakeAfter", "(D)V");
  m_set_ime = (*env)->GetStaticMethodID(env, host_cls, "setIme", "(ZDDDDLjava/lang/String;II)V");
  m_clipboard = (*env)->GetStaticMethodID(env, host_cls, "clipboardSet", "(Ljava/lang/String;)V");
  m_log = (*env)->GetStaticMethodID(env, host_cls, "log", "(Ljava/lang/String;)V");
  m_bench = (*env)->GetStaticMethodID(env, host_cls, "benchMode", "()I");
  m_exit = (*env)->GetStaticMethodID(env, host_cls, "exit", "(I)V");
  m_metrics = (*env)->GetStaticMethodID(env, text_cls, "fontMetrics", "(DI[D)V");
  m_shape = (*env)->GetStaticMethodID(env, text_cls, "shape", "(Ljava/lang/String;DI[D)I");
  m_glyph = (*env)->GetStaticMethodID(env, text_cls, "glyph", "(I[D)V");
  m_generation = (*env)->GetStaticMethodID(env, text_cls, "atlasGeneration", "()I");
  shape_buf = (*env)->NewGlobalRef(env, (*env)->NewDoubleArray(env, 4 * 8192));
  small_buf = (*env)->NewGlobalRef(env, (*env)->NewDoubleArray(env, 16));
  return JNI_VERSION_1_6;
}

static jstring jstr(JNIEnv *env, moonbit_string_t s) {
  return (*env)->NewString(env, (const jchar *)s, Moonbit_array_length(s));
}

static moonbit_string_t mstr(JNIEnv *env, jstring s) {
  jsize n = (*env)->GetStringLength(env, s);
  moonbit_string_t out = moonbit_make_string_raw(n);
  (*env)->GetStringRegion(env, s, 0, n, (jchar *)out);
  return out;
}

// ---------------------------------------------------------------------------
// Renderer: the same instances and shader as Metal and WebGL2.

static const char *VS =
    "#version 300 es\n"
    "layout(location=0) in vec4 a_rect;\n"
    "layout(location=1) in vec4 a_p;\n"
    "layout(location=2) in vec4 a_color;\n"
    "layout(location=3) in vec4 a_c2;\n"
    "layout(location=4) in vec4 a_clip;\n"
    "uniform vec2 u_vp;\n"
    "out vec2 v_pos;\n"
    "flat out vec4 v_rect; flat out vec4 v_p; flat out vec4 v_color; flat out vec4 v_c2; flat out vec4 v_clip;\n"
    "void main() {\n"
    "  int vid = gl_VertexID;\n"
    "  vec2 corner = vec2((vid == 1 || vid == 4 || vid == 5) ? 1.0 : 0.0, (vid == 2 || vid == 3 || vid == 5) ? 1.0 : 0.0);\n"
    "  int kind = int(a_p.y + 0.5);\n"
    "  float grow = kind == 2 ? a_p.w * 2.0 + 2.0 : (kind == 0 ? 1.0 : 0.0);\n"
    "  vec2 pos = a_rect.xy - grow + corner * (a_rect.zw + 2.0 * grow);\n"
    "  gl_Position = vec4(pos.x / u_vp.x * 2.0 - 1.0, 1.0 - pos.y / u_vp.y * 2.0, 0.0, 1.0);\n"
    "  v_pos = pos; v_rect = a_rect; v_p = a_p; v_color = a_color; v_c2 = a_c2; v_clip = a_clip;\n"
    "}\n";

static const char *FS =
    "#version 300 es\n"
    "precision highp float;\n"
    "in vec2 v_pos;\n"
    "flat in vec4 v_rect; flat in vec4 v_p; flat in vec4 v_color; flat in vec4 v_c2; flat in vec4 v_clip;\n"
    "uniform float u_scale;\n"
    "uniform sampler2D u_atlas;\n"
    "out vec4 o;\n"
    "void main() {\n"
    "  vec2 p = v_pos;\n"
    "  if (p.x < v_clip.x || p.y < v_clip.y || p.x > v_clip.z || p.y > v_clip.w) discard;\n"
    "  int kind = int(v_p.y + 0.5);\n"
    "  vec4 col = v_color;\n"
    "  if (kind == 1 || kind == 3) {\n"
    "    vec2 uv = (v_c2.xy + (p - v_rect.xy) / v_rect.zw * v_c2.zw) / 2048.0;\n"
    "    vec4 t = texture(u_atlas, uv);\n"
    "    o = kind == 1 ? vec4(col.rgb, 1.0) * (t.a * col.a) : t * col.a;\n"
    "    return;\n"
    "  }\n"
    "  vec2 hs = v_rect.zw * 0.5;\n"
    "  vec2 c = v_rect.xy + hs;\n"
    "  float r = min(v_p.x, min(hs.x, hs.y));\n"
    "  vec2 q = abs(p - c) - hs + r;\n"
    "  float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;\n"
    "  if (kind == 2) {\n"
    "    float b = max(v_p.w, 0.5);\n"
    "    float a = 1.0 - smoothstep(-b, b, d);\n"
    "    o = vec4(col.rgb, 1.0) * col.a * a;\n"
    "    return;\n"
    "  }\n"
    "  float a = clamp(0.5 - d * u_scale, 0.0, 1.0);\n"
    "  vec4 fill = vec4(col.rgb, 1.0) * col.a;\n"
    "  if (v_p.z > 0.0) {\n"
    "    float inner = clamp(0.5 - (d + v_p.z) * u_scale, 0.0, 1.0);\n"
    "    vec4 bc = vec4(v_c2.rgb, 1.0) * v_c2.a;\n"
    "    fill = mix(bc, fill, inner);\n"
    "  }\n"
    "  o = fill * a;\n"
    "}\n";

static GLuint prog, vao, vbo, atlas;
static GLint u_vp, u_scale, u_atlas;
static float *fbuf;
static size_t fcap;
static int fb_w, fb_h;
static double cur_w, cur_h, cur_scale;

static GLuint compile(GLenum type, const char *src) {
  GLuint s = glCreateShader(type);
  glShaderSource(s, 1, &src, NULL);
  glCompileShader(s);
  GLint ok = 0;
  glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
  if (!ok) {
    char log[2048];
    glGetShaderInfoLog(s, sizeof log, NULL, log);
    LOG("shader: %s", log);
  }
  return s;
}

JNIEXPORT void JNICALL Java_dev_mbui_Native_surfaceCreated(JNIEnv *env, jclass c) {
  prog = glCreateProgram();
  glAttachShader(prog, compile(GL_VERTEX_SHADER, VS));
  glAttachShader(prog, compile(GL_FRAGMENT_SHADER, FS));
  glLinkProgram(prog);
  u_vp = glGetUniformLocation(prog, "u_vp");
  u_scale = glGetUniformLocation(prog, "u_scale");
  u_atlas = glGetUniformLocation(prog, "u_atlas");
  glGenVertexArrays(1, &vao);
  glBindVertexArray(vao);
  glGenBuffers(1, &vbo);
  glBindBuffer(GL_ARRAY_BUFFER, vbo);
  for (int i = 0; i < 5; i++) {
    glEnableVertexAttribArray(i);
    glVertexAttribPointer(i, 4, GL_FLOAT, GL_FALSE, 96, (void *)(intptr_t)(i * 16));
    glVertexAttribDivisor(i, 1);
  }
  glGenTextures(1, &atlas);
  glBindTexture(GL_TEXTURE_2D, atlas);
  glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA8, 2048, 2048);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glEnable(GL_BLEND);
  glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
}

JNIEXPORT jint JNICALL Java_dev_mbui_Native_atlasTexture(JNIEnv *env, jclass c) { return (jint)atlas; }

JNIEXPORT void JNICALL Java_dev_mbui_Native_resize(JNIEnv *env, jclass c, jint w, jint h) {
  fb_w = w;
  fb_h = h;
}

void mb_host_present(double *buf, int32_t count, double r, double g, double b) {
  glViewport(0, 0, fb_w, fb_h);
  glClearColor((float)r, (float)g, (float)b, 1);
  glClear(GL_COLOR_BUFFER_BIT);
  if (count <= 0) return;
  size_t n = (size_t)count * 24;
  if (fcap < n) {
    fcap = n * 2;
    fbuf = realloc(fbuf, fcap * sizeof(float));
  }
  for (size_t i = 0; i < n; i++) fbuf[i] = (float)buf[i];
  glUseProgram(prog);
  glBindVertexArray(vao);
  glBindBuffer(GL_ARRAY_BUFFER, vbo);
  glBufferData(GL_ARRAY_BUFFER, n * sizeof(float), fbuf, GL_STREAM_DRAW);
  glUniform2f(u_vp, (float)cur_w, (float)cur_h);
  glUniform1f(u_scale, (float)cur_scale);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, atlas);
  glUniform1i(u_atlas, 0);
  glDrawArraysInstanced(GL_TRIANGLES, 0, 6, count);
}

// ---------------------------------------------------------------------------
// Java -> MoonBit

JNIEXPORT void JNICALL Java_dev_mbui_Native_start(JNIEnv *env, jclass c) {
  char *argv[] = {"mbui", NULL};
  mbui_main(1, argv);  // runs MoonBit's main, which registers the callbacks
}

JNIEXPORT jboolean JNICALL Java_dev_mbui_Native_frame(JNIEnv *env, jclass c, jfloat w, jfloat h,
                                                     jfloat scale, jdouble now) {
  cur_w = w;
  cur_h = h;
  cur_scale = scale;
  want_frame = 0;
  if (cb.frame) cb.frame(w, h, scale, now);
  return want_frame ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL Java_dev_mbui_Native_pointer(JNIEnv *env, jclass c, jint kind, jfloat x,
                                                   jfloat y) {
  if (cb.pointer) cb.pointer(kind, x, y, 0);
}

JNIEXPORT void JNICALL Java_dev_mbui_Native_key(JNIEnv *env, jclass c, jint code, jint mods) {
  if (cb.key) cb.key(code, mods);
}

JNIEXPORT void JNICALL Java_dev_mbui_Native_text(JNIEnv *env, jclass c, jint kind, jstring s,
                                                jint a, jint b) {
  if (cb.text) cb.text(kind, mstr(env, s), a, b);
}

// ---------------------------------------------------------------------------
// The host API MoonBit calls

void mb_host_run(moonbit_string_t title, mb_frame_fn frame, mb_pointer_fn pointer,
                 mb_wheel_fn wheel, mb_key_fn key, mb_text_fn text) {
  cb.frame = frame;
  cb.pointer = pointer;
  cb.wheel = wheel;
  cb.key = key;
  cb.text = text;
}

double mb_host_now(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec * 1000.0 + t.tv_nsec / 1e6;
}

void mb_host_request_frame(void) {
  want_frame = 1;
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, host_cls, m_request_frame);
}

void mb_host_wake_after(double ms) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, host_cls, m_wake_after, ms);
}

void mb_host_font_metrics(double size, int32_t weight, double *out) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, text_cls, m_metrics, size, weight, small_buf);
  (*env)->GetDoubleArrayRegion(env, small_buf, 0, 3, out);
}

int32_t mb_host_shape(moonbit_string_t text, double size, int32_t weight, double *out) {
  JNIEnv *env = env_();
  jstring s = jstr(env, text);
  jint n = (*env)->CallStaticIntMethod(env, text_cls, m_shape, s, size, weight, shape_buf);
  (*env)->DeleteLocalRef(env, s);
  int32_t cap = Moonbit_array_length(out) / 4;
  if (n > cap) n = cap;
  (*env)->GetDoubleArrayRegion(env, shape_buf, 0, n * 4, out);
  return n;
}

void mb_host_glyph(int32_t key, double *out) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, text_cls, m_glyph, key, small_buf);
  (*env)->GetDoubleArrayRegion(env, small_buf, 0, 7, out);
}

int32_t mb_host_atlas_generation(void) {
  JNIEnv *env = env_();
  return (*env)->CallStaticIntMethod(env, text_cls, m_generation);
}

void mb_host_set_ime(int32_t active, double x, double y, double w, double h, moonbit_string_t text,
                     int32_t a, int32_t b) {
  JNIEnv *env = env_();
  jstring s = jstr(env, text);
  (*env)->CallStaticVoidMethod(env, host_cls, m_set_ime, (jboolean)(active != 0), x, y, w, h, s,
                               a, b);
  (*env)->DeleteLocalRef(env, s);
}

void mb_host_clipboard_set(moonbit_string_t s) {
  JNIEnv *env = env_();
  jstring j = jstr(env, s);
  (*env)->CallStaticVoidMethod(env, host_cls, m_clipboard, j);
  (*env)->DeleteLocalRef(env, j);
}

void mb_host_log(moonbit_string_t s) {
  JNIEnv *env = env_();
  jstring j = jstr(env, s);
  (*env)->CallStaticVoidMethod(env, host_cls, m_log, j);
  (*env)->DeleteLocalRef(env, j);
}

int32_t mb_host_bench_mode(void) {
  JNIEnv *env = env_();
  return (*env)->CallStaticIntMethod(env, host_cls, m_bench);
}

void mb_host_exit(int32_t code) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, host_cls, m_exit, code);
}

double mb_host_mem_bytes(void) {
  FILE *f = fopen("/proc/self/statm", "r");
  if (!f) return 0;
  long pages = 0, rss = 0;
  if (fscanf(f, "%ld %ld", &pages, &rss) != 2) rss = 0;
  fclose(f);
  return (double)rss * 4096.0;
}

JNIEXPORT jboolean JNICALL Java_dev_mbui_Native_snapshot(JNIEnv *env, jclass c, jstring path) {
  return JNI_FALSE;  // screenshots come from `adb exec-out screencap`
}

// ---- images: not decoded on this platform yet; every load fails ----

int32_t mb_host_image_load(moonbit_string_t src, int32_t max_px) { (void)src; (void)max_px; return 0; }
int32_t mb_host_image_load_bytes(moonbit_bytes_t data, int32_t max_px) { (void)data; (void)max_px; return 0; }
int32_t mb_host_image_info(int32_t id, double *out) { (void)id; (void)out; return -1; }
void mb_host_image_free(int32_t id) { (void)id; }
