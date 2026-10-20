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
#include <zlib.h>
#include "moonbit.h"
#include "post.h"
#include "done_watch.h"
#include "corner_sl.h"

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
static jclass host_cls, text_cls, images_cls, login_cls, picks_cls, views_cls, pdfs_cls, notices_cls;
static jmethodID m_reduce_motion;
static jmethodID m_request_frame, m_wake_after, m_set_ime, m_clipboard, m_log, m_bench,
    m_exit, m_metrics, m_shape, m_glyph, m_generation, m_img_load, m_img_free, m_img_reload, m_bl_start, m_bl_port,
    m_bl_open, m_bl_back, m_bl_end, m_back_enabled, m_pk_start, m_pk_state, m_pk_count, m_pk_name, m_pk_bytes,
    m_pk_end, m_drive, m_ref_begin, m_ref_text, m_ref_end, m_ref_frame, m_text_key, m_v_open, m_v_place, m_v_close,
    m_v_control, m_v_info, m_v_read_next, m_v_read_answer, m_v_site_next, m_v_site_body, m_v_site_head,
    m_v_site_chunk, m_v_site_end, m_v_site_state, m_v_site_load, m_v_tell, m_pdf_open, m_pdf_pages, m_pdf_size, m_pdf_load, m_pdf_close,
    m_save, m_system_dark, m_set_dark, m_nt_show, m_nt_cancel, m_nt_state, m_nt_text, m_set_sideways, m_word_at,
    m_open_url, m_open_tab, m_hold_words, m_clipboard_secret, m_over_done, m_text_scale, m_img_hold, m_img_pump;
static jclass updates_cls, shares_cls, keeps_cls, holds_cls;
static jclass gallery_cls, marks_cls;
static void device_init(JNIEnv *env);  // android_device.h
static jmethodID m_mk_start, m_mk_state, m_mk_png;
static jmethodID m_cs_known, m_cs_decode;
static jmethodID m_v_text, m_v_still;
static jmethodID m_ga_access, m_ga_ask, m_ga_answers, m_ga_read, m_ga_state, m_ga_rows, m_ga_end, m_pk_photo;
static jmethodID m_kp_begin, m_kp_append, m_kp_finish, m_kp_state, m_kp_where, m_kp_end;
static jmethodID m_up_version, m_up_install, m_up_state, m_up_package, m_sh_share, m_sh_in, m_sh_file;
static mb_back_fn back_cb;
static jdoubleArray shape_buf, small_buf;
static int want_frame;
// A run to a declared moment (MBView's shotFrame, Native.ownClock): the app's clock is its frames', the time the
// frame being drawn (or the last one) was given.
static int own_clock;
static double frame_now;

int mbui_main(int argc, char **argv);  // the MoonBit program's main (renamed)

