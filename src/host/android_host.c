// Android host: the C side of android/ (dev.mbui.*). Java owns the
// Activity, the GLSurfaceView, input and the input method; this file owns the
// GLES3 renderer and forwards between Java and the MoonBit callbacks. All
// MoonBit code runs on the GL thread. Built by scripts/android.sh.
#include <jni.h>
#include <GLES3/gl3.h>
#include <android/log.h>
#include <math.h>
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
static jclass host_cls, text_cls, images_cls, login_cls, picks_cls, views_cls, pdfs_cls;
static jmethodID m_request_frame, m_wake_after, m_set_ime, m_clipboard, m_log, m_bench,
    m_exit, m_metrics, m_shape, m_glyph, m_generation, m_img_load, m_img_free, m_img_reload, m_bl_start, m_bl_port,
    m_bl_open, m_bl_back, m_bl_end, m_back_enabled, m_pk_start, m_pk_state, m_pk_count, m_pk_name, m_pk_bytes,
    m_pk_end, m_drive, m_ref_begin, m_ref_text, m_ref_end, m_ref_frame, m_text_key, m_v_open, m_v_place, m_v_close,
    m_v_control, m_v_info, m_v_read_next, m_v_read_answer, m_pdf_open, m_pdf_pages, m_pdf_size, m_pdf_load, m_pdf_close,
    m_save, m_system_dark, m_set_dark;
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
  m_drive = (*env)->GetStaticMethodID(env, host_cls, "drive", "(ILjava/lang/String;)I");
  m_system_dark = (*env)->GetStaticMethodID(env, host_cls, "systemDark", "()Z");
  m_set_dark = (*env)->GetStaticMethodID(env, host_cls, "setDark", "(Z)V");
  m_metrics = (*env)->GetStaticMethodID(env, text_cls, "fontMetrics", "(DII[D)V");
  m_shape = (*env)->GetStaticMethodID(env, text_cls, "shape", "(Ljava/lang/String;DII[D)I");
  m_glyph = (*env)->GetStaticMethodID(env, text_cls, "glyph", "(I[D)V");
  m_generation = (*env)->GetStaticMethodID(env, text_cls, "atlasGeneration", "()I");
  m_text_key = (*env)->GetStaticMethodID(env, text_cls, "textKey", "(Ljava/lang/String;DII)I");
  m_ref_begin = (*env)->GetStaticMethodID(env, text_cls, "refBegin", "(DDDI)V");
  m_ref_text = (*env)->GetStaticMethodID(env, text_cls, "refText", "(Ljava/lang/String;DIIDDI[D)V");
  m_ref_end = (*env)->GetStaticMethodID(env, text_cls, "refEnd", "(Ljava/lang/String;)Z");
  m_ref_frame = (*env)->GetStaticMethodID(env, text_cls, "refFrame", "(Ljava/lang/String;)Z");
  m_img_load = (*env)->GetStaticMethodID(env, images_cls, "load", "(ILjava/lang/String;[BI)V");
  m_img_free = (*env)->GetStaticMethodID(env, images_cls, "free", "(I)V");
  m_img_reload = (*env)->GetStaticMethodID(env, images_cls, "reload", "()V");
  login_cls = (*env)->NewGlobalRef(env, (*env)->FindClass(env, "dev/mbui/BrowserLogin"));
  m_bl_start = (*env)->GetStaticMethodID(env, login_cls, "start", "(Ljava/lang/String;)I");
  m_bl_port = (*env)->GetStaticMethodID(env, login_cls, "port", "(I)I");
  m_bl_open = (*env)->GetStaticMethodID(env, login_cls, "open", "(ILjava/lang/String;)I");
  m_bl_back = (*env)->GetStaticMethodID(env, login_cls, "back", "(I)Ljava/lang/String;");
  m_bl_end = (*env)->GetStaticMethodID(env, login_cls, "end", "(I)V");
  picks_cls = (*env)->NewGlobalRef(env, (*env)->FindClass(env, "dev/mbui/Picks"));
  m_pk_start = (*env)->GetStaticMethodID(env, picks_cls, "start", "(I)I");
  m_pk_state = (*env)->GetStaticMethodID(env, picks_cls, "state", "(I)I");
  m_pk_count = (*env)->GetStaticMethodID(env, picks_cls, "count", "(I)I");
  m_pk_name = (*env)->GetStaticMethodID(env, picks_cls, "name", "(II)Ljava/lang/String;");
  m_pk_bytes = (*env)->GetStaticMethodID(env, picks_cls, "bytes", "(II)[B");
  m_pk_end = (*env)->GetStaticMethodID(env, picks_cls, "end", "(I)V");
  views_cls = (*env)->NewGlobalRef(env, (*env)->FindClass(env, "dev/mbui/NativeViews"));
  m_v_open = (*env)->GetStaticMethodID(env, views_cls, "open", "(ILjava/lang/String;)I");
  m_v_place = (*env)->GetStaticMethodID(env, views_cls, "place", "(IFFFFFFFFZ)V");
  m_v_close = (*env)->GetStaticMethodID(env, views_cls, "close", "(I)V");
  m_v_control = (*env)->GetStaticMethodID(env, views_cls, "control", "(IID)V");
  m_v_info = (*env)->GetStaticMethodID(env, views_cls, "info", "(I[D)I");
  m_v_read_next = (*env)->GetStaticMethodID(env, views_cls, "readNext", "(I[D)I");
  m_v_read_answer = (*env)->GetStaticMethodID(env, views_cls, "readAnswer", "(II[BD)V");
  m_save = (*env)->GetStaticMethodID(env, views_cls, "save", "(Ljava/lang/String;[B)Z");
  pdfs_cls = (*env)->NewGlobalRef(env, (*env)->FindClass(env, "dev/mbui/Pdfs"));
  m_pdf_open = (*env)->GetStaticMethodID(env, pdfs_cls, "open", "([B)I");
  m_pdf_pages = (*env)->GetStaticMethodID(env, pdfs_cls, "pages", "(I)I");
  m_pdf_size = (*env)->GetStaticMethodID(env, pdfs_cls, "pageSize", "(II[D)V");
  m_pdf_load = (*env)->GetStaticMethodID(env, pdfs_cls, "pageLoad", "(IIII)V");
  m_pdf_close = (*env)->GetStaticMethodID(env, pdfs_cls, "close", "(I)V");
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
    "layout(location=5) in vec4 a_pad;\n"
    "uniform vec2 u_vp;\n"
    "uniform vec4 u_gb;\n"
    "out vec2 v_pos;\n"
    "flat out vec4 v_rect; flat out vec4 v_p; flat out vec4 v_color; flat out vec4 v_c2; flat out vec4 v_clip; flat out vec4 v_pad;\n"
    "void main() {\n"
    "  int vid = gl_VertexID;\n"
    "  vec2 corner = vec2((vid == 1 || vid == 4 || vid == 5) ? 1.0 : 0.0, (vid == 2 || vid == 3 || vid == 5) ? 1.0 : 0.0);\n"
    "  int kind = int(a_p.y + 0.5);\n"
    "  float grow = kind == 2 ? a_p.w * 2.0 + 2.0 : ((kind == 0 || kind == 4 || kind == 5) ? 1.0 : 0.0);\n"
    "  vec2 pos = a_rect.xy - grow + corner * (a_rect.zw + 2.0 * grow);\n"
    "  if (kind == 6) pos = mix(u_gb.xy, u_gb.zw, corner);\n"
    "  gl_Position = vec4(pos.x / u_vp.x * 2.0 - 1.0, 1.0 - pos.y / u_vp.y * 2.0, 0.0, 1.0);\n"
    "  v_pos = pos; v_rect = a_rect; v_p = a_p; v_color = a_color; v_c2 = a_c2; v_clip = a_clip; v_pad = a_pad;\n"
    "}\n";

