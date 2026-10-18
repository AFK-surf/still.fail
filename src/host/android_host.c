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
typedef void (*mb_back_fn)(int32_t, double, double, int32_t);

static struct {
  mb_frame_fn frame;
  mb_pointer_fn pointer;
  mb_wheel_fn wheel;
  mb_key_fn key;
  mb_text_fn text;
} cb;

static JavaVM *vm;
static jclass host_cls, text_cls, images_cls, login_cls;
static jmethodID m_request_frame, m_wake_after, m_set_ime, m_clipboard, m_log, m_bench,
    m_exit, m_metrics, m_shape, m_glyph, m_generation, m_img_load, m_img_free, m_img_reload, m_bl_start, m_bl_port,
    m_bl_open, m_bl_back, m_bl_end, m_back_enabled;
static mb_back_fn back_cb;
static jdoubleArray shape_buf, small_buf;
static int want_frame;

int mbui_main(int argc, char **argv);  // the MoonBit program's main (renamed)

// The process's VM, for the still.fail core's engine (android_core.c).
JavaVM *mb_android_vm(void) { return vm; }

// The core's queue, drained as each frame begins (src/core/core_native.c), in apps that link mbui/core's engine.
extern void mbc_frame(void) __attribute__((weak));

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
  images_cls = (*env)->NewGlobalRef(env, (*env)->FindClass(env, "dev/mbui/Images"));
  m_request_frame = (*env)->GetStaticMethodID(env, host_cls, "requestFrame", "()V");
  m_wake_after = (*env)->GetStaticMethodID(env, host_cls, "wakeAfter", "(D)V");
  m_set_ime = (*env)->GetStaticMethodID(env, host_cls, "setIme", "(ZDDDDLjava/lang/String;II)V");
  m_clipboard = (*env)->GetStaticMethodID(env, host_cls, "clipboardSet", "(Ljava/lang/String;)V");
  m_log = (*env)->GetStaticMethodID(env, host_cls, "log", "(Ljava/lang/String;)V");
  m_bench = (*env)->GetStaticMethodID(env, host_cls, "benchMode", "()I");
  m_exit = (*env)->GetStaticMethodID(env, host_cls, "exit", "(I)V");
  m_back_enabled = (*env)->GetStaticMethodID(env, host_cls, "backEnabled", "(Z)V");
  m_metrics = (*env)->GetStaticMethodID(env, text_cls, "fontMetrics", "(DII[D)V");
  m_shape = (*env)->GetStaticMethodID(env, text_cls, "shape", "(Ljava/lang/String;DII[D)I");
  m_glyph = (*env)->GetStaticMethodID(env, text_cls, "glyph", "(I[D)V");
  m_generation = (*env)->GetStaticMethodID(env, text_cls, "atlasGeneration", "()I");
  m_img_load = (*env)->GetStaticMethodID(env, images_cls, "load", "(ILjava/lang/String;[BI)V");
  m_img_free = (*env)->GetStaticMethodID(env, images_cls, "free", "(I)V");
  m_img_reload = (*env)->GetStaticMethodID(env, images_cls, "reload", "()V");
  login_cls = (*env)->NewGlobalRef(env, (*env)->FindClass(env, "dev/mbui/BrowserLogin"));
  m_bl_start = (*env)->GetStaticMethodID(env, login_cls, "start", "(Ljava/lang/String;)I");
  m_bl_port = (*env)->GetStaticMethodID(env, login_cls, "port", "(I)I");
  m_bl_open = (*env)->GetStaticMethodID(env, login_cls, "open", "(ILjava/lang/String;)I");
  m_bl_back = (*env)->GetStaticMethodID(env, login_cls, "back", "(I)Ljava/lang/String;");
  m_bl_end = (*env)->GetStaticMethodID(env, login_cls, "end", "(I)V");
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
// Images: dev.mbui.Images decodes them on background threads and uploads
// them here, on the GL thread, which is the only one that touches this.

typedef struct {
  int state;  // 0 decoding, 1 ready, -1 failed or freed
  GLuint tex;
  int w, h, ow, oh;
} mb_image;

static mb_image *imgs;  // by id; ids are not reused
static int nimgs, img_cap;

static GLuint image_tex(int id) {
  return id > 0 && id < nimgs && imgs[id].state == 1 ? imgs[id].tex : 0;
}