// The process's VM, for the still.fail core's engine (android_core.c).
JavaVM *mb_android_vm(void) { return vm; }


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
  m_clipboard_secret = (*env)->GetStaticMethodID(env, host_cls, "clipboardSecret", "(Ljava/lang/String;D)V");
  m_log = (*env)->GetStaticMethodID(env, host_cls, "log", "(Ljava/lang/String;)V");
  m_bench = (*env)->GetStaticMethodID(env, host_cls, "benchMode", "()I");
  m_reduce_motion = (*env)->GetStaticMethodID(env, host_cls, "reduceMotion", "()I");
  m_exit = (*env)->GetStaticMethodID(env, host_cls, "exit", "(I)V");
  m_back_enabled = (*env)->GetStaticMethodID(env, host_cls, "backEnabled", "(Z)V");
  m_drive = (*env)->GetStaticMethodID(env, host_cls, "drive", "(ILjava/lang/String;)I");
  m_system_dark = (*env)->GetStaticMethodID(env, host_cls, "systemDark", "()Z");
  m_set_dark = (*env)->GetStaticMethodID(env, host_cls, "setDark", "(Z)V");
  m_set_sideways = (*env)->GetStaticMethodID(env, host_cls, "setSideways", "(Z)V");
  m_word_at = (*env)->GetStaticMethodID(env, host_cls, "wordAt", "(Ljava/lang/String;I)D");
  m_open_url = (*env)->GetStaticMethodID(env, host_cls, "openUrl", "(Ljava/lang/String;)Z");
  m_over_done = (*env)->GetStaticMethodID(env, host_cls, "overDone", "(Z)V");
  updates_cls = (*env)->NewGlobalRef(env, (*env)->FindClass(env, "dev/mbui/Updates"));
  m_up_version = (*env)->GetStaticMethodID(env, updates_cls, "versionCode", "()I");
  m_up_install = (*env)->GetStaticMethodID(env, updates_cls, "install", "(Ljava/lang/String;Ljava/lang/String;DLjava/lang/String;)V");
  m_up_package = (*env)->GetStaticMethodID(env, updates_cls, "installPackage", "(Ljava/lang/String;[B)V");
  m_up_state = (*env)->GetStaticMethodID(env, updates_cls, "state", "()Ljava/lang/String;");
  shares_cls = (*env)->NewGlobalRef(env, (*env)->FindClass(env, "dev/mbui/Shares"));
  m_sh_share = (*env)->GetStaticMethodID(env, shares_cls, "share", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;[B)Z");
  m_sh_in = (*env)->GetStaticMethodID(env, shares_cls, "sharedIn", "()Ljava/lang/String;");
  m_sh_file = (*env)->GetStaticMethodID(env, shares_cls, "sharedFile", "(I)[B");
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
  m_img_hold = (*env)->GetStaticMethodID(env, images_cls, "hold", "()V");
  m_img_pump = (*env)->GetStaticMethodID(env, images_cls, "pump", "()V");
  m_text_scale = (*env)->GetStaticMethodID(env, text_cls, "setScale", "(F)V");
  login_cls = (*env)->NewGlobalRef(env, (*env)->FindClass(env, "dev/mbui/BrowserLogin"));
  m_bl_start = (*env)->GetStaticMethodID(env, login_cls, "start", "(Ljava/lang/String;)I");
  m_bl_port = (*env)->GetStaticMethodID(env, login_cls, "port", "(I)I");
  m_bl_open = (*env)->GetStaticMethodID(env, login_cls, "open", "(ILjava/lang/String;)I");
  m_bl_back = (*env)->GetStaticMethodID(env, login_cls, "back", "(I)Ljava/lang/String;");
  m_bl_end = (*env)->GetStaticMethodID(env, login_cls, "end", "(I)V");
  m_open_tab = (*env)->GetStaticMethodID(env, login_cls, "openTab", "(Ljava/lang/String;)Z");
  holds_cls = (*env)->NewGlobalRef(env, (*env)->FindClass(env, "dev/mbui/LoginService"));
  m_hold_words = (*env)->GetStaticMethodID(env, holds_cls, "words",
                                          "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V");
  picks_cls = (*env)->NewGlobalRef(env, (*env)->FindClass(env, "dev/mbui/Picks"));
  m_pk_start = (*env)->GetStaticMethodID(env, picks_cls, "start", "(I)I");
  m_pk_state = (*env)->GetStaticMethodID(env, picks_cls, "state", "(I)I");
  m_pk_count = (*env)->GetStaticMethodID(env, picks_cls, "count", "(I)I");
  m_pk_name = (*env)->GetStaticMethodID(env, picks_cls, "name", "(II)Ljava/lang/String;");
  m_pk_bytes = (*env)->GetStaticMethodID(env, picks_cls, "bytes", "(II)[B");
  m_pk_end = (*env)->GetStaticMethodID(env, picks_cls, "end", "(I)V");
  keeps_cls = (*env)->NewGlobalRef(env, (*env)->FindClass(env, "dev/mbui/Keeps"));
  m_kp_begin = (*env)->GetStaticMethodID(env, keeps_cls, "begin", "(Ljava/lang/String;Ljava/lang/String;I)I");
  m_kp_append = (*env)->GetStaticMethodID(env, keeps_cls, "append", "(I[B)I");
  m_kp_finish = (*env)->GetStaticMethodID(env, keeps_cls, "finish", "(I)V");
  m_kp_state = (*env)->GetStaticMethodID(env, keeps_cls, "state", "(I)I");
  m_kp_where = (*env)->GetStaticMethodID(env, keeps_cls, "where", "(I)Ljava/lang/String;");
  m_kp_end = (*env)->GetStaticMethodID(env, keeps_cls, "end", "(I)V");
  marks_cls = (*env)->NewGlobalRef(env, (*env)->FindClass(env, "dev/mbui/Marks"));
  m_mk_start = (*env)->GetStaticMethodID(env, marks_cls, "start", "([BLjava/lang/String;)I");
  m_mk_state = (*env)->GetStaticMethodID(env, marks_cls, "state", "(I)I");
  m_mk_png = (*env)->GetStaticMethodID(env, marks_cls, "png", "(I)[B");
  gallery_cls = (*env)->NewGlobalRef(env, (*env)->FindClass(env, "dev/mbui/Gallery"));
  m_ga_access = (*env)->GetStaticMethodID(env, gallery_cls, "access", "()I");
  m_ga_ask = (*env)->GetStaticMethodID(env, gallery_cls, "ask", "()V");
  m_ga_answers = (*env)->GetStaticMethodID(env, gallery_cls, "answers", "()I");
  m_ga_read = (*env)->GetStaticMethodID(env, gallery_cls, "read", "()I");
  m_ga_state = (*env)->GetStaticMethodID(env, gallery_cls, "readState", "(I)I");
  m_ga_rows = (*env)->GetStaticMethodID(env, gallery_cls, "readRows", "(I)Ljava/lang/String;");
  m_ga_end = (*env)->GetStaticMethodID(env, gallery_cls, "readEnd", "(I)V");
  m_pk_photo = (*env)->GetStaticMethodID(env, picks_cls, "photo", "(Ljava/lang/String;)I");
  views_cls = (*env)->NewGlobalRef(env, (*env)->FindClass(env, "dev/mbui/NativeViews"));
  m_v_open = (*env)->GetStaticMethodID(env, views_cls, "open", "(ILjava/lang/String;)I");
  m_v_place = (*env)->GetStaticMethodID(env, views_cls, "place", "(IFFFFFFFFFZ)V");
  m_v_close = (*env)->GetStaticMethodID(env, views_cls, "close", "(I)V");
  m_v_control = (*env)->GetStaticMethodID(env, views_cls, "control", "(IID)V");
  m_v_info = (*env)->GetStaticMethodID(env, views_cls, "info", "(I[D)I");
  m_v_read_next = (*env)->GetStaticMethodID(env, views_cls, "readNext", "(I[D)I");
  m_v_read_answer = (*env)->GetStaticMethodID(env, views_cls, "readAnswer", "(II[BD)V");
  m_v_site_next = (*env)->GetStaticMethodID(env, views_cls, "siteNext", "(I)Ljava/lang/String;");
  m_v_site_body = (*env)->GetStaticMethodID(env, views_cls, "siteBody", "(II)[B");
  m_v_site_head = (*env)->GetStaticMethodID(env, views_cls, "siteHead", "(IIILjava/lang/String;)V");
  m_v_site_chunk = (*env)->GetStaticMethodID(env, views_cls, "siteChunk", "(II[B)V");
  m_v_site_end = (*env)->GetStaticMethodID(env, views_cls, "siteEnd", "(IILjava/lang/String;)V");
  m_v_site_state = (*env)->GetStaticMethodID(env, views_cls, "siteState", "(I)Ljava/lang/String;");
  m_v_site_load = (*env)->GetStaticMethodID(env, views_cls, "siteLoad", "(ILjava/lang/String;)V");
  m_v_tell = (*env)->GetStaticMethodID(env, views_cls, "tell", "(IILjava/lang/String;)V");
  m_save = (*env)->GetStaticMethodID(env, views_cls, "save", "(Ljava/lang/String;[B)Z");
  m_v_text = (*env)->GetStaticMethodID(env, views_cls, "text", "(II)Ljava/lang/String;");
  m_cs_known = (*env)->GetStaticMethodID(env, host_cls, "charsetKnown", "(Ljava/lang/String;)Z");
  m_cs_decode = (*env)->GetStaticMethodID(env, host_cls, "charsetDecode", "([BLjava/lang/String;)Ljava/lang/String;");
  m_v_still = (*env)->GetStaticMethodID(env, views_cls, "still", "(I)[B");
  pdfs_cls = (*env)->NewGlobalRef(env, (*env)->FindClass(env, "dev/mbui/Pdfs"));
  m_pdf_open = (*env)->GetStaticMethodID(env, pdfs_cls, "open", "([B)I");
  m_pdf_pages = (*env)->GetStaticMethodID(env, pdfs_cls, "pages", "(I)I");
  m_pdf_size = (*env)->GetStaticMethodID(env, pdfs_cls, "pageSize", "(II[D)V");
  m_pdf_load = (*env)->GetStaticMethodID(env, pdfs_cls, "pageLoad", "(IIII)V");
  m_pdf_close = (*env)->GetStaticMethodID(env, pdfs_cls, "close", "(I)V");
  notices_cls = (*env)->NewGlobalRef(env, (*env)->FindClass(env, "dev/mbui/Notices"));
  m_nt_show = (*env)->GetStaticMethodID(env, notices_cls, "show",
                                        "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V");
  m_nt_cancel = (*env)->GetStaticMethodID(env, notices_cls, "cancel", "(Ljava/lang/String;)V");
  m_nt_state = (*env)->GetStaticMethodID(env, notices_cls, "state", "(I)I");
  m_nt_text = (*env)->GetStaticMethodID(env, notices_cls, "text", "(I)Ljava/lang/String;");
  shape_buf = (*env)->NewGlobalRef(env, (*env)->NewDoubleArray(env, 4 * 8192));
  small_buf = (*env)->NewGlobalRef(env, (*env)->NewDoubleArray(env, 16));
  device_init(env);
  return JNI_VERSION_1_6;
}

static jstring jstr(JNIEnv *env, moonbit_string_t s) {
  return (*env)->NewString(env, (const jchar *)s, Moonbit_array_length(s));
}

static jbyteArray jbytes(JNIEnv *env, moonbit_bytes_t data);

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
  int told;  // its decode told to the app (outside_cb), once: not again when decoded anew for a new context
} mb_image;

static mb_image *imgs;  // by id; ids are not reused
static int nimgs, img_cap;

// a stream's texture (Streams.java; its instances' image is MB_STREAM_TEX + its id: src/host/stream.mbt), below
#define MB_STREAM_TEX 4194304
static GLuint stream_tex(int id);
static void streams_lost(JNIEnv *env);