static const char *FS =
    "#version 300 es\n"
    "precision highp float;\n"
    "in vec2 v_pos;\n"
    "flat in vec4 v_rect; flat in vec4 v_p; flat in vec4 v_color; flat in vec4 v_c2; flat in vec4 v_clip; flat in vec4 v_pad;\n"
    "uniform float u_scale;\n"
    "uniform sampler2D u_atlas;\n"
    "uniform sampler2D u_img;\n"
    "// glass (src/ui/glass.mbt): the blurred copy under it and where a point is in it (uv = p * u_map.xy + u_map.zw, kept\n"
    "// in u_uvc), a liquid group's shapes and corners, how many\n"
    "uniform sampler2D u_bd;\n"
    "uniform vec4 u_map;\n"
    "uniform vec4 u_uvc;\n"
    "uniform vec4 u_shape[8];\n"
    "uniform vec4 u_rad[2];\n"
    "uniform int u_n;\n"
    "out vec4 o;\n"
    "float sd_rr(vec2 p, vec4 r, float rad) {\n"
    "  vec2 hs = r.zw * 0.5;\n"
    "  float rr = min(rad, min(hs.x, hs.y));\n"
    "  vec2 q = abs(p - r.xy - hs) - hs + rr;\n"
    "  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rr;\n"
    "}\n"
    "float smin_k(float a, float b, float k) {\n"
    "  if (k <= 0.0) return min(a, b);\n"
    "  float h = max(k - abs(a - b), 0.0) / k;\n"
    "  return min(a, b) - h * h * k * 0.25;\n"
    "}\n"
    "float sd_group(vec2 p, float k) {\n"
    "  float d = 1e9;\n"
    "  for (int i = 0; i < 8; i++) {\n"
    "    if (i >= u_n) break;\n"
    "    d = smin_k(d, sd_rr(p, u_shape[i], u_rad[i / 4][i % 4]), k);\n"
    "  }\n"
    "  return d;\n"
    "}\n"
    "vec3 backdrop(vec2 p) {\n"
    "  return texture(u_bd, clamp(p * u_map.xy + u_map.zw, u_uvc.xy, u_uvc.zw)).rgb;\n"
    "}\n"
    "float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }\n"
    "void main() {\n"
    "  vec2 p = v_pos;\n"
    "  if (p.x < v_clip.x || p.y < v_clip.y || p.x > v_clip.z || p.y > v_clip.w) discard;\n"
    "  int kind = int(v_p.y + 0.5);\n"
    "  if (kind == 9) { o = vec4(0.0); return; }\n"
    "  vec4 col = v_color;\n"
    "  if (kind == 1 || kind == 3 || kind == 7) {\n"
    "    vec2 uv = (v_c2.xy + (p - v_rect.xy) / v_rect.zw * v_c2.zw) / 2048.0;\n"
    "    vec4 t = texture(u_atlas, uv);\n"
    "    if (kind == 7) {\n"
    "      // inked by how light what is under its glass is, looked at round the glass's middle\n"
    "      vec2 c = v_pad.yz; float r = v_pad.w * 0.5;\n"
    "      float l = (luma(backdrop(c)) + luma(backdrop(c + vec2(r, 0.0))) + luma(backdrop(c - vec2(r, 0.0))) +\n"
    "                 luma(backdrop(c + vec2(0.0, r))) + luma(backdrop(c - vec2(0.0, r)))) / 5.0;\n"
    "      vec3 ink = mix(vec3(1.0), vec3(0.11, 0.11, 0.12), smoothstep(0.42, 0.6, l));\n"
    "      o = vec4(ink, 1.0) * (t.a * col.a);\n"
    "      return;\n"
    "    }\n"
    "    o = kind == 1 ? vec4(col.rgb, 1.0) * (t.a * col.a) : t * col.a;\n"
    "    return;\n"
    "  }\n"
    "  if (kind == 6) {\n"
    "    // liquid: one shape of the group's, merged; what is under it bent along the bezel, the colours split a little\n"
    "    float k = v_pad.w;\n"
    "    float d = sd_group(p, k);\n"
    "    float a = clamp(0.5 - d * u_scale, 0.0, 1.0);\n"
    "    if (a <= 0.0) discard;\n"
    "    float e = 0.5;\n"
    "    vec2 grad = vec2(sd_group(p + vec2(e, 0.0), k) - sd_group(p - vec2(e, 0.0), k),\n"
    "                     sd_group(p + vec2(0.0, e), k) - sd_group(p - vec2(0.0, e), k));\n"
    "    vec2 n = grad / max(length(grad), 1e-4);\n"
    "    float bezel = max(v_c2.y, 1.0);\n"
    "    float edge = 1.0 - clamp(-d / bezel, 0.0, 1.0);\n"
    "    float disp = v_pad.y * (1.0 - sqrt(max(1.0 - edge * edge, 0.0)));\n"
    "    vec2 off = -n * disp;\n"
    "    float ch = v_pad.z;\n"
    "    vec3 c = vec3(backdrop(p + off * (1.0 + ch)).r, backdrop(p + off).g, backdrop(p + off * (1.0 - ch)).b);\n"
    "    c = max(mix(vec3(luma(c)), c, v_p.z), 0.0);\n"
    "    c = c * (1.0 - col.a) + col.rgb * col.a;\n"
    "    // the rim lit from the top left, and less across from it\n"
    "    float ndl = dot(n, vec2(-0.6, -0.8));\n"
    "    float band = clamp(1.0 + d / 2.5, 0.0, 1.0);\n"
    "    float spec = v_c2.x * (band * (0.9 * pow(max(ndl, 0.0), 1.5) + 0.45 * pow(max(-ndl, 0.0), 1.5)) +\n"
    "                           0.3 * edge * edge * max(ndl, 0.0));\n"
    "    // the edge shaded, more on the side away from the light, so the shape reads over a light ground too\n"
    "    c *= 1.0 - v_c2.x * band * (0.1 + 0.25 * max(-ndl, 0.0));\n"
    "    c = c + (1.0 - c) * clamp(spec, 0.0, 1.0);\n"
    "    o = vec4(c, 1.0) * (a * v_c2.w);\n"
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
    "    // glass's: only outside its box (c2.y above it)\n"
    "    if (v_c2.x > 0.5) {\n"
    "      vec2 qb = abs(p - c + vec2(0.0, v_c2.y)) - hs + r;\n"
    "      float db = length(max(qb, 0.0)) + min(max(qb.x, qb.y), 0.0) - r;\n"
    "      a *= clamp(0.5 + db * u_scale, 0.0, 1.0);\n"
    "    }\n"
    "    o = vec4(col.rgb, 1.0) * col.a * a;\n"
    "    return;\n"
    "  }\n"
    "  float a = clamp(0.5 - d * u_scale, 0.0, 1.0);\n"
    "  if (kind == 5) {\n"
    "    // frosted: the blurred copy, saturated, the tint over it; the rim (a hairline inside the edge, the top left lit,\n"
    "    // the foot and right less), 0.5 wide\n"
    "    vec3 g3 = backdrop(p);\n"
    "    g3 = max(mix(vec3(luma(g3)), g3, v_p.z), 0.0);\n"
    "    g3 = g3 * (1.0 - col.a) + col.rgb * col.a;\n"
    "    if (v_c2.x + v_c2.y + v_c2.z > 0.0) {\n"
    "      float edge = clamp(0.5 + (d + 0.5) * u_scale, 0.0, 1.0);\n"
    "      float lit = clamp(0.5 + sd_rr(p - 0.5, v_rect, v_p.x) * u_scale, 0.0, 1.0);\n"
    "      float back = clamp(0.5 + sd_rr(p + 0.5, v_rect, v_p.x) * u_scale, 0.0, 1.0);\n"
    "      g3 = mix(g3, vec3(1.0), v_c2.x * edge);\n"
    "      g3 = mix(g3, vec3(1.0), v_c2.y * lit);\n"
    "      g3 = mix(g3, vec3(1.0), v_c2.z * back);\n"
    "    }\n"
    "    o = vec4(g3, 1.0) * (a * v_c2.w);\n"
    "    return;\n"
    "  }\n"
    "  vec4 fill = vec4(col.rgb, 1.0) * col.a;\n"
    "  if (v_p.z > 0.0) {\n"
    "    float inner = clamp(0.5 - (d + v_p.z) * u_scale, 0.0, 1.0);\n"
    "    vec4 bc = vec4(v_c2.rgb, 1.0) * v_c2.a;\n"
    "    fill = mix(bc, fill, inner);\n"
    "  }\n"
    "  o = fill * a;\n"
    "}\n";