// a new context has none of the old textures: forget them and decode again
static void images_lost(JNIEnv *env) {
  static int first = 1;
  if (first) {
    first = 0;
    return;
  }
  for (int i = 0; i < nimgs; i++) imgs[i].tex = 0;
  (*env)->CallStaticVoidMethod(env, images_cls, m_img_reload);
}

static int image_new(void) {
  if (nimgs == 0) nimgs = 1;  // 0 is no image
  if (nimgs >= img_cap) {
    img_cap = img_cap ? img_cap * 2 : 256;
    imgs = realloc(imgs, (size_t)img_cap * sizeof *imgs);
  }
  imgs[nimgs] = (mb_image){0};
  return nimgs++;
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
    "  float grow = kind == 2 ? a_p.w * 2.0 + 2.0 : ((kind == 0 || kind == 4) ? 1.0 : 0.0);\n"
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
    "uniform sampler2D u_img;\n"
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
    "  if (kind == 4) {\n"
    "    vec2 uv = v_c2.xy + clamp((p - v_rect.xy) / v_rect.zw, 0.0, 1.0) * v_c2.zw;\n"
    "    o = texture(u_img, uv) * (col.a * clamp(0.5 - d * u_scale, 0.0, 1.0));\n"
    "    return;\n"
    "  }\n"
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
static GLint u_vp, u_scale, u_atlas, u_img;
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
  u_img = glGetUniformLocation(prog, "u_img");
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
  images_lost(env);
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
  glUniform1i(u_img, 1);
  // one draw per run of instances showing the same image (slot 20; 0: none,
  // the atlas stands in); GLES has no base instance, so the attributes start
  // at the run instead
  int32_t start = 0;
  while (start < count) {
    int tid = (int)fbuf[start * 24 + 20];
    int32_t end = start + 1;
    while (end < count && (int)fbuf[end * 24 + 20] == tid) end++;
    GLuint t = tid ? image_tex(tid) : atlas;
    if (t) {  // 0: lost with the context, decoding again
      glActiveTexture(GL_TEXTURE1);
      glBindTexture(GL_TEXTURE_2D, t);
      for (int i = 0; i < 5; i++)
        glVertexAttribPointer(i, 4, GL_FLOAT, GL_FALSE, 96, (void *)(intptr_t)(start * 96 + i * 16));
      glDrawArraysInstanced(GL_TRIANGLES, 0, 6, end - start);
    }
    start = end;
  }
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
  if (mbc_frame) mbc_frame();
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

// The system's back (MainActivity: OnBackAnimationCallback, its predictive back gesture; on older systems
// onBackPressed): kind 0 started, 1 moved, 2 gone back, 3 called off; x in logical pixels, edge 0 left, 1 right.
JNIEXPORT void JNICALL Java_dev_mbui_Native_back(JNIEnv *env, jclass c, jint kind, jfloat x, jfloat progress,
                                                jint edge) {
  if (back_cb) back_cb(kind, x, progress, edge);
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

void mb_host_font_metrics(double size, int32_t weight, int32_t style, double *out) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, text_cls, m_metrics, size, weight, style, small_buf);
  (*env)->GetDoubleArrayRegion(env, small_buf, 0, 3, out);
}

int32_t mb_host_shape(moonbit_string_t text, double size, int32_t weight, int32_t style, double *out) {
  JNIEnv *env = env_();
  jstring s = jstr(env, text);
  jint n = (*env)->CallStaticIntMethod(env, text_cls, m_shape, s, size, weight, style, shape_buf);
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

void mb_host_set_back(mb_back_fn f) { back_cb = f; }

void mb_host_back_enabled(int32_t on) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, host_cls, m_back_enabled, (jboolean)(on != 0));
}