static GLuint image_tex(int id) {
  if (id > MB_STREAM_TEX) return stream_tex(id - MB_STREAM_TEX);
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
  streams_lost(env);
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

// the numbers of an instance (src/ui/scene.mbt)
#define MB_INST 32

static const char *VS =
    "#version 300 es\n"
    "layout(location=0) in vec4 a_rect;\n"
    "layout(location=1) in vec4 a_p;\n"
    "layout(location=2) in vec4 a_color;\n"
    "layout(location=3) in vec4 a_c2;\n"
    "layout(location=4) in vec4 a_clip;\n"
    "layout(location=5) in vec4 a_pad;\n"
    "layout(location=6) in vec4 a_rc;\n"
    "layout(location=7) in vec4 a_rs;\n"
    "uniform vec2 u_vp;\n"
    "uniform vec4 u_gb;\n"
    "out vec2 v_pos;\n"
    "flat out vec4 v_rect; flat out vec4 v_p; flat out vec4 v_color; flat out vec4 v_c2; flat out vec4 v_clip; flat out vec4 v_pad;\n"
    "flat out vec4 v_rc; flat out vec4 v_rs;\n"
    "void main() {\n"
    "  int vid = gl_VertexID;\n"
    "  vec2 corner = vec2((vid == 1 || vid == 4 || vid == 5) ? 1.0 : 0.0, (vid == 2 || vid == 3 || vid == 5) ? 1.0 : 0.0);\n"
    "  int kind = int(a_p.y + 0.5);\n"
    "  float grow = kind == 2 ? a_p.w * 2.0 + 2.0 : ((kind == 0 || kind == 4 || kind == 5) ? 1.0 : 0.0);\n"
    "  vec2 pos = a_rect.xy - grow + corner * (a_rect.zw + 2.0 * grow);\n"
    "  if (kind == 6) pos = mix(u_gb.xy, u_gb.zw, corner);\n"
    "  gl_Position = vec4(pos.x / u_vp.x * 2.0 - 1.0, 1.0 - pos.y / u_vp.y * 2.0, 0.0, 1.0);\n"
    "  v_pos = pos; v_rect = a_rect; v_p = a_p; v_color = a_color; v_c2 = a_c2; v_clip = a_clip; v_pad = a_pad; v_rc = a_rc; v_rs = a_rs;\n"
    "}\n";

static const char *FS =
    "#version 300 es\n"
    "precision highp float;\n"
    "in vec2 v_pos;\n"
    "flat in vec4 v_rect; flat in vec4 v_p; flat in vec4 v_color; flat in vec4 v_c2; flat in vec4 v_clip; flat in vec4 v_pad;\n"
    "flat in vec4 v_rc; flat in vec4 v_rs;\n"
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
    "#define float2 vec2\n"
    MB_CORNER_SL
    "float sd_rr(vec2 p, vec4 r, float rad) {\n"
    "  vec2 hs = r.zw * 0.5;\n"
    "  return mb_sd_box(p - r.xy - hs, hs, rad, 1e9);\n"
    "}\n"
    "// a notch cut into the top edge (scene.mbt 21-23): a circle about the top's middle (pad.y below it, pad.z its radius),\n"
    "// met by the edge through fillets (pad.w): the rounded intersection with what is outside the circle\n"
    "float notch_cut(float d, vec2 p, vec4 r, vec4 pad) {\n"
    "  if (pad.z <= 0.0) return d;\n"
    "  float b = pad.z - length(p - vec2(r.x + r.z * 0.5, r.y + pad.y));\n"
    "  float f = max(pad.w, 0.0);\n"
    "  vec2 u = max(vec2(f + d, f + b), 0.0);\n"
    "  return min(-f, max(d, b)) + length(u);\n"
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
    "// how much of the pixel at p its rounded clip keeps (r: the corners' radii, top left, then clockwise; s: how smooth\n"
    "// each is), its edge covered as a box's own (0.5 - d * scale), so what it cuts meets the ground of the box that cuts it\n"
    "float clip_cover(vec2 p, vec4 c, vec4 r, vec4 s, float scale) {\n"
    "  vec2 hs = (c.zw - c.xy) * 0.5;\n"
    "  vec2 m = c.xy + hs;\n"
    "  float rr = p.x < m.x ? (p.y < m.y ? r.x : r.w) : (p.y < m.y ? r.y : r.z);\n"
    "  float ss = p.x < m.x ? (p.y < m.y ? s.x : s.w) : (p.y < m.y ? s.y : s.z);\n"
    "  float d = mb_sd_corner(p - m, hs, min(rr, min(hs.x, hs.y)), ss, 1.0 + 2.0 / scale);\n"
    "  return clamp(0.5 - d * scale, 0.0, 1.0);\n"
    "}\n"
    "// what it shows at p, as if uncut\n"
    "void shade(vec2 p) {\n"
    "  int kind = int(v_p.y + 0.5);\n"
    "  if (kind == 9) { vec2 hh = v_rect.zw * 0.5; float rr = min(v_p.x, min(hh.x, hh.y)); vec2 q = abs(p - v_rect.xy - hh) - hh + rr; if (length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rr > 0.0) discard; o = vec4(0.0); return; }\n"
    "  vec4 col = v_color;\n"
    "  if (kind == 10) {\n"
    "    // a piece of a line (scene.mbt): from c2.xy to c2.zw (shares of its rect), p.x half its width, its ends round\n"
    "    vec2 a = v_rect.xy + v_c2.xy * v_rect.zw, ab = v_rect.xy + v_c2.zw * v_rect.zw - a;\n"
    "    float h = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-8), 0.0, 1.0);\n"
    "    float d = length(p - a - ab * h) - v_p.x;\n"
    "    o = vec4(col.rgb, 1.0) * col.a * clamp(0.5 - d * u_scale, 0.0, 1.0);\n"
    "    return;\n"
    "  }\n"
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
    "  // worked out as near the curve as its cover, its edge or its blur reaches\n"
    "  float band = 1.0 + 2.0 / u_scale + (kind == 2 ? max(v_p.w, 0.5) : max(v_p.z, 0.0));\n"
    "  float d = mb_sd_box(p - c, hs, v_p.x, band);\n"
    "  if (kind == 0 || kind == 5) d = notch_cut(d, p, v_rect, v_pad);\n"
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
    "      float db = mb_sd_box(p - c + vec2(0.0, v_c2.y), hs, v_p.x, band);\n"
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
    "      float lit = clamp(0.5 + notch_cut(sd_rr(p - 0.5, v_rect, v_p.x), p - 0.5, v_rect, v_pad) * u_scale, 0.0, 1.0);\n"
    "      float back = clamp(0.5 + notch_cut(sd_rr(p + 0.5, v_rect, v_p.x), p + 0.5, v_rect, v_pad) * u_scale, 0.0, 1.0);\n"
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
    "}\n"
    "// cut to its clip: a rect's, hard; a rounded one's, covered as edges are\n"
    "void main() {\n"
    "  vec2 p = v_pos;\n"
    "  float cover = 1.0;\n"
    "  if (max(max(v_rc.x, v_rc.y), max(v_rc.z, v_rc.w)) > 0.0) {\n"
    "    cover = clip_cover(p, v_clip, v_rc, v_rs, u_scale);\n"
    "    if (cover <= 0.0) discard;\n"
    "  } else if (p.x < v_clip.x || p.y < v_clip.y || p.x > v_clip.z || p.y > v_clip.w) discard;\n"
    "  shade(p);\n"
    "  o *= cover;\n"
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
// what is drawn into: the surface (0), or mbui-render's offscreen framebuffer (mb_render_init_offscreen)
static GLuint target_fb;

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
  for (int i = 0; i < 8; i++) {
    glEnableVertexAttribArray(i);
    glVertexAttribPointer(i, 4, GL_FLOAT, GL_FALSE, MB_INST * 4, (void *)(intptr_t)(i * 16));
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

// what the run [start, end) of glass sees, frosted glass of the same capture further on (glass.mbt shares_capture)
// too; 0 when none of it shows
static int capture(const float *f, int32_t start, int32_t end, int32_t count) {
  const float *a = f + start * MB_INST;
  float blur = a[7];
  int kind = (int)(a[5] + 0.5f);
  float margin = 3.0f * blur + (kind == 6 ? a[21] * (1.0f + a[22]) + a[23] : 0.0f) + 2.0f;
  float x0 = 1e9f, y0 = 1e9f, x1 = -1e9f, y1 = -1e9f;
  gn = 0;
  for (int32_t i = start; i < end; i++) {
    const float *b = f + i * MB_INST;
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
  for (int32_t i = end; kind == 5 && i < count; i++) {
    const float *b = f + i * MB_INST;
    if (b[20] != a[20]) continue;
    float bx0 = b[0] > b[16] ? b[0] : b[16], by0 = b[1] > b[17] ? b[1] : b[17];
    float bx1 = b[0] + b[2] < b[18] ? b[0] + b[2] : b[18], by1 = b[1] + b[3] < b[19] ? b[1] + b[3] : b[19];
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
  glBindFramebuffer(GL_READ_FRAMEBUFFER, target_fb);
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
  glBindFramebuffer(GL_FRAMEBUFFER, target_fb);
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

// Over another app (OverActivity: Native.overOther): what the app does not paint stays clear, the app under it shows.
static volatile int over_other;

JNIEXPORT void JNICALL Java_dev_mbui_Native_overOther(JNIEnv *env, jclass c, jboolean on) { over_other = on ? 1 : 0; }

void mb_host_present(double *buf, int32_t count, double r, double g, double b) {
  glBindFramebuffer(GL_FRAMEBUFFER, target_fb);
  glViewport(0, 0, fb_w, fb_h);
  if (over_other) glClearColor(0, 0, 0, 0);
  else glClearColor((float)r, (float)g, (float)b, 1);
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
  size_t n = (size_t)count * MB_INST;
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
    int tid = (int)fbuf[start * MB_INST + 20];
    int hole = (int)(fbuf[start * MB_INST + 5] + 0.5f) == 9;
    int32_t end = start + 1;
    while (end < count && (int)fbuf[end * MB_INST + 20] == tid && ((int)(fbuf[end * MB_INST + 5] + 0.5f) == 9) == hole) end++;
    if (tid < 0) {
      if (tid != bound) {
        shows = capture(fbuf, start, end, count);
        bound = tid;
        main_state();
      }
      if (shows) {
        for (int i = 0; i < 8; i++)
          glVertexAttribPointer(i, 4, GL_FLOAT, GL_FALSE, MB_INST * 4, (void *)(intptr_t)(start * MB_INST * 4 + i * 16));
        // liquid: the group as one shape, drawn once
        glDrawArraysInstanced(GL_TRIANGLES, 0, 6, (int)(fbuf[start * MB_INST + 5] + 0.5f) == 6 ? 1 : end - start);
      }
      start = end;
      continue;
    }
    GLuint t = tid ? image_tex(tid) : atlas;
    if (t) {  // 0: lost with the context, decoding again
      glActiveTexture(GL_TEXTURE1);
      glBindTexture(GL_TEXTURE_2D, t);
      for (int i = 0; i < 8; i++)
        glVertexAttribPointer(i, 4, GL_FLOAT, GL_FALSE, MB_INST * 4, (void *)(intptr_t)(start * MB_INST * 4 + i * 16));
      if (hole) glDisable(GL_BLEND);
      glDrawArraysInstanced(GL_TRIANGLES, 0, 6, end - start);
      if (hole) glEnable(GL_BLEND);
    }
    start = end;
  }
}

// ---------------------------------------------------------------------------
// Without the surface (mbui-render, src/render: started as an app, on the GL thread with the surface's context
// current): a framebuffer of its own the size the surface would be, the text at the list's scale (MBText.setScale,
// not the screen's density), the images' uploads done when it asks (Images.hold, mb_render_spin). A frame is drawn
// there as on the surface, and read back from it as a PNG.

static GLuint off_tex;
double mb_host_now(void);

void mb_render_init_offscreen(double w, double h, double scale) {
  JNIEnv *env = env_();
  cur_w = w;
  cur_h = h;
  cur_scale = scale;
  fb_w = (int)floor(w * scale + 0.5);
  fb_h = (int)floor(h * scale + 0.5);
  glGenTextures(1, &off_tex);
  glBindTexture(GL_TEXTURE_2D, off_tex);
  glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA8, fb_w, fb_h);
  glGenFramebuffers(1, &target_fb);
  glBindFramebuffer(GL_FRAMEBUFFER, target_fb);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, off_tex, 0);
  if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) LOG("mbui-render: no framebuffer");
  (*env)->CallStaticVoidMethod(env, text_cls, m_text_scale, (jfloat)scale);
  (*env)->CallStaticVoidMethod(env, images_cls, m_img_hold);
}

void mb_render_draw_timed(const double *inst, int32_t count, double r, double g, double b, double *out) {
  double t0 = mb_host_now();
  mb_host_present((double *)inst, count, r, g, b);
  glFinish();
  out[0] = mb_host_now() - t0;
  out[1] = -1;
}

// the images decoded meanwhile uploaded here (Images.pump), then a while for more
void mb_render_spin(double ms) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, images_cls, m_img_pump);
  struct timespec t = {(time_t)(ms / 1000), (long)(fmod(ms, 1000) * 1e6)};
  nanosleep(&t, NULL);
}