// glass's passes over its copy of what is under it
static const char *PVS =
    "#version 300 es\n"
    "void main() {\n"
    "  gl_Position = vec4(gl_VertexID == 1 ? 3.0 : -1.0, gl_VertexID == 2 ? 3.0 : -1.0, 0.0, 1.0);\n"
    "}\n";

static const char *PFS =
    "#version 300 es\n"
    "precision highp float;\n"
    "// The backdrop's passes: u_a.xy the source's texel, u_a.z 1 halving (dual Kawase's down), 2 a Gaussian along u_b.zw\n"
    "// of deviation u_a.w (texels); u_b.xy the last texel's centre of what the source holds\n"
    "uniform sampler2D u_src;\n"
    "uniform vec4 u_a;\n"
    "uniform vec4 u_b;\n"
    "out vec4 o;\n"
    "void main() {\n"
    "  vec2 ts = u_a.xy;\n"
    "  vec2 lo = ts * 0.5, hi = u_b.xy;\n"
    "  if (u_a.z < 1.5) {\n"
    "    vec2 uv = gl_FragCoord.xy * 2.0 * ts;\n"
    "    vec4 s = texture(u_src, clamp(uv, lo, hi)) * 4.0;\n"
    "    s += texture(u_src, clamp(uv - ts, lo, hi));\n"
    "    s += texture(u_src, clamp(uv + ts, lo, hi));\n"
    "    s += texture(u_src, clamp(uv + vec2(ts.x, -ts.y), lo, hi));\n"
    "    s += texture(u_src, clamp(uv + vec2(-ts.x, ts.y), lo, hi));\n"
    "    o = s / 8.0;\n"
    "    return;\n"
    "  }\n"
    "  vec2 uv = gl_FragCoord.xy * ts;\n"
    "  vec2 dir = u_b.zw * ts;\n"
    "  float sg = u_a.w;\n"
    "  float k = -0.5 / (sg * sg);\n"
    "  vec4 s = texture(u_src, clamp(uv, lo, hi));\n"
    "  float wsum = 1.0;\n"
    "  int n = int(ceil(sg * 3.0));\n"
    "  for (int i = 1; i <= 64; i += 2) {\n"
    "    if (i > n) break;\n"
    "    float w1 = exp(float(i * i) * k), w2 = exp(float((i + 1) * (i + 1)) * k);\n"
    "    float w = w1 + w2;\n"
    "    float off = (float(i) * w1 + float(i + 1) * w2) / w;\n"
    "    s += (texture(u_src, clamp(uv + dir * off, lo, hi)) + texture(u_src, clamp(uv - dir * off, lo, hi))) * w;\n"
    "    wsum += 2.0 * w;\n"
    "  }\n"
    "  o = s / wsum;\n"
    "}\n";