// MainActivity sets the intent's `env` extras as the process's environment before the app starts.
moonbit_string_t mb_host_env(moonbit_string_t name) {
  int n = Moonbit_array_length(name);
  char k[256];
  if (n >= (int)sizeof k) n = sizeof k - 1;
  for (int i = 0; i < n; i++) k[i] = name[i] < 128 ? (char)name[i] : '?';
  k[n] = 0;
  const unsigned char *v = (const unsigned char *)getenv(k);
  if (!v) return moonbit_make_string_raw(0);
  // UTF-8 to UTF-16
  size_t len = strlen((const char *)v);
  uint16_t *tmp = malloc((len + 1) * 2 * sizeof(uint16_t));
  int m = 0;
  for (size_t i = 0; i < len;) {
    uint32_t cp = v[i];
    int extra = cp >= 0xF0 ? 3 : cp >= 0xE0 ? 2 : cp >= 0xC0 ? 1 : 0;
    if (extra) cp &= (0x3F >> extra);
    i++;
    for (int j = 0; j < extra && i < len; j++, i++) cp = (cp << 6) | (v[i] & 0x3F);
    if (cp >= 0x10000) {
      cp -= 0x10000;
      tmp[m++] = (uint16_t)(0xD800 + (cp >> 10));
      tmp[m++] = (uint16_t)(0xDC00 + (cp & 0x3FF));
    } else {
      tmp[m++] = (uint16_t)cp;
    }
  }
  moonbit_string_t out = moonbit_make_string_raw(m);
  memcpy(out, tmp, (size_t)m * 2);
  free(tmp);
  return out;
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

// ---- images ----

int32_t mb_host_image_load(moonbit_string_t src, int32_t max_px) {
  JNIEnv *env = env_();
  int id = image_new();
  jstring s = jstr(env, src);
  (*env)->CallStaticVoidMethod(env, images_cls, m_img_load, id, s, NULL, max_px);
  (*env)->DeleteLocalRef(env, s);
  return id;
}

int32_t mb_host_image_load_bytes(moonbit_bytes_t data, int32_t max_px) {
  JNIEnv *env = env_();
  int id = image_new();
  jsize n = Moonbit_array_length(data);
  jbyteArray b = (*env)->NewByteArray(env, n);
  (*env)->SetByteArrayRegion(env, b, 0, n, (const jbyte *)data);
  jstring s = (*env)->NewStringUTF(env, "(bytes)");
  (*env)->CallStaticVoidMethod(env, images_cls, m_img_load, id, s, b, max_px);
  (*env)->DeleteLocalRef(env, s);
  (*env)->DeleteLocalRef(env, b);
  return id;
}

int32_t mb_host_image_info(int32_t id, double *out) {
  if (id <= 0 || id >= nimgs) return -1;
  mb_image *im = &imgs[id];
  if (im->state == 1) {
    out[0] = im->w; out[1] = im->h; out[2] = im->ow; out[3] = im->oh;
  }
  return im->state;
}

void mb_host_image_free(int32_t id) {
  if (id <= 0 || id >= nimgs) return;
  mb_image *im = &imgs[id];
  if (im->tex) glDeleteTextures(1, &im->tex);
  *im = (mb_image){-1};
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, images_cls, m_img_free, id);
}

JNIEXPORT void JNICALL Java_dev_mbui_Native_imageDone(JNIEnv *env, jclass c, jint id, jint tex,
                                                     jint w, jint h, jint ow, jint oh) {
  GLuint t = (GLuint)tex;
  if (id <= 0 || id >= nimgs || imgs[id].state == -1) {  // freed meanwhile
    if (t) glDeleteTextures(1, &t);
    return;
  }
  mb_image *im = &imgs[id];
  if (im->tex && im->tex != t) glDeleteTextures(1, &im->tex);
  *im = (mb_image){t ? 1 : -1, t, w, h, ow, oh};
}

// A sign-in in the browser that comes back here (host_native.mbt `browser_login`): dev.mbui.BrowserLogin, a loopback
// listener (dev.mbui.Loopback) and a Custom Tab, the app brought back in front once the browser has come back.
int32_t mb_host_browser_login_start(moonbit_string_t path) {
  JNIEnv *env = env_();
  jstring p = jstr(env, path);
  jint id = (*env)->CallStaticIntMethod(env, login_cls, m_bl_start, p);
  (*env)->DeleteLocalRef(env, p);
  return id;
}

int32_t mb_host_browser_login_port(int32_t id) {
  JNIEnv *env = env_();
  return (*env)->CallStaticIntMethod(env, login_cls, m_bl_port, id);
}

int32_t mb_host_browser_login_open(int32_t id, moonbit_string_t url) {
  JNIEnv *env = env_();
  jstring u = jstr(env, url);
  jint ok = (*env)->CallStaticIntMethod(env, login_cls, m_bl_open, id, u);
  (*env)->DeleteLocalRef(env, u);
  return ok;
}

moonbit_string_t mb_host_browser_login_back(int32_t id) {
  JNIEnv *env = env_();
  jstring s = (jstring)(*env)->CallStaticObjectMethod(env, login_cls, m_bl_back, id);
  moonbit_string_t out = s ? mstr(env, s) : moonbit_make_string_raw(0);
  if (s) (*env)->DeleteLocalRef(env, s);
  return out;
}

void mb_host_browser_login_end(int32_t id) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, login_cls, m_bl_end, id);
}