static void png_chunk(FILE *f, const char *type, const unsigned char *data, uint32_t n) {
  unsigned char be[4] = {n >> 24, n >> 16, n >> 8, n};
  fwrite(be, 1, 4, f);
  fwrite(type, 1, 4, f);
  if (n) fwrite(data, 1, n, f);
  uLong c = crc32(0, (const Bytef *)type, 4);
  if (n) c = crc32(c, data, n);
  unsigned char cb[4] = {c >> 24, c >> 16, c >> 8, c};
  fwrite(cb, 1, 4, f);
}

// The offscreen frame as a PNG (8-bit RGBA, top row first, zlib's level 6): 1 when written.
int mb_render_snapshot(const char *path) {
  if (!target_fb || fb_w <= 0 || fb_h <= 0) return 0;
  size_t row = (size_t)fb_w * 4;
  unsigned char *px = malloc(row * fb_h), *raw = malloc((row + 1) * fb_h);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, target_fb);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glReadPixels(0, 0, fb_w, fb_h, GL_RGBA, GL_UNSIGNED_BYTE, px);
  // GL's rows are from the foot up
  for (int y = 0; y < fb_h; y++) {
    raw[(row + 1) * y] = 0;
    memcpy(raw + (row + 1) * y + 1, px + row * (fb_h - 1 - y), row);
  }
  uLongf zn = compressBound((uLong)((row + 1) * fb_h));
  unsigned char *z = malloc(zn);
  int ok = compress2(z, &zn, raw, (uLong)((row + 1) * fb_h), 6) == Z_OK;
  FILE *f = ok ? fopen(path, "wb") : NULL;
  if (f) {
    static const unsigned char sig[8] = {0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'};
    unsigned char ihdr[13] = {fb_w >> 24, fb_w >> 16, fb_w >> 8, fb_w, fb_h >> 24, fb_h >> 16, fb_h >> 8, fb_h,
                              8, 6, 0, 0, 0};
    fwrite(sig, 1, 8, f);
    png_chunk(f, "IHDR", ihdr, 13);
    png_chunk(f, "IDAT", z, (uint32_t)zn);
    png_chunk(f, "IEND", NULL, 0);
    ok = fclose(f) == 0;
  } else {
    ok = 0;
  }
  free(z);
  free(raw);
  free(px);
  return ok;
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
  frame_now = now;
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

// What the system says between frames (MainActivity: the app back on screen after a while, the device's network
// changed, a link it was opened with), posted on its channel for the app's handler (src/host/system.mbt): the JSON's
// UTF-8 as Java made it (Native.post), the channel's name ASCII.
JNIEXPORT void JNICALL Java_dev_mbui_Native_postBytes(JNIEnv *env, jclass c, jstring channel, jbyteArray json) {
  const char *ch = (*env)->GetStringUTFChars(env, channel, NULL);
  jsize n = (*env)->GetArrayLength(env, json);
  jbyte *j = (*env)->GetByteArrayElements(env, json, NULL);
  mb_post(ch, (const char *)j, (size_t)n, NULL, 0);
  (*env)->ReleaseByteArrayElements(env, json, j, JNI_ABORT);
  (*env)->ReleaseStringUTFChars(env, channel, ch);
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

JNIEXPORT void JNICALL Java_dev_mbui_Native_ownClock(JNIEnv *env, jclass c) { own_clock = 1; }

double mb_host_now(void) {
  if (own_clock) return frame_now;
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec * 1000.0 + t.tv_nsec / 1e6;
}

// The time of day (host_native.mbt's wall_ms): a run to a declared moment's (own_clock) from a fixed day
// (@ui.tester_wall's), on with its frames' clock.
double mb_host_wall_ms(void) {
  if (own_clock) return 1790000000000.0 + frame_now;
  struct timespec t;
  clock_gettime(CLOCK_REALTIME, &t);
  return t.tv_sec * 1000.0 + t.tv_nsec / 1e6;
}

void mb_host_request_frame(void) {
  want_frame = 1;
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, host_cls, m_request_frame);
}

// A message posted from outside the frames (post.h), on whatever thread: a frame asked of the view (Host.requestFrame
// is any thread's). A thread the VM does not know is attached for the call and let go after.
static void mb_post_wake(void) {
  if (!vm || !host_cls) return;
  JNIEnv *env = NULL;
  int attached = 0;
  if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) {
    if ((*vm)->AttachCurrentThread(vm, &env, NULL) != JNI_OK) return;
    attached = 1;
  }
  (*env)->CallStaticVoidMethod(env, host_cls, m_request_frame);
  if ((*env)->ExceptionCheck(env)) (*env)->ExceptionClear(env);
  if (attached) (*vm)->DetachCurrentThread(vm);
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

// Turned sideways for a film (@host.set_sideways): landscape and the system bars away, or upright (Host.setSideways).
void mb_host_set_sideways(int32_t on) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, host_cls, m_set_sideways, (jboolean)(on != 0));
}