static GLuint prog, vao, vbo, atlas, post;
static GLint u_vp, u_scale, u_atlas, u_img, u_bd, u_map, u_uvc, u_gb, u_shape, u_rad, u_n, pu_src, pu_a, pu_b;
static float *fbuf;
static size_t fcap;
static int fb_w, fb_h;
static double cur_w, cur_h, cur_scale;

static void glass_lost(void);

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
  u_bd = glGetUniformLocation(prog, "u_bd");
  u_map = glGetUniformLocation(prog, "u_map");
  u_uvc = glGetUniformLocation(prog, "u_uvc");
  u_gb = glGetUniformLocation(prog, "u_gb");
  u_shape = glGetUniformLocation(prog, "u_shape");
  u_rad = glGetUniformLocation(prog, "u_rad");
  u_n = glGetUniformLocation(prog, "u_n");
  post = glCreateProgram();
  glAttachShader(post, compile(GL_VERTEX_SHADER, PVS));
  glAttachShader(post, compile(GL_FRAGMENT_SHADER, PFS));
  glLinkProgram(post);
  pu_src = glGetUniformLocation(post, "u_src");
  pu_a = glGetUniformLocation(post, "u_a");
  pu_b = glGetUniformLocation(post, "u_b");
  glass_lost();
  glGenVertexArrays(1, &vao);
  glBindVertexArray(vao);
  glGenBuffers(1, &vbo);
  glBindBuffer(GL_ARRAY_BUFFER, vbo);
  for (int i = 0; i < 6; i++) {
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

// ---------------------------------------------------------------------------
// Glass (src/ui/glass.mbt): when the instances reach a run of glass (slot 20 negative: the capture it shares), what
// is drawn so far under it (its rects with room for the blur round them) is copied out of the surface, halved down
// to where the blur is a few texels wide (dual Kawase's downsample, at most 1/8), blurred there by a Gaussian of what
// deviation is left, and drawn through. Level j is 1/2^j of the surface, [4] a Gaussian's first half.

typedef struct { GLuint t, fb; int w, h; } level;
static level lv[5];
static int lv_w, lv_h;
static GLuint bd_tex;
static float gmap[4], guvc[4], ggb[4], gshape[32], grad[8];
static int gn;
// the app's part of the surface (MBView: the soft keyboard over the rest), in its pixels from the foot
static int vy0, vhp;

// a new context has none of the old textures
static void glass_lost(void) {
  memset(lv, 0, sizeof lv);
  lv_w = lv_h = 0;
}

static level level_tex(int w, int h) {
  level l = {0, 0, w > 0 ? w : 1, h > 0 ? h : 1};
  glGenTextures(1, &l.t);
  glBindTexture(GL_TEXTURE_2D, l.t);
  glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA8, l.w, l.h);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glGenFramebuffers(1, &l.fb);
  glBindFramebuffer(GL_FRAMEBUFFER, l.fb);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, l.t, 0);
  return l;
}

static void ensure_levels(int w, int h) {
  if (lv[0].t && lv_w >= w && lv_h >= h) return;
  for (int j = 0; j < 5; j++)
    if (lv[j].t) {
      glDeleteTextures(1, &lv[j].t);
      glDeleteFramebuffers(1, &lv[j].fb);
    }
  lv_w = w > lv_w ? w : lv_w;
  lv_h = h > lv_h ? h : lv_h;
  for (int j = 0; j < 4; j++) lv[j] = level_tex((lv_w + (1 << j) - 1) >> j, (lv_h + (1 << j) - 1) >> j);
  lv[4] = level_tex(lv_w, lv_h);
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

static void post_pass(level *src, int sw, int sh, level *dst, int w, int h, int mode, float sg, float dx, float dy) {
  glBindFramebuffer(GL_FRAMEBUFFER, dst->fb);
  glViewport(0, 0, w, h);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, src->t);
  glUniform1i(pu_src, 0);
  glUniform4f(pu_a, 1.0f / src->w, 1.0f / src->h, (float)mode, sg);
  glUniform4f(pu_b, (sw - 0.5f) / src->w, (sh - 0.5f) / src->h, dx, dy);
  glDrawArrays(GL_TRIANGLES, 0, 3);
}

// what the run [start, end) of glass sees; 0 when none of it shows
static int capture(const float *f, int32_t start, int32_t end) {
  const float *a = f + start * 24;
  float blur = a[7];
  int kind = (int)(a[5] + 0.5f);
  float margin = 3.0f * blur + a[21] * (1.0f + a[22]) + a[23] + 2.0f;
  float x0 = 1e9f, y0 = 1e9f, x1 = -1e9f, y1 = -1e9f;
  gn = 0;
  for (int32_t i = start; i < end; i++) {
    const float *b = f + i * 24;
    float bx0 = b[0] > b[16] ? b[0] : b[16], by0 = b[1] > b[17] ? b[1] : b[17];
    float bx1 = b[0] + b[2] < b[18] ? b[0] + b[2] : b[18], by1 = b[1] + b[3] < b[19] ? b[1] + b[3] : b[19];
    if (kind == 6) {
      bx0 = b[0] - a[23]; by0 = b[1] - a[23]; bx1 = b[0] + b[2] + a[23]; by1 = b[1] + b[3] + a[23];
      if (gn < 8) {
        for (int k = 0; k < 4; k++) gshape[gn * 4 + k] = b[k];
        grad[gn] = b[4];
        gn++;
      }
    }
    if (bx0 < x0) x0 = bx0;
    if (by0 < y0) y0 = by0;
    if (bx1 > x1) x1 = bx1;
    if (by1 > y1) y1 = by1;
  }
  ggb[0] = x0 - 2; ggb[1] = y0 - 2; ggb[2] = x1 + 2; ggb[3] = y1 + 2;
  float sc = (float)cur_scale;
  // in the surface's pixels, from its foot (GL's way up)
  int top = vy0 + vhp;
  int px0 = (int)floorf((x0 - margin) * sc), px1 = (int)ceilf((x1 + margin) * sc);
  int pb0 = top - (int)ceilf((y1 + margin) * sc), pb1 = top - (int)floorf((y0 - margin) * sc);
  if (px0 < 0) px0 = 0;
  if (px1 > fb_w) px1 = fb_w;
  if (pb0 < vy0) pb0 = vy0;
  if (pb1 > top) pb1 = top;
  if (px1 <= px0 || pb1 <= pb0 || x1 <= x0 || y1 <= y0) return 0;
  int w = px1 - px0, h = pb1 - pb0;
  ensure_levels(fb_w, fb_h);
  glDisable(GL_BLEND);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, lv[0].fb);
  glBlitFramebuffer(px0, pb0, px1, pb1, 0, 0, w, h, GL_COLOR_BUFFER_BIT, GL_NEAREST);
  glUseProgram(post);
  float sp = blur * sc;
  int k = 0;
  while (k < 3 && sp / (float)(1 << (k + 1)) >= 2.0f) k++;
  int lw[4] = {w}, lh[4] = {h};
  for (int j = 1; j <= k; j++) {
    lw[j] = (lw[j - 1] + 1) / 2;
    lh[j] = (lh[j - 1] + 1) / 2;
    post_pass(&lv[j - 1], lw[j - 1], lh[j - 1], &lv[j], lw[j], lh[j], 1, 0, 0, 0);
  }
  // what is left of the deviation once the halvings' and the last look's (bilinear) spread are taken out
  float sk = sp / (float)(1 << k);
  float pre = k > 0 ? 0.75f * (1.0f - powf(0.25f, (float)k)) / 3.0f + 1.0f / 6.0f : 0.0f;
  float sg = sqrtf(sk * sk - pre > 0 ? sk * sk - pre : 0);
  if (sg > 0.3f) {
    post_pass(&lv[k], lw[k], lh[k], &lv[4], lw[k], lh[k], 2, sg, 1, 0);
    post_pass(&lv[4], lw[k], lh[k], &lv[k], lw[k], lh[k], 2, sg, 0, 1);
  }
  level *L = &lv[k];
  float d = (float)(1 << k);
  bd_tex = L->t;
  gmap[0] = sc / d / L->w; gmap[1] = -sc / d / L->h;
  gmap[2] = -(float)px0 / d / L->w; gmap[3] = (float)(top - pb0) / d / L->h;
  guvc[0] = 0.5f / L->w; guvc[1] = 0.5f / L->h; guvc[2] = (lw[k] - 0.5f) / L->w; guvc[3] = (lh[k] - 0.5f) / L->h;
  return 1;
}