// The word around an offset as ICU finds it (Host.wordAt, @host.word_at): start × 2³² + end, or -1.
double mb_host_word_at(moonbit_string_t text, int32_t off) {
  JNIEnv *env = env_();
  jstring t = jstr(env, text);
  jdouble v = (*env)->CallStaticDoubleMethod(env, host_cls, m_word_at, t, (jint)off);
  (*env)->DeleteLocalRef(env, t);
  return v;
}

// A URL handed to the system (Host.openUrl, @host.open_url): ACTION_VIEW.
int32_t mb_host_open_url(moonbit_string_t url) {
  JNIEnv *env = env_();
  jstring u = jstr(env, url);
  jboolean ok = (*env)->CallStaticBooleanMethod(env, host_cls, m_open_url, u);
  (*env)->DeleteLocalRef(env, u);
  return ok ? 1 : 0;
}

// The app over another app done (Host.overDone, @host.over_done): back to it, or on into the app's own activity.
void mb_host_over_done(int32_t open_app) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, host_cls, m_over_done, open_app ? JNI_TRUE : JNI_FALSE);
}

// A page in a browser's tab over the app (BrowserLogin.openTab, @host.open_tab): a Custom Tab, ACTION_VIEW where no
// browser takes one.
int32_t mb_host_open_tab(moonbit_string_t url) {
  JNIEnv *env = env_();
  jstring u = jstr(env, url);
  jboolean ok = (*env)->CallStaticBooleanMethod(env, login_cls, m_open_tab, u);
  (*env)->DeleteLocalRef(env, u);
  return ok ? 1 : 0;
}

// What the notice that holds the app up while it listens for a browser says (LoginService.words, @host.hold_words).
void mb_host_hold_words(moonbit_string_t channel, moonbit_string_t title, moonbit_string_t body) {
  JNIEnv *env = env_();
  jstring c = jstr(env, channel), t = jstr(env, title), b = jstr(env, body);
  (*env)->CallStaticVoidMethod(env, holds_cls, m_hold_words, c, t, b);
  (*env)->DeleteLocalRef(env, c);
  (*env)->DeleteLocalRef(env, t);
  (*env)->DeleteLocalRef(env, b);
}

// Sharing (Shares.java): words or a file to the system's share sheet; what another app shared in.
int32_t mb_host_share(moonbit_string_t text, moonbit_string_t name, moonbit_string_t mime, moonbit_bytes_t data) {
  JNIEnv *env = env_();
  jstring t = jstr(env, text), n = jstr(env, name), m = jstr(env, mime);
  jbyteArray b = jbytes(env, data);
  jboolean ok = (*env)->CallStaticBooleanMethod(env, shares_cls, m_sh_share, t, n, m, b);
  (*env)->DeleteLocalRef(env, t);
  (*env)->DeleteLocalRef(env, n);
  (*env)->DeleteLocalRef(env, m);
  (*env)->DeleteLocalRef(env, b);
  return ok ? 1 : 0;
}

moonbit_string_t mb_host_shared_in(void) {
  JNIEnv *env = env_();
  jstring j = (jstring)(*env)->CallStaticObjectMethod(env, shares_cls, m_sh_in);
  moonbit_string_t out = j ? mstr(env, j) : moonbit_make_string_raw(0);
  if (j) (*env)->DeleteLocalRef(env, j);
  return out;
}

moonbit_bytes_t mb_host_shared_in_file(int32_t i) {
  JNIEnv *env = env_();
  jbyteArray a = (jbyteArray)(*env)->CallStaticObjectMethod(env, shares_cls, m_sh_file, i);
  jsize n = a ? (*env)->GetArrayLength(env, a) : 0;
  moonbit_bytes_t out = moonbit_make_bytes(n, 0);
  if (n) (*env)->GetByteArrayRegion(env, a, 0, n, (jbyte *)out);
  if (a) (*env)->DeleteLocalRef(env, a);
  return out;
}

// Updates (Updates.java): this build's version code, a newer one installed, how that goes.
int32_t mb_host_app_version(void) {
  JNIEnv *env = env_();
  return (*env)->CallStaticIntMethod(env, updates_cls, m_up_version);
}

void mb_host_update_install(moonbit_string_t url, moonbit_string_t sha256, double size, moonbit_string_t name) {
  JNIEnv *env = env_();
  jstring u = jstr(env, url), h = jstr(env, sha256), n = jstr(env, name);
  (*env)->CallStaticVoidMethod(env, updates_cls, m_up_install, u, h, size, n);
  (*env)->DeleteLocalRef(env, u);
  (*env)->DeleteLocalRef(env, h);
  (*env)->DeleteLocalRef(env, n);
}

// A package handed to the system's installer (Updates.installPackage, @host.install_package); what comes of it is
// posted on the system channel (system.mbt `install`).
void mb_host_install_package(moonbit_string_t name, moonbit_bytes_t data) {
  JNIEnv *env = env_();
  jstring n = jstr(env, name);
  jbyteArray b = jbytes(env, data);
  (*env)->CallStaticVoidMethod(env, updates_cls, m_up_package, n, b);
  (*env)->DeleteLocalRef(env, n);
  (*env)->DeleteLocalRef(env, b);
}

moonbit_string_t mb_host_update_state(void) {
  JNIEnv *env = env_();
  jstring j = (jstring)(*env)->CallStaticObjectMethod(env, updates_cls, m_up_state);
  moonbit_string_t out = j ? mstr(env, j) : moonbit_make_string_raw(0);
  if (j) (*env)->DeleteLocalRef(env, j);
  return out;
}

void mb_host_wake_after(double ms) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, host_cls, m_wake_after, ms);
}

void mb_host_font_metrics(double size, int32_t weight, int32_t style, double *out) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, text_cls, m_metrics, size, weight, style, small_buf);
  (*env)->GetDoubleArrayRegion(env, small_buf, 0, 6, out);
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

// A secret on the clipboard (Host.clipboardSecret): marked sensitive, cleared `clear_ms` later if still there.
void mb_host_clipboard_secret(moonbit_string_t s, double clear_ms) {
  JNIEnv *env = env_();
  jstring j = jstr(env, s);
  (*env)->CallStaticVoidMethod(env, host_cls, m_clipboard_secret, j, clear_ms);
  (*env)->DeleteLocalRef(env, j);
}

void mb_host_log(moonbit_string_t s) {
  JNIEnv *env = env_();
  jstring j = jstr(env, s);
  (*env)->CallStaticVoidMethod(env, host_cls, m_log, j);
  (*env)->DeleteLocalRef(env, j);
}

// Whether the run is on its own clock (host_native.mbt's own_clock): a run to a declared moment's (Native.ownClock).
int32_t mb_host_own_clock(void) { return own_clock; }

int32_t mb_host_reduce_motion(void) {
  JNIEnv *env = env_();
  return (*env)->CallStaticIntMethod(env, host_cls, m_reduce_motion);
}