// the main program's state (after the passes)
static void main_state(void) {
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glViewport(0, vy0, fb_w, vhp);
  glEnable(GL_BLEND);
  glUseProgram(prog);
  glBindVertexArray(vao);
  glBindBuffer(GL_ARRAY_BUFFER, vbo);
  glUniform2f(u_vp, (float)cur_w, (float)cur_h);
  glUniform1f(u_scale, (float)cur_scale);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, atlas);
  glUniform1i(u_atlas, 0);
  glUniform1i(u_img, 1);
  glActiveTexture(GL_TEXTURE2);
  glBindTexture(GL_TEXTURE_2D, bd_tex ? bd_tex : atlas);
  glUniform1i(u_bd, 2);
  glUniform4fv(u_map, 1, gmap);
  glUniform4fv(u_uvc, 1, guvc);
  glUniform4fv(u_gb, 1, ggb);
  glUniform4fv(u_shape, 8, gshape);
  glUniform4fv(u_rad, 2, grad);
  glUniform1i(u_n, gn);
}

void mb_host_present(double *buf, int32_t count, double r, double g, double b) {
  glViewport(0, 0, fb_w, fb_h);
  glClearColor((float)r, (float)g, (float)b, 1);
  glClear(GL_COLOR_BUFFER_BIT);
  // the app drawn in the surface's top part, as tall as it was told (the soft keyboard over the rest: MBView)
  int vh = (int)(cur_h * cur_scale + 0.5);
  vy0 = 0;
  vhp = fb_h;
  if (vh > 0 && vh < fb_h) {
    vy0 = fb_h - vh;
    vhp = vh;
  }
  glViewport(0, vy0, fb_w, vhp);
  if (count <= 0) return;
  size_t n = (size_t)count * 24;
  if (fcap < n) {
    fcap = n * 2;
    fbuf = realloc(fbuf, fcap * sizeof(float));
  }
  for (size_t i = 0; i < n; i++) fbuf[i] = (float)buf[i];
  bd_tex = 0;
  memset(gmap, 0, sizeof gmap);
  memset(guvc, 0, sizeof guvc);
  memset(ggb, 0, sizeof ggb);
  gn = 0;
  glUseProgram(prog);
  glBindVertexArray(vao);
  glBindBuffer(GL_ARRAY_BUFFER, vbo);
  glBufferData(GL_ARRAY_BUFFER, n * sizeof(float), fbuf, GL_STREAM_DRAW);
  main_state();
  // one draw per run of instances showing the same image (slot 20; 0: none, the atlas stands in), or sharing one
  // capture of glass (negative); GLES has no base instance, so the attributes start at the run instead
  // (and per run of holes, kind 9: where a native view shows, written transparent with no blending, NativeViews.java)
  int32_t start = 0;
  int bound = 0, shows = 0;
  while (start < count) {
    int tid = (int)fbuf[start * 24 + 20];
    int hole = (int)(fbuf[start * 24 + 5] + 0.5f) == 9;
    int32_t end = start + 1;
    while (end < count && (int)fbuf[end * 24 + 20] == tid && ((int)(fbuf[end * 24 + 5] + 0.5f) == 9) == hole) end++;
    if (tid < 0) {
      if (tid != bound) {
        shows = capture(fbuf, start, end);
        bound = tid;
        main_state();
      }
      if (shows) {
        for (int i = 0; i < 6; i++)
          glVertexAttribPointer(i, 4, GL_FLOAT, GL_FALSE, 96, (void *)(intptr_t)(start * 96 + i * 16));
        // liquid: the group as one shape, drawn once
        glDrawArraysInstanced(GL_TRIANGLES, 0, 6, (int)(fbuf[start * 24 + 5] + 0.5f) == 6 ? 1 : end - start);
      }
      start = end;
      continue;
    }
    GLuint t = tid ? image_tex(tid) : atlas;
    if (t) {  // 0: lost with the context, decoding again
      glActiveTexture(GL_TEXTURE1);
      glBindTexture(GL_TEXTURE_2D, t);
      for (int i = 0; i < 6; i++)
        glVertexAttribPointer(i, 4, GL_FLOAT, GL_FALSE, 96, (void *)(intptr_t)(start * 96 + i * 16));
      if (hole) glDisable(GL_BLEND);
      glDrawArraysInstanced(GL_TRIANGLES, 0, 6, end - start);
      if (hole) glEnable(GL_BLEND);
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

// A touch at its own time (MotionEvent.getEventTime, or a historical sample's: uptime ms, CLOCK_MONOTONIC as
// mb_host_now), which MoonBit asks for while handling it (mb_host_event_time).
static double event_time = -1;

JNIEXPORT void JNICALL Java_dev_mbui_Native_pointer(JNIEnv *env, jclass c, jint kind, jfloat x,
                                                   jfloat y, jdouble t) {
  event_time = t;
  if (cb.pointer) cb.pointer(kind, x, y, 0);
  event_time = -1;
}

double mb_host_event_time(void) { return event_time; }

int32_t mb_host_platform(void) { return 2; }

JNIEXPORT void JNICALL Java_dev_mbui_Native_key(JNIEnv *env, jclass c, jint code, jint mods) {
  if (cb.key) cb.key(code, mods);
}

JNIEXPORT void JNICALL Java_dev_mbui_Native_text(JNIEnv *env, jclass c, jint kind, jstring s,
                                                jint a, jint b) {
  if (cb.text) cb.text(kind, mstr(env, s), a, b);
}

// The system's back (MainActivity: OnBackAnimationCallback, its predictive back gesture; on older systems
// onBackPressed): kind 0 started, 1 moved, 2 gone back, 3 called off; x in logical pixels, edge 0 left, 1 right.
// The app in front or not (@host.set_app_state), as MainActivity tells it (Host.appState), on the GL thread.
static void (*state_cb)(int32_t);
void mb_host_set_app_state(void (*f)(int32_t)) { state_cb = f; }
JNIEXPORT void JNICALL Java_dev_mbui_Native_appState(JNIEnv *env, jclass c, jint state) {
  if (state_cb) state_cb(state);
}

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

// Whether the system is in night mode (@host.system_dark), as MainActivity keeps it (Host.systemDark: the
// configuration's uiMode, a frame asked for when it changes).
int32_t mb_host_system_dark(void) {
  JNIEnv *env = env_();
  return (*env)->CallStaticBooleanMethod(env, host_cls, m_system_dark) ? 1 : 0;
}

// The app drawn dark or light (@host.set_dark): the status and navigation bars' icons light on it or dark (Host.setDark).
void mb_host_set_dark(int32_t dark) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, host_cls, m_set_dark, (jboolean)(dark != 0));
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

int32_t mb_host_text_key(moonbit_string_t text, double size, int32_t weight, int32_t style) {
  JNIEnv *env = env_();
  jstring s = jstr(env, text);
  jint k = (*env)->CallStaticIntMethod(env, text_cls, m_text_key, s, size, weight, style);
  (*env)->DeleteLocalRef(env, s);
  return k;
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

// The platform's own text drawing beside mbui's (textref_native.mbt, src/textdiff): MBText's StaticLayout into a
// bitmap, and the window's picture read back after the next frame.
void mb_host_ref_begin(double w, double h, double scale, int32_t bg) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, text_cls, m_ref_begin, w, h, scale, bg);
}

void mb_host_ref_text(moonbit_string_t text, double size, int32_t weight, int32_t style, double x, double base,
                      int32_t color, double *out) {
  JNIEnv *env = env_();
  jstring s = jstr(env, text);
  (*env)->CallStaticVoidMethod(env, text_cls, m_ref_text, s, size, weight, style, x, base, color, small_buf);
  (*env)->DeleteLocalRef(env, s);
  (*env)->GetDoubleArrayRegion(env, small_buf, 0, 5, out);
}

int32_t mb_host_ref_end(moonbit_string_t name) {
  JNIEnv *env = env_();
  jstring s = jstr(env, name);
  jboolean ok = (*env)->CallStaticBooleanMethod(env, text_cls, m_ref_end, s);
  (*env)->DeleteLocalRef(env, s);
  return ok;
}

int32_t mb_host_ref_frame(moonbit_string_t name) {
  JNIEnv *env = env_();
  jstring s = jstr(env, name);
  jboolean ok = (*env)->CallStaticBooleanMethod(env, text_cls, m_ref_frame, s);
  (*env)->DeleteLocalRef(env, s);
  return ok;
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

// A scripted run's input (src/ui/drive.mbt), as the system sends it (Host.drive: the view's InputConnection, a
// KEYCODE_PASTE); 0 for what it has no path for (the window's picture: adb's screencap takes it).
int32_t mb_host_drive(int32_t kind, moonbit_string_t text) {
  JNIEnv *env = env_();
  jstring s = jstr(env, text);
  jint r = (*env)->CallStaticIntMethod(env, host_cls, m_drive, (jint)kind, s);
  (*env)->DeleteLocalRef(env, s);
  return r;
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

// Android has no setting asking for less transparency (MBUI_GLASS=solid stands in for it); the GPU's time is not
// measured here.
int32_t mb_host_reduce_transparency(void) { return 0; }

double mb_host_gpu_ms(void) { return -1; }

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

// ---------------------------------------------------------------------------
// Files picked (pick.mbt): dev.mbui.Picks opens the system's pickers and reads what comes back.

int32_t mb_host_pick_start(int32_t kind) {
  JNIEnv *env = env_();
  return (*env)->CallStaticIntMethod(env, picks_cls, m_pk_start, kind);
}

int32_t mb_host_pick_state(int32_t id) {
  JNIEnv *env = env_();
  return (*env)->CallStaticIntMethod(env, picks_cls, m_pk_state, id);
}

int32_t mb_host_pick_count(int32_t id) {
  JNIEnv *env = env_();
  return (*env)->CallStaticIntMethod(env, picks_cls, m_pk_count, id);
}

moonbit_string_t mb_host_pick_name(int32_t id, int32_t i) {
  JNIEnv *env = env_();
  jstring s = (jstring)(*env)->CallStaticObjectMethod(env, picks_cls, m_pk_name, id, i);
  moonbit_string_t out = s ? mstr(env, s) : moonbit_make_string_raw(0);
  if (s) (*env)->DeleteLocalRef(env, s);
  return out;
}

moonbit_bytes_t mb_host_pick_bytes(int32_t id, int32_t i) {
  JNIEnv *env = env_();
  jbyteArray a = (jbyteArray)(*env)->CallStaticObjectMethod(env, picks_cls, m_pk_bytes, id, i);
  jsize n = a ? (*env)->GetArrayLength(env, a) : 0;
  moonbit_bytes_t out = moonbit_make_bytes(n, 0);
  if (n) (*env)->GetByteArrayRegion(env, a, 0, n, (jbyte *)out);
  if (a) (*env)->DeleteLocalRef(env, a);
  return out;
}

void mb_host_pick_end(int32_t id) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, picks_cls, m_pk_end, id);
}

// ---------------------------------------------------------------------------
// Native views over the canvas (host_native.mbt `view_*`): dev.mbui.NativeViews keeps them in a layer under the GL
// surface (which is on top and translucent: they show through the holes the app paints, kind 9), a video player
// (Media3's ExoPlayer, its bytes read through the app) or a WebView. Called on the GL thread; NativeViews moves to the
// main thread what must run there.

static jbyteArray jbytes(JNIEnv *env, moonbit_bytes_t data) {
  jsize n = Moonbit_array_length(data);
  jbyteArray b = (*env)->NewByteArray(env, n);
  if (n) (*env)->SetByteArrayRegion(env, b, 0, n, (const jbyte *)data);
  return b;
}

int32_t mb_host_view_open(int32_t kind, moonbit_string_t arg) {
  JNIEnv *env = env_();
  jstring a = jstr(env, arg);
  jint id = (*env)->CallStaticIntMethod(env, views_cls, m_v_open, kind, a);
  (*env)->DeleteLocalRef(env, a);
  return id;
}

void mb_host_view_place(int32_t id, double x, double y, double w, double h, double cx0, double cy0, double cx1,
                        double cy1, int32_t shown) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, views_cls, m_v_place, id, (jfloat)x, (jfloat)y, (jfloat)w, (jfloat)h,
                               (jfloat)cx0, (jfloat)cy0, (jfloat)cx1, (jfloat)cy1, shown ? JNI_TRUE : JNI_FALSE);
}

void mb_host_view_close(int32_t id) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, views_cls, m_v_close, id);
}

void mb_host_view_control(int32_t id, int32_t op, double value) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, views_cls, m_v_control, id, op, value);
}

int32_t mb_host_view_info(int32_t id, double *out) {
  JNIEnv *env = env_();
  jint st = (*env)->CallStaticIntMethod(env, views_cls, m_v_info, id, small_buf);
  (*env)->GetDoubleArrayRegion(env, small_buf, 0, 8, out);
  return st;
}

int32_t mb_host_view_read_next(int32_t id, double *out) {
  JNIEnv *env = env_();
  jint req = (*env)->CallStaticIntMethod(env, views_cls, m_v_read_next, id, small_buf);
  if (req > 0) (*env)->GetDoubleArrayRegion(env, small_buf, 0, 2, out);
  return req;
}

void mb_host_view_read_answer(int32_t id, int32_t req, moonbit_bytes_t data, double total) {
  JNIEnv *env = env_();
  jbyteArray b = jbytes(env, data);
  (*env)->CallStaticVoidMethod(env, views_cls, m_v_read_answer, id, req, b, total);
  (*env)->DeleteLocalRef(env, b);
}

int32_t mb_host_save_file(moonbit_string_t name, moonbit_bytes_t data) {
  JNIEnv *env = env_();
  jstring n = jstr(env, name);
  jbyteArray b = jbytes(env, data);
  jboolean ok = (*env)->CallStaticBooleanMethod(env, views_cls, m_save, n, b);
  (*env)->DeleteLocalRef(env, n);
  (*env)->DeleteLocalRef(env, b);
  return ok ? 1 : 0;
}