// What the host did for the app is done (host_native.mbt's set_outside): kind 1 an image or a PDF's page decoded and
// uploaded (Native.imageDone, below), 2 a native view ready (NativeViews.NView.tell: a page loaded and drawn, a
// video's first frame shown, a sound that can play) or failed (state -1), or (a view, state 0: NView.askApp) waiting on
// the app now, a player's read or a site's request: the host's work for it stops until the app answers. Told on the
// GL thread, MoonBit's, between frames (each comes as a queued event, which GLSurfaceView runs before the next
// onDrawFrame); ready or failed once per item. Also (Native.tell) what the pickers gave, the gallery read, marks
// drawn, a video's frame grabbed, an update's progress: the kinds named as src/ui/hostcall.mbt's outside_* and
// Native.java's OUTSIDE_*.
enum { MB_OUTSIDE_IMAGE = 1, MB_OUTSIDE_VIEW = 2 };
static void (*outside_cb)(int32_t, int32_t, int32_t);
int32_t mb_host_set_outside(void (*f)(int32_t, int32_t, int32_t)) {
  outside_cb = f;
  return 1;
}

JNIEXPORT void JNICALL Java_dev_mbui_Native_outside(JNIEnv *env, jclass c, jint kind, jint id, jint state) {
  if (outside_cb) outside_cb(kind, id, state);
}

// How many of the app's asks are not answered yet, and what they are, as the frame just built left it
// (host_native.mbt's frame_awaiting): a run to a declared moment keeps its clock still while any is (MBView's
// shotFrame, Native.awaiting).
static int awaiting_n;
void mb_host_frame_awaiting(int32_t awaiting, moonbit_string_t what) {
  (void)what;
  awaiting_n = awaiting;
}
JNIEXPORT jint JNICALL Java_dev_mbui_Native_awaiting(JNIEnv *env, jclass c) { return awaiting_n; }

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
  // the directory the run's runner says what it has done in, watched (done_watch.h)
  if (kind == 9) return mb_done_watch(text);
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
  int told = imgs[id].told;
  mb_image *im = &imgs[id];
  if (im->tex && im->tex != t) glDeleteTextures(1, &im->tex);
  *im = (mb_image){t ? 1 : -1, t, w, h, ow, oh, 1};
  if (told) return;
  if (outside_cb) outside_cb(MB_OUTSIDE_IMAGE, id, t ? 1 : -1);
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
                        double cy1, double radius, int32_t shown) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, views_cls, m_v_place, id, (jfloat)x, (jfloat)y, (jfloat)w, (jfloat)h,
                               (jfloat)cx0, (jfloat)cy0, (jfloat)cx1, (jfloat)cy1, (jfloat)radius,
                               shown ? JNI_TRUE : JNI_FALSE);
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
  (*env)->GetDoubleArrayRegion(env, small_buf, 0, 10, out);
  return st;
}

int32_t mb_host_view_read_next(int32_t id, double *out) {
  JNIEnv *env = env_();
  jint req = (*env)->CallStaticIntMethod(env, views_cls, m_v_read_next, id, small_buf);
  if (req > 0) (*env)->GetDoubleArrayRegion(env, small_buf, 0, 2, out);
  return req;
}

// A site's (kind 3: NativeViews.Site): what it says, its requests answered, where its page is.
moonbit_string_t mb_host_view_site_next(int32_t id) {
  JNIEnv *env = env_();
  jstring j = (jstring)(*env)->CallStaticObjectMethod(env, views_cls, m_v_site_next, id);
  moonbit_string_t out = j ? mstr(env, j) : moonbit_make_string_raw(0);
  if (j) (*env)->DeleteLocalRef(env, j);
  return out;
}

moonbit_bytes_t mb_host_view_site_body(int32_t id, int32_t req) {
  JNIEnv *env = env_();
  jbyteArray a = (jbyteArray)(*env)->CallStaticObjectMethod(env, views_cls, m_v_site_body, id, req);
  jsize n = a ? (*env)->GetArrayLength(env, a) : 0;
  moonbit_bytes_t out = moonbit_make_bytes(n, 0);
  if (n) (*env)->GetByteArrayRegion(env, a, 0, n, (jbyte *)out);
  if (a) (*env)->DeleteLocalRef(env, a);
  return out;
}

void mb_host_view_site_head(int32_t id, int32_t req, int32_t status, moonbit_string_t headers) {
  JNIEnv *env = env_();
  jstring h = jstr(env, headers);
  (*env)->CallStaticVoidMethod(env, views_cls, m_v_site_head, id, req, status, h);
  (*env)->DeleteLocalRef(env, h);
}

void mb_host_view_site_chunk(int32_t id, int32_t req, moonbit_bytes_t data) {
  JNIEnv *env = env_();
  jbyteArray b = jbytes(env, data);
  (*env)->CallStaticVoidMethod(env, views_cls, m_v_site_chunk, id, req, b);
  (*env)->DeleteLocalRef(env, b);
}

void mb_host_view_site_end(int32_t id, int32_t req, moonbit_string_t error) {
  JNIEnv *env = env_();
  jstring e = jstr(env, error);
  (*env)->CallStaticVoidMethod(env, views_cls, m_v_site_end, id, req, e);
  (*env)->DeleteLocalRef(env, e);
}

moonbit_string_t mb_host_view_site_state(int32_t id) {
  JNIEnv *env = env_();
  jstring j = (jstring)(*env)->CallStaticObjectMethod(env, views_cls, m_v_site_state, id);
  moonbit_string_t out = j ? mstr(env, j) : moonbit_make_string_raw(0);
  if (j) (*env)->DeleteLocalRef(env, j);
  return out;
}

void mb_host_view_site_load(int32_t id, moonbit_string_t path) {
  JNIEnv *env = env_();
  jstring p = jstr(env, path);
  (*env)->CallStaticVoidMethod(env, views_cls, m_v_site_load, id, p);
  (*env)->DeleteLocalRef(env, p);
}

// What the app tells a view beyond its controls (host_native.mbt view_tell: a script, who takes a finger, a site's
// settings): NativeViews.tell.
void mb_host_view_tell(int32_t id, int32_t what, moonbit_string_t text) {
  JNIEnv *env = env_();
  jstring t = jstr(env, text);
  (*env)->CallStaticVoidMethod(env, views_cls, m_v_tell, id, what, t);
  (*env)->DeleteLocalRef(env, t);
}

void mb_host_view_read_answer(int32_t id, int32_t req, moonbit_bytes_t data, double total) {
  JNIEnv *env = env_();
  jbyteArray b = jbytes(env, data);
  (*env)->CallStaticVoidMethod(env, views_cls, m_v_read_answer, id, req, b, total);
  (*env)->DeleteLocalRef(env, b);
}

// Text in a legacy encoding (charset.mbt): java.nio's Charset (Host.charsetDecode).

int32_t mb_host_charset_known(moonbit_string_t charset) {
  JNIEnv *env = env_();
  jstring c = jstr(env, charset);
  jboolean ok = (*env)->CallStaticBooleanMethod(env, host_cls, m_cs_known, c);
  (*env)->DeleteLocalRef(env, c);
  return ok ? 1 : 0;
}

moonbit_string_t mb_host_charset_decode(moonbit_bytes_t data, moonbit_string_t charset) {
  JNIEnv *env = env_();
  jstring c = jstr(env, charset);
  jbyteArray b = jbytes(env, data);
  jstring s = (jstring)(*env)->CallStaticObjectMethod(env, host_cls, m_cs_decode, b, c);
  moonbit_string_t out = s ? mstr(env, s) : moonbit_make_string_raw(0);
  if (s) (*env)->DeleteLocalRef(env, s);
  (*env)->DeleteLocalRef(env, b);
  (*env)->DeleteLocalRef(env, c);
  return out;
}

// A video's frames' times and a frame grabbed (native.mbt `frames`, `grabbed`): NativeViews.Video.

moonbit_string_t mb_host_view_text(int32_t id, int32_t what) {
  JNIEnv *env = env_();
  jstring s = (jstring)(*env)->CallStaticObjectMethod(env, views_cls, m_v_text, id, what);
  moonbit_string_t out = s ? mstr(env, s) : moonbit_make_string_raw(0);
  if (s) (*env)->DeleteLocalRef(env, s);
  return out;
}

int32_t mb_host_view_text_known(int32_t id, int32_t what) {
  JNIEnv *env = env_();
  jstring s = (jstring)(*env)->CallStaticObjectMethod(env, views_cls, m_v_text, id, what);
  if (s) (*env)->DeleteLocalRef(env, s);
  return s ? 1 : 0;
}

moonbit_bytes_t mb_host_view_still(int32_t id) {
  JNIEnv *env = env_();
  jbyteArray a = (jbyteArray)(*env)->CallStaticObjectMethod(env, views_cls, m_v_still, id);
  jsize n = a ? (*env)->GetArrayLength(env, a) : 0;
  moonbit_bytes_t out = moonbit_make_bytes(n, 0);
  if (n) (*env)->GetByteArrayRegion(env, a, 0, n, (jbyte *)out);
  if (a) (*env)->DeleteLocalRef(env, a);
  return out;
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

// Marks drawn onto an image (marks.mbt): dev.mbui.Marks.

int32_t mb_host_marks_start(moonbit_bytes_t image, moonbit_string_t marks) {
  JNIEnv *env = env_();
  jbyteArray b = jbytes(env, image);
  jstring m = jstr(env, marks);
  jint id = (*env)->CallStaticIntMethod(env, marks_cls, m_mk_start, b, m);
  (*env)->DeleteLocalRef(env, b);
  (*env)->DeleteLocalRef(env, m);
  return id;
}

int32_t mb_host_marks_state(int32_t id) {
  JNIEnv *env = env_();
  return (*env)->CallStaticIntMethod(env, marks_cls, m_mk_state, id);
}

moonbit_bytes_t mb_host_marks_png(int32_t id) {
  JNIEnv *env = env_();
  jbyteArray a = (jbyteArray)(*env)->CallStaticObjectMethod(env, marks_cls, m_mk_png, id);
  jsize n = a ? (*env)->GetArrayLength(env, a) : 0;
  moonbit_bytes_t out = moonbit_make_bytes(n, 0);
  if (n) (*env)->GetByteArrayRegion(env, a, 0, n, (jbyte *)out);
  if (a) (*env)->DeleteLocalRef(env, a);
  return out;
}

// The gallery (gallery.mbt): dev.mbui.Gallery; a photo of it picked by its address (Picks.photo).

int32_t mb_host_gallery_access(void) {
  JNIEnv *env = env_();
  return (*env)->CallStaticIntMethod(env, gallery_cls, m_ga_access);
}

void mb_host_gallery_ask(void) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, gallery_cls, m_ga_ask);
}

int32_t mb_host_gallery_answers(void) {
  JNIEnv *env = env_();
  return (*env)->CallStaticIntMethod(env, gallery_cls, m_ga_answers);
}

int32_t mb_host_gallery_read(void) {
  JNIEnv *env = env_();
  return (*env)->CallStaticIntMethod(env, gallery_cls, m_ga_read);
}

int32_t mb_host_gallery_read_state(int32_t id) {
  JNIEnv *env = env_();
  return (*env)->CallStaticIntMethod(env, gallery_cls, m_ga_state, id);
}

moonbit_string_t mb_host_gallery_read_rows(int32_t id) {
  JNIEnv *env = env_();
  jstring s = (jstring)(*env)->CallStaticObjectMethod(env, gallery_cls, m_ga_rows, id);
  moonbit_string_t out = s ? mstr(env, s) : moonbit_make_string_raw(0);
  if (s) (*env)->DeleteLocalRef(env, s);
  return out;
}

void mb_host_gallery_read_end(int32_t id) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, gallery_cls, m_ga_end, id);
}

int32_t mb_host_pick_photo(moonbit_string_t src) {
  JNIEnv *env = env_();
  jstring s = jstr(env, src);
  jint id = (*env)->CallStaticIntMethod(env, picks_cls, m_pk_photo, s);
  (*env)->DeleteLocalRef(env, s);
  return id;
}

// Files kept on the device (keep.mbt): dev.mbui.Keeps, MediaStore's Downloads or the documents UI's CreateDocument.

int32_t mb_host_keep_begin(moonbit_string_t name, moonbit_string_t mime, int32_t way) {
  JNIEnv *env = env_();
  jstring n = jstr(env, name), m = jstr(env, mime);
  jint id = (*env)->CallStaticIntMethod(env, keeps_cls, m_kp_begin, n, m, way);
  (*env)->DeleteLocalRef(env, n);
  (*env)->DeleteLocalRef(env, m);
  return id;
}

int32_t mb_host_keep_append(int32_t id, moonbit_bytes_t data) {
  JNIEnv *env = env_();
  jbyteArray b = jbytes(env, data);
  jint ok = (*env)->CallStaticIntMethod(env, keeps_cls, m_kp_append, id, b);
  (*env)->DeleteLocalRef(env, b);
  return ok;
}

void mb_host_keep_finish(int32_t id) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, keeps_cls, m_kp_finish, id);
}

int32_t mb_host_keep_state(int32_t id) {
  JNIEnv *env = env_();
  return (*env)->CallStaticIntMethod(env, keeps_cls, m_kp_state, id);
}

moonbit_string_t mb_host_keep_where(int32_t id) {
  JNIEnv *env = env_();
  jstring s = (jstring)(*env)->CallStaticObjectMethod(env, keeps_cls, m_kp_where, id);
  moonbit_string_t out = s ? mstr(env, s) : moonbit_make_string_raw(0);
  if (s) (*env)->DeleteLocalRef(env, s);
  return out;
}

void mb_host_keep_end(int32_t id) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, keeps_cls, m_kp_end, id);
}

// Notifications (notify.mbt): dev.mbui.Notices over the system's NotificationManager; the tap comes back to
// MainActivity, which keeps what it opens until the app asks (Notices.text 0).

void mb_host_notice_show(moonbit_string_t channel, moonbit_string_t tag, moonbit_string_t title, moonbit_string_t body,
                         moonbit_string_t opens) {
  JNIEnv *env = env_();
  jstring c = jstr(env, channel), t = jstr(env, tag), h = jstr(env, title), b = jstr(env, body), o = jstr(env, opens);
  (*env)->CallStaticVoidMethod(env, notices_cls, m_nt_show, c, t, h, b, o);
  (*env)->DeleteLocalRef(env, c);
  (*env)->DeleteLocalRef(env, t);
  (*env)->DeleteLocalRef(env, h);
  (*env)->DeleteLocalRef(env, b);
  (*env)->DeleteLocalRef(env, o);
}

void mb_host_notice_cancel(moonbit_string_t tag) {
  JNIEnv *env = env_();
  jstring t = jstr(env, tag);
  (*env)->CallStaticVoidMethod(env, notices_cls, m_nt_cancel, t);
  (*env)->DeleteLocalRef(env, t);
}

int32_t mb_host_notice_state(int32_t what) {
  JNIEnv *env = env_();
  return (*env)->CallStaticIntMethod(env, notices_cls, m_nt_state, what);
}