// PDFs (host_native.mbt `pdf_*`): dev.mbui.Pdfs over the system's PdfRenderer; a page drawn is an image of the table
// above, uploaded as a decoded image is (Images.upload).

int32_t mb_host_pdf_open(moonbit_bytes_t data) {
  JNIEnv *env = env_();
  jbyteArray b = jbytes(env, data);
  jint doc = (*env)->CallStaticIntMethod(env, pdfs_cls, m_pdf_open, b);
  (*env)->DeleteLocalRef(env, b);
  return doc;
}

int32_t mb_host_pdf_pages(int32_t doc) {
  JNIEnv *env = env_();
  return (*env)->CallStaticIntMethod(env, pdfs_cls, m_pdf_pages, doc);
}

void mb_host_pdf_page_size(int32_t doc, int32_t page, double *out) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, pdfs_cls, m_pdf_size, doc, page, small_buf);
  (*env)->GetDoubleArrayRegion(env, small_buf, 0, 2, out);
}

int32_t mb_host_pdf_page_load(int32_t doc, int32_t page, int32_t max_px) {
  JNIEnv *env = env_();
  int id = image_new();
  (*env)->CallStaticVoidMethod(env, pdfs_cls, m_pdf_load, doc, page, max_px, id);
  return id;
}

void mb_host_pdf_close(int32_t doc) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, pdfs_cls, m_pdf_close, doc);
}