moonbit_string_t mb_host_notice_text(int32_t what) {
  JNIEnv *env = env_();
  jstring s = (jstring)(*env)->CallStaticObjectMethod(env, notices_cls, m_nt_text, what);
  moonbit_string_t out = s ? mstr(env, s) : moonbit_make_string_raw(0);
  if (s) (*env)->DeleteLocalRef(env, s);
  return out;
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

// The desktop's window and pointer (@host.window_setup, window_inset, window_drag, set_cursor): no window to size
// or move here, no pointer to shape.
void mb_host_window_setup(double min_w, double min_h, double w, double h, int32_t inset) {
  (void)min_w; (void)min_h; (void)w; (void)h; (void)inset;
}
int32_t mb_host_window_inset(void) { return 0; }
void mb_host_window_drag(void) {}
void mb_host_set_cursor(int32_t kind) { (void)kind; }

// ---------------------------------------------------------------------------
// Streams (src/host/stream.mbt): dev.mbui.Streams decodes (MediaCodec, BitmapFactory) and draws each frame the app
// shows into a texture of its own on the GL thread, told here (Streams.texture) for the renderer to draw the stream's
// instances with. What MediaCodec takes of H.264 is made by avc.h, the conversion the hosts share.

#include "avc.h"

static jclass streams_cls;
static jmethodID m_st_open, m_st_h264, m_st_frame, m_st_jpeg, m_st_next, m_st_show, m_st_close, m_st_here, m_st_lost;
static GLuint *stream_texs;  // by id
static int stream_cap;

// (looked up as the first stream opens, on the GL thread under a call from Java: the app's class loader)
static JNIEnv *streams_env(void) {
  JNIEnv *env = env_();
  if (!streams_cls) {
    streams_cls = (*env)->NewGlobalRef(env, (*env)->FindClass(env, "dev/mbui/Streams"));
    m_st_open = (*env)->GetStaticMethodID(env, streams_cls, "open", "()I");
    m_st_h264 = (*env)->GetStaticMethodID(env, streams_cls, "h264", "(I[BII)V");
    m_st_frame = (*env)->GetStaticMethodID(env, streams_cls, "frame", "(I[BZD)V");
    m_st_jpeg = (*env)->GetStaticMethodID(env, streams_cls, "jpeg", "(I[BD)V");
    m_st_next = (*env)->GetStaticMethodID(env, streams_cls, "next", "(I)Ljava/lang/String;");
    m_st_show = (*env)->GetStaticMethodID(env, streams_cls, "show", "(ID)V");
    m_st_close = (*env)->GetStaticMethodID(env, streams_cls, "close", "(I)V");
    m_st_here = (*env)->GetStaticMethodID(env, streams_cls, "h264Here", "()Z");
    m_st_lost = (*env)->GetStaticMethodID(env, streams_cls, "lost", "()V");
  }
  return env;
}

static GLuint stream_tex(int id) { return id > 0 && id < stream_cap ? stream_texs[id] : 0; }

// A Java exception out of a call into Streams: logged (its stack on logcat) and cleared, so the GL thread's next JNI
// call does not find it pending (CheckJNI aborts the process on that).
static int streams_threw(JNIEnv *env) {
  if (!(*env)->ExceptionCheck(env)) return 0;
  (*env)->ExceptionDescribe(env);
  (*env)->ExceptionClear(env);
  return 1;
}

static void streams_lost(JNIEnv *env) {
  if (!streams_cls) return;
  for (int i = 0; i < stream_cap; i++) stream_texs[i] = 0;
  (*env)->CallStaticVoidMethod(env, streams_cls, m_st_lost);
  streams_threw(env);
}

JNIEXPORT void JNICALL Java_dev_mbui_Streams_texture(JNIEnv *env, jclass c, jint id, jint tex) {
  if (id <= 0) return;
  if (id >= stream_cap) {
    int cap = stream_cap ? stream_cap : 16;
    while (cap <= id) cap *= 2;
    stream_texs = realloc(stream_texs, (size_t)cap * sizeof *stream_texs);
    memset(stream_texs + stream_cap, 0, (size_t)(cap - stream_cap) * sizeof *stream_texs);
    stream_cap = cap;
  }
  stream_texs[id] = (GLuint)tex;
}

JNIEXPORT jint JNICALL Java_dev_mbui_Streams_avcLengthSize(JNIEnv *env, jclass c, jbyteArray avcc) {
  jsize n = (*env)->GetArrayLength(env, avcc);
  jbyte *b = (*env)->GetByteArrayElements(env, avcc, NULL);
  mb_avc_config cfg;
  int ok = mb_avc_parse((const uint8_t *)b, (size_t)n, &cfg);
  (*env)->ReleaseByteArrayElements(env, avcc, b, JNI_ABORT);
  return ok ? cfg.length_size : -1;
}

JNIEXPORT jbyteArray JNICALL Java_dev_mbui_Streams_avcCsd(JNIEnv *env, jclass c, jbyteArray avcc, jint kind) {
  jsize n = (*env)->GetArrayLength(env, avcc);
  jbyte *b = (*env)->GetByteArrayElements(env, avcc, NULL);
  mb_avc_config cfg;
  jbyteArray out = NULL;
  if (mb_avc_parse((const uint8_t *)b, (size_t)n, &cfg)) {
    size_t size = mb_avc_csd(&cfg, kind, NULL, 0);
    uint8_t *tmp = malloc(size ? size : 1);
    mb_avc_csd(&cfg, kind, tmp, size);
    out = (*env)->NewByteArray(env, (jsize)size);
    (*env)->SetByteArrayRegion(env, out, 0, (jsize)size, (const jbyte *)tmp);
    free(tmp);
  }
  (*env)->ReleaseByteArrayElements(env, avcc, b, JNI_ABORT);
  return out;
}

JNIEXPORT jbyteArray JNICALL Java_dev_mbui_Streams_annexB(JNIEnv *env, jclass c, jbyteArray frame, jint length_size) {
  jsize n = (*env)->GetArrayLength(env, frame);
  jbyte *b = (*env)->GetByteArrayElements(env, frame, NULL);
  jbyteArray out = NULL;
  long size = mb_avc_annexb_size((const uint8_t *)b, (size_t)n, length_size);
  if (size >= 0) {
    out = (*env)->NewByteArray(env, (jsize)size);
    jbyte *o = (*env)->GetByteArrayElements(env, out, NULL);
    mb_avc_annexb((const uint8_t *)b, (size_t)n, length_size, (uint8_t *)o, (size_t)size);
    (*env)->ReleaseByteArrayElements(env, out, o, 0);
  }
  (*env)->ReleaseByteArrayElements(env, frame, b, JNI_ABORT);
  return out;
}

int32_t mb_host_stream_open(void) {
  JNIEnv *env = streams_env();
  jint id = (*env)->CallStaticIntMethod(env, streams_cls, m_st_open);
  return streams_threw(env) ? 0 : id;
}

void mb_host_stream_h264(int32_t id, moonbit_bytes_t avcc, int32_t w, int32_t h) {
  JNIEnv *env = streams_env();
  jbyteArray b = jbytes(env, avcc);
  (*env)->CallStaticVoidMethod(env, streams_cls, m_st_h264, id, b, w, h);
  streams_threw(env);
  (*env)->DeleteLocalRef(env, b);
}

void mb_host_stream_frame(int32_t id, moonbit_bytes_t data, int32_t key, double ts) {
  JNIEnv *env = streams_env();
  jbyteArray b = jbytes(env, data);
  (*env)->CallStaticVoidMethod(env, streams_cls, m_st_frame, id, b, key ? JNI_TRUE : JNI_FALSE, ts);
  streams_threw(env);
  (*env)->DeleteLocalRef(env, b);
}

void mb_host_stream_jpeg(int32_t id, moonbit_bytes_t data, double ts) {
  JNIEnv *env = streams_env();
  jbyteArray b = jbytes(env, data);
  (*env)->CallStaticVoidMethod(env, streams_cls, m_st_jpeg, id, b, ts);
  streams_threw(env);
  (*env)->DeleteLocalRef(env, b);
}

moonbit_string_t mb_host_stream_next(int32_t id) {
  JNIEnv *env = streams_env();
  jstring s = (*env)->CallStaticObjectMethod(env, streams_cls, m_st_next, id);
  if (streams_threw(env) || !s) return moonbit_make_string_raw(0);
  moonbit_string_t out = mstr(env, s);
  (*env)->DeleteLocalRef(env, s);
  return out;
}

void mb_host_stream_show(int32_t id, double ts) {
  JNIEnv *env = streams_env();
  (*env)->CallStaticVoidMethod(env, streams_cls, m_st_show, id, ts);
  streams_threw(env);
}

void mb_host_stream_close(int32_t id) {
  JNIEnv *env = streams_env();
  (*env)->CallStaticVoidMethod(env, streams_cls, m_st_close, id);
  streams_threw(env);
}

int32_t mb_host_h264_here(void) {
  JNIEnv *env = streams_env();
  jboolean here = (*env)->CallStaticBooleanMethod(env, streams_cls, m_st_here);
  return !streams_threw(env) && here ? 1 : 0;
}

// The device beyond the window (device.mbt): a key catcher, the soft keyboard, the clipboard, awake, haptics.
#include "android_device.h"
