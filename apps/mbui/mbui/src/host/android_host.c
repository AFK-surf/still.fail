// Android host: the C side of android/ (dev.mbui.*). Java owns the
// Activity, the GLSurfaceView, input and the input method; this file owns the
// GLES3 renderer and forwards between Java and the MoonBit callbacks. All
// MoonBit code runs on the GL thread. Built by scripts/android.sh.
#include <sys/resource.h>
#include <jni.h>
#include <GLES3/gl3.h>
#include <android/log.h>
#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/system_properties.h>
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
static jmethodID m_text_menu;
static jmethodID m_posted;
static jmethodID m_request_frame, m_wake_after, m_set_ime, m_clipboard, m_log, m_bench,
    m_exit, m_metrics, m_shape, m_glyph, m_glyph_put, m_generation, m_img_load, m_img_free, m_img_reload, m_bl_start, m_bl_port,
    m_bl_open, m_bl_back, m_bl_end, m_back_enabled, m_pk_start, m_pk_state, m_pk_count, m_pk_name, m_pk_bytes, m_pk_info,
    m_pk_end, m_drive, m_ref_begin, m_ref_text, m_ref_end, m_ref_frame, m_text_key, m_v_open, m_v_place, m_v_close,
    m_v_control, m_v_info, m_v_read_next, m_v_read_answer, m_v_site_next, m_v_site_body, m_v_site_head,
    m_v_site_chunk, m_v_site_end, m_v_site_state, m_v_site_load, m_v_tell, m_pdf_open, m_pdf_pages, m_pdf_size, m_pdf_load, m_pdf_close,
    m_save, m_system_dark, m_font_scale, m_native_pointing, m_keyboard, m_a11y_on, m_a11y_tree, m_set_dark, m_nt_show, m_nt_cancel, m_nt_state, m_nt_text, m_set_sideways, m_set_turnable, m_word_at,
    m_open_url, m_open_tab, m_hold_words, m_clipboard_secret, m_clipboard_secret_off, m_over_done, m_text_scale, m_img_hold, m_img_pump;
static jclass updates_cls, shares_cls, keeps_cls, holds_cls;
static jclass gallery_cls, marks_cls;
static void device_init(JNIEnv *env);  // android_device.h
static jmethodID m_mk_start, m_mk_state, m_mk_png;
static jmethodID m_face_add, m_face_add_bytes, m_face_clear, m_ahead, m_flush;
static jmethodID m_cs_known, m_cs_decode;
static jmethodID m_v_text, m_v_still, m_v_lost;
static jmethodID m_ga_access, m_ga_ask, m_ga_answers, m_ga_read, m_ga_state, m_ga_rows, m_ga_end, m_pk_photo;
static jmethodID m_kp_begin, m_kp_append, m_kp_finish, m_kp_state, m_kp_where, m_kp_end;
static jmethodID m_up_version, m_up_install, m_up_state, m_up_package, m_sh_share, m_sh_in, m_sh_file;
static mb_back_fn back_cb;
static jdoubleArray shape_buf, small_buf;
static jintArray ahead_buf;
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
  m_posted = (*env)->GetStaticMethodID(env, host_cls, "posted", "()V");
  m_wake_after = (*env)->GetStaticMethodID(env, host_cls, "wakeAfter", "(D)V");
  m_set_ime = (*env)->GetStaticMethodID(env, host_cls, "setIme", "(ZDDDDLjava/lang/String;II)V");
  m_clipboard = (*env)->GetStaticMethodID(env, host_cls, "clipboardSet", "(Ljava/lang/String;)V");
  m_text_menu = (*env)->GetStaticMethodID(env, host_cls, "textMenu", "(ZDDDDI)V");
  m_clipboard_secret = (*env)->GetStaticMethodID(env, host_cls, "clipboardSecret", "(Ljava/lang/String;D)V");
  m_clipboard_secret_off = (*env)->GetStaticMethodID(env, host_cls, "clipboardSecretOff", "()V");
  m_log = (*env)->GetStaticMethodID(env, host_cls, "log", "(Ljava/lang/String;)V");
  m_bench = (*env)->GetStaticMethodID(env, host_cls, "benchMode", "()I");
  m_reduce_motion = (*env)->GetStaticMethodID(env, host_cls, "reduceMotion", "()I");
  m_exit = (*env)->GetStaticMethodID(env, host_cls, "exit", "(I)V");
  m_back_enabled = (*env)->GetStaticMethodID(env, host_cls, "backEnabled", "(Z)V");
  m_drive = (*env)->GetStaticMethodID(env, host_cls, "drive", "(ILjava/lang/String;)I");
  m_system_dark = (*env)->GetStaticMethodID(env, host_cls, "systemDark", "()Z");
  m_font_scale = (*env)->GetStaticMethodID(env, host_cls, "fontScale", "()F");
  m_native_pointing = (*env)->GetStaticMethodID(env, host_cls, "nativePointing", "()I");
  m_keyboard = (*env)->GetStaticMethodID(env, host_cls, "keyboard", "()I");
  m_a11y_on = (*env)->GetStaticMethodID(env, host_cls, "a11yOn", "()Z");
  m_a11y_tree = (*env)->GetStaticMethodID(env, host_cls, "a11yTree", "(Ljava/lang/String;)V");
  m_set_dark = (*env)->GetStaticMethodID(env, host_cls, "setDark", "(Z)V");
  m_set_sideways = (*env)->GetStaticMethodID(env, host_cls, "setSideways", "(Z)V");
  m_set_turnable = (*env)->GetStaticMethodID(env, host_cls, "setTurnable", "(Z)Z");
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
  m_glyph_put = (*env)->GetStaticMethodID(env, text_cls, "glyphPut", "(III)V");
  m_generation = (*env)->GetStaticMethodID(env, text_cls, "atlasGeneration", "()I");
  m_text_key = (*env)->GetStaticMethodID(env, text_cls, "textKey", "(Ljava/lang/String;DII)I");
  m_face_add = (*env)->GetStaticMethodID(env, text_cls, "faceAdd", "(ILjava/lang/String;I)Z");
  m_face_add_bytes = (*env)->GetStaticMethodID(env, text_cls, "faceAddBytes", "(I[BI)Z");
  m_face_clear = (*env)->GetStaticMethodID(env, text_cls, "faceClear", "(I)V");
  m_ahead = (*env)->GetStaticMethodID(env, text_cls, "ahead", "([II)V");
  m_flush = (*env)->GetStaticMethodID(env, text_cls, "flush", "()V");
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
  m_pk_info = (*env)->GetStaticMethodID(env, picks_cls, "info", "(II)Ljava/lang/String;");
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
  m_v_place = (*env)->GetStaticMethodID(env, views_cls, "place", "(IFFFFFFFFFFFFZ)V");
  m_v_close = (*env)->GetStaticMethodID(env, views_cls, "close", "(I)V");
  m_v_lost = (*env)->GetStaticMethodID(env, views_cls, "lost", "()V");
  m_v_control = (*env)->GetStaticMethodID(env, views_cls, "control", "(IID)V");
  m_v_info = (*env)->GetStaticMethodID(env, views_cls, "info", "(I[D)I");
  m_v_read_next = (*env)->GetStaticMethodID(env, views_cls, "readNext", "(I[D)I");
  m_v_read_answer = (*env)->GetStaticMethodID(env, views_cls, "readAnswer", "(II[BDZ)V");
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
  ahead_buf = (*env)->NewGlobalRef(env, (*env)->NewIntArray(env, 4096));
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

// a stream's texture (Streams.java; its instances' image is MB_STREAM_TEX + its id: src/hostapi/stream.mbt), and a
// native view's picture (NativeViews.Picture; MB_VIEW_TEX + its id: src/hostapi/host.mbt view_tex_base), below
#define MB_STREAM_TEX 4194304
#define MB_VIEW_TEX 8388608
static GLuint stream_tex(int id);
static void streams_lost(JNIEnv *env);
static GLuint view_tex(int id);
static void view_parts_in(int tid, int32_t start, int32_t end);
static void views_lost(JNIEnv *env);

// The native views kept under the canvas, not drawn in it: a stream's on its layer (kind 4, StreamLayer.java): where
// one shows, the canvas is taken away (gles_render.h: its picture one white texel, its coverage what is drawn), the
// layer under the surface seen there.
#define MB_VIEWS_UNDER 1
static uint8_t *views_under;  // by id
static int views_under_cap;
static GLuint white_tex;  // in the context now; 0 once it is lost
static int view_under(int tid) {
  int id = tid - MB_VIEW_TEX;
  return id > 0 && id < views_under_cap && views_under[id];
}

JNIEXPORT void JNICALL Java_dev_mbui_StreamLayer_under(JNIEnv *env, jclass c, jint id, jboolean on) {
  if (id <= 0) return;
  if (id >= views_under_cap) {
    int cap = views_under_cap ? views_under_cap : 16;
    while (cap <= id) cap *= 2;
    views_under = realloc(views_under, (size_t)cap);
    memset(views_under + views_under_cap, 0, (size_t)(cap - views_under_cap));
    views_under_cap = cap;
  }
  views_under[id] = on ? 1 : 0;
}

static GLuint image_tex(int id) {
  if (id > MB_VIEW_TEX && view_under(id)) {
    if (!white_tex) {
      static const uint8_t white[4] = {255, 255, 255, 255};
      glGenTextures(1, &white_tex);
      glBindTexture(GL_TEXTURE_2D, white_tex);
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, white);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    }
    return white_tex;
  }
  if (id > MB_VIEW_TEX) return view_tex(id - MB_VIEW_TEX);
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
  white_tex = 0;
  (*env)->CallStaticVoidMethod(env, images_cls, m_img_reload);
  streams_lost(env);
  views_lost(env);
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
// Renderer: GLES 3's (gles_render.h, Linux's too), in the GLSurfaceView's context; the glyphs' atlases written by
// MBText (MBText.flush, as a frame is presented).

#include "gles_render.h"

JNIEXPORT void JNICALL Java_dev_mbui_Native_surfaceCreated(JNIEnv *env, jclass c) {
  gl_setup();
  images_lost(env);
}

JNIEXPORT jint JNICALL Java_dev_mbui_Native_atlasTexture(JNIEnv *env, jclass c) { return (jint)atlas; }

JNIEXPORT jint JNICALL Java_dev_mbui_Native_colourAtlasTexture(JNIEnv *env, jclass c) { return (jint)catlas; }

JNIEXPORT void JNICALL Java_dev_mbui_Native_resize(JNIEnv *env, jclass c, jint w, jint h) {
  fb_w = w;
  fb_h = h;
}

// Over another app (OverActivity: Native.overOther): what the app does not paint stays clear, the app under it shows.
JNIEXPORT void JNICALL Java_dev_mbui_Native_overOther(JNIEnv *env, jclass c, jboolean on) { over_other = on ? 1 : 0; }

void mb_host_present(double *buf, int32_t count, double r, double g, double b) {
  // the glyphs placed in the atlas as the frame was painted, uploaded before it is drawn (MBText.flush)
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, text_cls, m_flush);
  gl_present(buf, count, r, g, b);
}

// (MBView.onDrawFrame, GL thread: only a native view's picture changed since the last frame)
JNIEXPORT void JNICALL Java_dev_mbui_Native_redraw(JNIEnv *env, jclass c) { draw_kept(); }

// Without the surface (mbui-render, src/render: started as an app, on the GL thread with the surface's context
// current): gles_render.h's framebuffer of its own, the text at the list's scale (MBText.setScale, not the screen's
// density), the images' uploads done when it asks (Images.hold, mb_render_spin).
double mb_host_now(void);

void mb_render_init_offscreen(double w, double h, double scale) {
  JNIEnv *env = env_();
  gl_offscreen(w, h, scale);
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

// The offscreen frame as a PNG: 1 when written.
int mb_render_snapshot(const char *path) { return target_fb ? gl_png(path, target_fb) : 0; }


// ---------------------------------------------------------------------------
// Java -> MoonBit

JNIEXPORT void JNICALL Java_dev_mbui_Native_start(JNIEnv *env, jclass c) {
  char *argv[] = {"mbui", NULL};
  mbui_main(1, argv);  // runs MoonBit's main, which registers the callbacks
}

// how late the frame before reached the screen, as MBView said with this one (mb_host_frame_late)
static double frame_late;

JNIEXPORT jboolean JNICALL Java_dev_mbui_Native_frame(JNIEnv *env, jclass c, jfloat w, jfloat h,
                                                     jfloat scale, jdouble now, jdouble late) {
  frame_late = late;
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

// What a pointer's event came from (@hostapi.event_finger): a finger, as this system's are; not said.
int32_t mb_host_event_finger(void) { return -1; }

double mb_host_frame_late(void) { return frame_late; }

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
// The app in front or not (@hostapi.set_app_state), as MainActivity tells it (Host.appState), on the GL thread.
static void (*state_cb)(int32_t);
void mb_host_set_app_state(void (*f)(int32_t)) { state_cb = f; }
JNIEXPORT void JNICALL Java_dev_mbui_Native_appState(JNIEnv *env, jclass c, jint state) {
  if (state_cb) state_cb(state);
}

// What the system says between frames (MainActivity: the app back on screen after a while, the device's network
// changed, a link it was opened with), posted on its channel for the app's handler (src/hostapi/system.mbt): the JSON's
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

// how far local time is ahead of UTC then, in minutes (@hostapi.utc_offset_min); a run on its own clock's UTC
int32_t mb_host_utc_offset_min(double at_ms) {
  if (own_clock) return 0;
  time_t s = (time_t)(at_ms / 1000.0);
  struct tm local;
  if (!localtime_r(&s, &local)) return 0;
  return (int32_t)(local.tm_gmtoff / 60);
}

void mb_host_request_frame(void) {
  want_frame = 1;
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, host_cls, m_request_frame);
}

// A message posted from outside the frames (post.h), on whatever thread: the app told on the GL thread, between frames
// (Host.posted: Native.posted, below), and it takes what changes only signals then (ui's messages_between), a frame
// asked for only where something is left for one. A thread the VM does not know is attached for the call and let go
// after.
static void mb_post_wake(void) {
  if (!vm || !host_cls) return;
  JNIEnv *env = NULL;
  int attached = 0;
  if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) {
    if ((*vm)->AttachCurrentThread(vm, &env, NULL) != JNI_OK) return;
    attached = 1;
  }
  (*env)->CallStaticVoidMethod(env, host_cls, m_posted);
  if ((*env)->ExceptionCheck(env)) (*env)->ExceptionClear(env);
  if (attached) (*vm)->DetachCurrentThread(vm);
}

// Whether the system is in night mode (@hostapi.system_dark), as MainActivity keeps it (Host.systemDark: the
// configuration's uiMode, a frame asked for when it changes).
int32_t mb_host_system_dark(void) {
  JNIEnv *env = env_();
  return (*env)->CallStaticBooleanMethod(env, host_cls, m_system_dark) ? 1 : 0;
}

// Whether an accessibility service is on (@hostapi.a11y_on: Host.a11yOn, AccessibilityManager's say, a frame asked as it
// changes), and what the app's widgets are now for it (@hostapi.a11y_tree: MBView's A11y, the view's virtual nodes).
int32_t mb_host_a11y_on(void) {
  JNIEnv *env = env_();
  return (*env)->CallStaticBooleanMethod(env, host_cls, m_a11y_on) ? 1 : 0;
}

void mb_host_a11y_tree(moonbit_string_t s) {
  JNIEnv *env = env_();
  jstring j = jstr(env, s);
  (*env)->CallStaticVoidMethod(env, host_cls, m_a11y_tree, j);
  (*env)->DeleteLocalRef(env, j);
}

// How much bigger the system's words setting makes words (@hostapi.font_scale), as MainActivity keeps it (Host.fontScale:
// the configuration's fontScale, a frame asked for when it changes).
double mb_host_font_scale(void) {
  JNIEnv *env = env_();
  return (double)(*env)->CallStaticFloatMethod(env, host_cls, m_font_scale);
}

// What the app was started to be used with (@hostapi.native_pointing): Host.nativePointing (a mouse or a touchpad among
// the input devices: keyboard and mouse; else touch).
int32_t mb_host_native_pointing(void) {
  JNIEnv *env = env_();
  return (int32_t)(*env)->CallStaticIntMethod(env, host_cls, m_native_pointing);
}

// Whether a keyboard is at hand (@hostapi.keyboard): Host.keyboard (a physical keyboard of letters among the input
// devices; a frame asked for as one comes or goes).
int32_t mb_host_keyboard(void) {
  JNIEnv *env = env_();
  return (int32_t)(*env)->CallStaticIntMethod(env, host_cls, m_keyboard);
}

// The app drawn dark or light (@hostapi.set_dark): the status and navigation bars' icons light on it or dark (Host.setDark).
void mb_host_set_dark(int32_t dark) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, host_cls, m_set_dark, (jboolean)(dark != 0));
}

// Turned sideways for a film (@hostapi.set_sideways): landscape and the system bars away, or upright (Host.setSideways).
void mb_host_set_sideways(int32_t on) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, host_cls, m_set_sideways, (jboolean)(on != 0));
}

// A phone held upright let turn as held, or upright only again (@hostapi.set_turnable, Host.setTurnable): whether it
// is one held upright.
int32_t mb_host_set_turnable(int32_t on) {
  JNIEnv *env = env_();
  return (*env)->CallStaticBooleanMethod(env, host_cls, m_set_turnable, (jboolean)(on != 0)) ? 1 : 0;
}

// The word around an offset as ICU finds it (Host.wordAt, @hostapi.word_at): start × 2³² + end, or -1.
double mb_host_word_at(moonbit_string_t text, int32_t off) {
  JNIEnv *env = env_();
  jstring t = jstr(env, text);
  jdouble v = (*env)->CallStaticDoubleMethod(env, host_cls, m_word_at, t, (jint)off);
  (*env)->DeleteLocalRef(env, t);
  return v;
}

// A URL handed to the system (Host.openUrl, @hostapi.open_url): ACTION_VIEW.
int32_t mb_host_open_url(moonbit_string_t url) {
  JNIEnv *env = env_();
  jstring u = jstr(env, url);
  jboolean ok = (*env)->CallStaticBooleanMethod(env, host_cls, m_open_url, u);
  (*env)->DeleteLocalRef(env, u);
  return ok ? 1 : 0;
}

// The app over another app done (Host.overDone, @hostapi.over_done): back to it, or on into the app's own activity.
void mb_host_over_done(int32_t open_app) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, host_cls, m_over_done, open_app ? JNI_TRUE : JNI_FALSE);
}

// A page in a browser's tab over the app (BrowserLogin.openTab, @hostapi.open_tab): a Custom Tab, ACTION_VIEW where no
// browser takes one.
int32_t mb_host_open_tab(moonbit_string_t url) {
  JNIEnv *env = env_();
  jstring u = jstr(env, url);
  jboolean ok = (*env)->CallStaticBooleanMethod(env, login_cls, m_open_tab, u);
  (*env)->DeleteLocalRef(env, u);
  return ok ? 1 : 0;
}

// What the notice that holds the app up while it listens for a browser says (LoginService.words, @hostapi.hold_words).
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

// A package handed to the system's installer (Updates.installPackage, @hostapi.install_package); what comes of it is
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

// A face's file (style.mbt; MBText.faceAdd): false when Android could not make a typeface of it.
int32_t mb_host_face_add(int32_t face, moonbit_string_t path, int32_t weight) {
  JNIEnv *env = env_();
  jstring s = jstr(env, path);
  jboolean ok = (*env)->CallStaticBooleanMethod(env, text_cls, m_face_add, face, s, weight);
  (*env)->DeleteLocalRef(env, s);
  return ok ? 1 : 0;
}

int32_t mb_host_face_add_bytes(int32_t face, moonbit_bytes_t data, int32_t weight) {
  JNIEnv *env = env_();
  jbyteArray b = jbytes(env, data);
  jboolean ok = (*env)->CallStaticBooleanMethod(env, text_cls, m_face_add_bytes, face, b, weight);
  (*env)->DeleteLocalRef(env, b);
  return ok ? 1 : 0;
}

void mb_host_face_clear(int32_t face) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, text_cls, m_face_clear, face);
}

void mb_host_glyph(int32_t key, double *out) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, text_cls, m_glyph, key, small_buf);
  (*env)->GetDoubleArrayRegion(env, small_buf, 0, 7, out);
}

// The glyph drawn last put in the atlas at x, y (uploaded with the frame's others before it is drawn: MBText.flush).
void mb_host_glyph_put(int32_t key, int32_t x, int32_t y) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, text_cls, m_glyph_put, key, x, y);
}

// The side of the words' atlas, or of colour glyphs' (MB_ATLAS above).
int32_t mb_host_atlas_size(int32_t colour) { return colour ? MB_ATLAS_COLOR : MB_ATLAS; }

// The glyphs shaped and not drawn yet (text.mbt glyphs_ahead): MBText draws them on a thread of its own, for glyph to
// find drawn.
void mb_host_glyphs_ahead(int32_t *keys, int32_t n) {
  JNIEnv *env = env_();
  if (n > 4096) n = 4096;
  if (n <= 0) return;
  (*env)->SetIntArrayRegion(env, ahead_buf, 0, n, (const jint *)keys);
  (*env)->CallStaticVoidMethod(env, text_cls, m_ahead, ahead_buf, n);
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

// The system's floating text menu over a field's words, or put away (Host.textMenu: ActionMode.TYPE_FLOATING).
// no menu bar of the app's here
void mb_host_edit_can(int32_t can) { (void)can; }

void mb_host_text_menu(int32_t shown, double x, double y, double w, double h, int32_t can) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, host_cls, m_text_menu, shown ? JNI_TRUE : JNI_FALSE, x, y, w, h, can);
}

// A picture on the clipboard (@hostapi.clipboard_set_image): none here (Android's clipboard takes a picture only as a
// content URI another app can read).
void mb_host_clipboard_image(moonbit_bytes_t data) { (void)data; }

void mb_host_clipboard_set(moonbit_string_t s) {
  JNIEnv *env = env_();
  jstring j = jstr(env, s);
  (*env)->CallStaticVoidMethod(env, host_cls, m_clipboard, j);
  (*env)->DeleteLocalRef(env, j);
}

// A secret on the clipboard (Host.clipboardSecret): marked sensitive; taken off as the app asks.
void mb_host_clipboard_secret(moonbit_string_t s, double clear_ms) {
  JNIEnv *env = env_();
  jstring j = jstr(env, s);
  (*env)->CallStaticVoidMethod(env, host_cls, m_clipboard_secret, j, clear_ms);
  (*env)->DeleteLocalRef(env, j);
}

// The last secret copied taken off unless something else was copied since (Host.clipboardSecretOff).
void mb_host_clipboard_secret_off(void) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, host_cls, m_clipboard_secret_off);
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
enum { MB_OUTSIDE_IMAGE = 1, MB_OUTSIDE_VIEW = 2, MB_OUTSIDE_POSTED = 11, MB_OUTSIDE_STREAMED = 12 };
static void (*outside_cb)(int32_t, int32_t, int32_t);
int32_t mb_host_set_outside(void (*f)(int32_t, int32_t, int32_t)) {
  outside_cb = f;
  return 1;
}

JNIEXPORT void JNICALL Java_dev_mbui_Native_outside(JNIEnv *env, jclass c, jint kind, jint id, jint state) {
  if (outside_cb) outside_cb(kind, id, state);
}

// Something posted since (mb_post_wake, Host.posted: on the GL thread, between frames): the app told (MB_OUTSIDE_POSTED),
// or, before it has said where it is told, a frame asked for.
JNIEXPORT void JNICALL Java_dev_mbui_Native_posted(JNIEnv *env, jclass c) {
  if (outside_cb) outside_cb(MB_OUTSIDE_POSTED, 0, 0);
  else mb_host_request_frame();
}

// How many of the app's asks are not answered yet, and what they are, as the frame just built left it
// (host_native.mbt's frame_awaiting): a run to a declared moment keeps its clock still while any is (MBView's
// shotFrame, Native.awaiting).
static int awaiting_n;
// (in a run to a declared moment, what it awaits said on the log as it changes: a picture whose clock stands still is
// told by what it stands for, not left to a timeout)
static char awaiting_said[512];
void mb_host_frame_awaiting(int32_t awaiting, moonbit_string_t what) {
  awaiting_n = awaiting;
  if (!own_clock) return;
  char now[512];
  int n = Moonbit_array_length(what), m = 0;
  for (int i = 0; i < n && m < (int)sizeof now - 1; i++) now[m++] = what[i] < 128 ? (char)what[i] : '?';
  now[m] = 0;
  if (strcmp(now, awaiting_said) == 0) return;
  memcpy(awaiting_said, now, (size_t)m + 1);
  LOG("shot: awaiting %d: %s", awaiting, now);
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

// MainActivity sets the intent's `env` extras as the process's environment before the app starts. A release build
// takes no intent's on a phone (MainActivity.testHooks): the frame probe's switches (MBUI_PROBE, MBUI_PROBE_DAMAGE:
// app.mbt's slow_probe, on the log) are read from a debug property besides, `debug.mbui.probe` and the like, which only
// adb sets (`adb shell setprop debug.mbui.probe 1`, the app started anew): how fast a phone draws, asked of that phone.
moonbit_string_t mb_host_env(moonbit_string_t name) {
  int n = Moonbit_array_length(name);
  char k[256];
  if (n >= (int)sizeof k) n = sizeof k - 1;
  for (int i = 0; i < n; i++) k[i] = name[i] < 128 ? (char)name[i] : '?';
  k[n] = 0;
  const unsigned char *v = (const unsigned char *)getenv(k);
  char prop[PROP_VALUE_MAX];
  if (!v && strncmp(k, "MBUI_PROBE", 10) == 0) {
    char pn[64] = "debug.mbui.";
    size_t at = strlen(pn);
    for (const char *c = k + 5; *c && at + 1 < sizeof pn; c++)
      pn[at++] = (*c >= 'A' && *c <= 'Z') ? (char)(*c - 'A' + 'a') : *c;
    pn[at] = 0;
    if (__system_property_get(pn, prop) > 0) v = (const unsigned char *)prop;
  }
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

// The performance record (@hostapi.perf_state): none kept here (iOS keeps one, ios_app.m).
int32_t mb_host_perf_state(void) { return -1; }
void mb_host_set_perf(int32_t on) { (void)on; }
void mb_host_perf_line(moonbit_string_t line) { (void)line; }
moonbit_string_t mb_host_perf_where(void) { return moonbit_make_string_raw(0); }
double mb_host_perf_size(void) { return 0; }

double mb_host_gpu_ms(void) { return -1; }

// The CPU's time the whole process has had, every thread's (@hostapi.cpu_ms: MBUI_PROBE's share of a CPU), in ms.
double mb_host_cpu_ms(void) {
  struct rusage u;
  if (getrusage(RUSAGE_SELF, &u) != 0) return -1;
  return (u.ru_utime.tv_sec + u.ru_stime.tv_sec) * 1000.0 + (u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1000.0;
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

// A ready image's pixels read back from its texture through a framebuffer of its own (premultiplied RGBA, as
// uploaded), rows from the top (as the bitmap's were uploaded).
int32_t mb_host_image_pixels(int32_t id, moonbit_bytes_t out) {
  if (id <= 0 || id >= nimgs) return 0;
  mb_image *im = &imgs[id];
  if (im->state != 1 || !im->tex) return 0;
  if ((size_t)Moonbit_array_length(out) < (size_t)im->w * im->h * 4) return 0;
  GLint was = 0;
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &was);
  GLuint fb = 0;
  glGenFramebuffers(1, &fb);
  glBindFramebuffer(GL_FRAMEBUFFER, fb);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, im->tex, 0);
  int ok = glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
  if (ok) {
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0, 0, im->w, im->h, GL_RGBA, GL_UNSIGNED_BYTE, out);
  }
  glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)was);
  glDeleteFramebuffers(1, &fb);
  return ok;
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

// a file held (Picks.java: too big to read whole): its id, size and address, a tab between; "" for one read whole
moonbit_string_t mb_host_pick_info(int32_t id, int32_t i) {
  JNIEnv *env = env_();
  jstring s = (jstring)(*env)->CallStaticObjectMethod(env, picks_cls, m_pk_info, id, i);
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
// Native views in the canvas (host_native.mbt `view_*`): dev.mbui.NativeViews keeps them in a layer under the GL
// surface, a video player (Media3's ExoPlayer, its bytes read through the app) or a WebView, each drawing into a
// picture of its own (NativeViews.Picture), which the frame draws where the app paints the view (kind 9, its image
// MB_VIEW_TEX + its id: present). Called on the GL thread; NativeViews moves to the main thread what must run there.

static GLuint *view_texs;  // by id
// the part of its content each one's picture is, by id: its top and its height, of the content's (0 1: all of it)
static float *view_parts;
static int view_cap;

static GLuint view_tex(int id) { return id > 0 && id < view_cap ? view_texs[id] : 0; }

// room for view `id`'s (id > 0)
static void views_hold(int id) {
  if (id < view_cap) return;
  int cap = view_cap ? view_cap : 16;
  while (cap <= id) cap *= 2;
  view_texs = realloc(view_texs, (size_t)cap * sizeof *view_texs);
  memset(view_texs + view_cap, 0, (size_t)(cap - view_cap) * sizeof *view_texs);
  view_parts = realloc(view_parts, (size_t)cap * 2 * sizeof *view_parts);
  for (int i = view_cap; i < cap; i++) {
    view_parts[i * 2] = 0.0f;
    view_parts[i * 2 + 1] = 1.0f;
  }
  view_cap = cap;
}

// The run of instances [start, end) showing view picture `tid` (MB_VIEW_TEX + its id), in the buffer bound: where its
// picture is a part of its content (a tall page's, NativeViews.Page), each one's c2 (the part of the content where it
// shows) made the part of the picture there; the shader draws nothing where that is outside the picture.
static void view_parts_in(int tid, int32_t start, int32_t end) {
  int id = tid - MB_VIEW_TEX;
  if (id <= 0 || id >= view_cap) return;
  float top = view_parts[id * 2], height = view_parts[id * 2 + 1];
  if ((top == 0.0f && height == 1.0f) || height <= 0.0f) return;
  for (int32_t i = start; i < end; i++) {
    const float *c2 = fbuf + (size_t)i * MB_INST + 12;
    float in[4] = {c2[0], (c2[1] - top) / height, c2[2], c2[3] / height};
    glBufferSubData(GL_ARRAY_BUFFER, (GLintptr)(((size_t)i * MB_INST + 12) * sizeof(float)), sizeof in, in);
  }
}

static void views_lost(JNIEnv *env) {
  for (int i = 0; i < view_cap; i++) view_texs[i] = 0;
  (*env)->CallStaticVoidMethod(env, views_cls, m_v_lost);
  if ((*env)->ExceptionCheck(env)) {
    (*env)->ExceptionDescribe(env);
    (*env)->ExceptionClear(env);
  }
}

JNIEXPORT void JNICALL Java_dev_mbui_NativeViews_texture(JNIEnv *env, jclass c, jint id, jint tex) {
  if (id <= 0) return;
  views_hold(id);
  view_texs[id] = (GLuint)tex;
}

JNIEXPORT void JNICALL Java_dev_mbui_NativeViews_part(JNIEnv *env, jclass c, jint id, jfloat top, jfloat height) {
  if (id <= 0) return;
  views_hold(id);
  view_parts[id * 2] = top;
  view_parts[id * 2 + 1] = height;
}

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
                        double cy1, double r0, double r1, double r2, double r3, int32_t shown) {
  JNIEnv *env = env_();
  (*env)->CallStaticVoidMethod(env, views_cls, m_v_place, id, (jfloat)x, (jfloat)y, (jfloat)w, (jfloat)h,
                               (jfloat)cx0, (jfloat)cy0, (jfloat)cx1, (jfloat)cy1, (jfloat)r0, (jfloat)r1,
                               (jfloat)r2, (jfloat)r3, shown ? JNI_TRUE : JNI_FALSE);
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

void mb_host_view_read_answer(int32_t id, int32_t req, moonbit_bytes_t data, double total, int32_t more) {
  JNIEnv *env = env_();
  jbyteArray b = jbytes(env, data);
  (*env)->CallStaticVoidMethod(env, views_cls, m_v_read_answer, id, req, b, total, (jboolean)(more != 0));
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

// The system's own bars (@hostapi.nav_bar): none here, the app draws its own.
int32_t mb_host_nav_bar(moonbit_string_t spec) {
  (void)spec;
  return 0;
}

int32_t mb_host_nav_able(void) { return 0; }

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

// The desktop's window and pointer (@hostapi.window_setup, window_inset, window_drag, set_cursor): no window to size
// or move here, no pointer to shape.
// The window held till the app shows it (@hostapi.window_hold): the system shows the app's own here, as it opens.
void mb_host_window_hold(void) {}
void mb_host_window_show(void) {}

void mb_host_window_setup(double min_w, double min_h, double w, double h, int32_t inset) {
  (void)min_w; (void)min_h; (void)w; (void)h; (void)inset;
}
int32_t mb_host_window_inset(void) { return 0; }
// A window filling the screen (@hostapi.full_screen): not one of this host's.
int32_t mb_host_full_screen(void) { return 0; }
void mb_host_set_full_screen(int32_t on) { (void)on; }
// How round the window's corners are (@hostapi.window_corner): the app fills the screen, whose own corners (40 and
// more) are rounder than anything by them could follow within the corner rule's ranges: said as none.
double mb_host_window_corner(void) { return 0; }
double mb_host_window_corner_at(int k) { (void)k; return 0; }
void mb_host_window_drag(void) {}

// The window's own buttons, the app's to draw where the system draws none (@hostapi.window_act, window_zoomed,
// window_snap, window_snap_state): Windows' alone; none here.
void mb_host_window_act(int32_t what) { (void)what; }
int32_t mb_host_window_zoomed(void) { return 0; }
void mb_host_window_snap(double x, double y, double w, double h) { (void)x, (void)y, (void)w, (void)h; }
int32_t mb_host_window_snap_state(void) { return 0; }
// A window of the app's own beside this one (@hostapi.window_opens, window_open): a desktop's; none here.
int32_t mb_host_window_opens(void) { return 0; }
int32_t mb_host_window_open(moonbit_string_t what) { (void)what; return 0; }
void mb_host_set_cursor(int32_t kind) { (void)kind; }
void mb_host_set_badge(int32_t n) { (void)n; }
// The menu bar (@hostapi.menu_setup): none here.
void mb_host_menu_setup(moonbit_string_t json) { (void)json; }
// (this machine's station: managed from the macOS app only)
moonbit_string_t mb_host_local_station(void) { return moonbit_make_string_raw(0); }
// (the phone's faces are the files given: no family of the machine's, no list of them)
int32_t mb_host_face_add_family(int32_t face, moonbit_string_t family) { (void)face; (void)family; return 0; }
moonbit_string_t mb_host_local_font_families(void) { return moonbit_make_string_raw(0); }
void mb_host_local_station_act(moonbit_string_t a) { (void)a; }
// The keys held now (@hostapi.mods_held): none read here.
int32_t mb_host_mods_held(void) { return 0; }

// ---------------------------------------------------------------------------
// Streams (src/hostapi/stream.mbt): dev.mbui.Streams decodes (MediaCodec, BitmapFactory) and draws each frame the app
// shows into a texture of its own on the GL thread, told here (Streams.texture) for the renderer to draw the stream's
// instances with. What MediaCodec takes of H.264 is made by avc.h, the conversion the hosts share.

#include "avc.h"

static jclass streams_cls;
static jmethodID m_st_open, m_st_h264, m_st_frame, m_st_jpeg, m_st_next, m_st_show, m_st_close, m_st_here, m_st_lost, m_st_codec;
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
    m_st_codec = (*env)->GetStaticMethodID(env, streams_cls, "codec", "(ILjava/lang/String;[B)V");
  }
  return env;
}

static GLuint stream_tex(int id) { return id > 0 && id < stream_cap ? stream_texs[id] : 0; }
static void unroute(int32_t sid, int what);

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
  unroute(id, 3);
  JNIEnv *env = streams_env();
  (*env)->CallStaticVoidMethod(env, streams_cls, m_st_close, id);
  streams_threw(env);
}

// (its H.264 decoder driven by the framework: what MediaCodec and the SurfaceTexture say goes up as events, what to do
// comes down here; @ui's stream_feed.mbt)
int32_t mb_host_stream_feeds(void) { return 1; }

void mb_host_stream_codec(int32_t id, moonbit_string_t cmd, moonbit_bytes_t data) {
  JNIEnv *env = streams_env();
  jstring c = jstr(env, cmd);
  jbyteArray b = jbytes(env, data);
  (*env)->CallStaticVoidMethod(env, streams_cls, m_st_codec, id, c, b);
  streams_threw(env);
  (*env)->DeleteLocalRef(env, b);
  (*env)->DeleteLocalRef(env, c);
}

int32_t mb_host_h264_here(void) {
  JNIEnv *env = streams_env();
  jboolean here = (*env)->CallStaticBooleanMethod(env, streams_cls, m_st_here);
  return !streams_threw(env) && here ? 1 : 0;
}

// The device beyond the window (device.mbt): a key catcher, the soft keyboard, the clipboard, awake, haptics.
#include "android_device.h"

// Whether a switch of a run's says no (MBUI_<NAME>=0, or the debug property adb sets, `debug.mbui.<name>` 0: a phone's
// release build takes no environment of a run's): stream layers and H.265 turned off to compare, the app as before.
static int switched_off(const char *env, const char *prop) {
  const char *v = getenv(env);
  char p[PROP_VALUE_MAX];
  if (!v && __system_property_get(prop, p) > 0) v = p;
  return v && strcmp(v, "0") == 0;
}

// A stream's sound: played by an AudioTrack of its own (Streams.Sound), the app's packets and its route's alike.
static jmethodID m_st_audio;
int32_t mb_host_stream_audio_here(void) { return switched_off("MBUI_STREAM_AUDIO", "debug.mbui.stream_audio") ? 0 : 1; }
void mb_host_stream_audio(int32_t id, moonbit_bytes_t data) {
  JNIEnv *env = streams_env();
  if (!m_st_audio) m_st_audio = (*env)->GetStaticMethodID(env, streams_cls, "audio", "(I[B)V");
  // (stopped: what its route plays stops with it, until the app routes it again)
  if (Moonbit_array_length(data) == 0) unroute(id, 2);
  jbyteArray b = jbytes(env, data);
  (*env)->CallStaticVoidMethod(env, streams_cls, m_st_audio, id, b);
  streams_threw(env);
  (*env)->DeleteLocalRef(env, b);
}

// ---- streams on a layer of the system's (StreamLayer.java: @hostapi.stream_layers, native views of kind 4) ----

static jclass layers_cls;
static jmethodID m_sl_here, m_sl_hevc_here, m_sl_pointer, m_sl_pointer_at, m_st_hevc, m_st_direct;
static JNIEnv *layers_env(void) {
  JNIEnv *env = streams_env();
  if (!layers_cls) {
    layers_cls = (*env)->NewGlobalRef(env, (*env)->FindClass(env, "dev/mbui/StreamLayer"));
    m_sl_here = (*env)->GetStaticMethodID(env, layers_cls, "here", "()Z");
    m_sl_hevc_here = (*env)->GetStaticMethodID(env, layers_cls, "hevcHere", "()Z");
    m_sl_pointer = (*env)->GetStaticMethodID(env, layers_cls, "pointer", "(I[BFFFF)V");
    m_sl_pointer_at = (*env)->GetStaticMethodID(env, layers_cls, "pointerAt", "(IDDZ)V");
    m_st_hevc = (*env)->GetStaticMethodID(env, streams_cls, "hevc", "(I[BII)V");
    m_st_direct = (*env)->GetStaticMethodID(env, streams_cls, "direct", "(IJZD[B)V");
  }
  return env;
}

// A system video layer here where Android has what it takes (API 33: a SurfaceControl's crop, position and scale), an
// H.264 decoder and the switch is not off (debug.mbui.stream_layers 0): a remote screen's frames decoded by MediaCodec
// straight onto a layer under the canvas, nothing of the app's built or drawn for them; else drawn by the app as before.
int32_t mb_host_stream_layers(void) {
  static int known = -1;
  if (known < 0) {
    if (switched_off("MBUI_STREAM_LAYERS", "debug.mbui.stream_layers")) {
      known = 0;
    } else {
      JNIEnv *env = layers_env();
      jboolean here = (*env)->CallStaticBooleanMethod(env, layers_cls, m_sl_here);
      known = !streams_threw(env) && here ? 1 : 0;
    }
  }
  return known;
}

// The station's pointer over stream `id`'s picture on its layer: a layer of its own over it (StreamLayer.pointer).
void mb_host_stream_pointer(int32_t id, moonbit_bytes_t png, double w, double h, double hx, double hy) {
  if (!mb_host_stream_layers()) return;
  JNIEnv *env = layers_env();
  jbyteArray b = jbytes(env, png);
  (*env)->CallStaticVoidMethod(env, layers_cls, m_sl_pointer, id, b, (jfloat)w, (jfloat)h, (jfloat)hx, (jfloat)hy);
  streams_threw(env);
  (*env)->DeleteLocalRef(env, b);
}

void mb_host_stream_pointer_at(int32_t id, double x, double y, int32_t shown) {
  if (!mb_host_stream_layers()) return;
  JNIEnv *env = layers_env();
  (*env)->CallStaticVoidMethod(env, layers_cls, m_sl_pointer_at, id, x, y, shown ? JNI_TRUE : JNI_FALSE);
  streams_threw(env);
}

// H.265 where streams show on their layers (decoded there by the host's own MediaCodec, not the framework's feed) and
// the device decodes it in its hardware; the switch not off (debug.mbui.h265 0).
int32_t mb_host_h265_here(void) {
  static int known = -1;
  if (known < 0) {
    if (!mb_host_stream_layers() || switched_off("MBUI_H265", "debug.mbui.h265")) {
      known = 0;
    } else {
      JNIEnv *env = layers_env();
      jboolean here = (*env)->CallStaticBooleanMethod(env, layers_cls, m_sl_hevc_here);
      known = !streams_threw(env) && here ? 1 : 0;
    }
  }
  return known;
}

void mb_host_stream_hevc(int32_t id, moonbit_bytes_t hvcc, int32_t w, int32_t h) {
  JNIEnv *env = layers_env();
  jbyteArray b = jbytes(env, hvcc);
  (*env)->CallStaticVoidMethod(env, streams_cls, m_st_hevc, id, b, w, h);
  streams_threw(env);
  (*env)->DeleteLocalRef(env, b);
}

// ---- routes: a remote screen's frames straight from the app's engine (apple_stream.m's, the same) ----
//
// Where the app's engine reads a remote screen itself (still.fail's shell: mb_stream_route_take, handed over by the
// app's src/sfcore/android_engine.c), the frames of the view the app routed to a stream (@hostapi.stream_direct) come
// here from the engine's threads, not through the app's queue: handed to the stream's own decoder (Streams.direct),
// each decoded one shown on its layer at once and acknowledged to its sender (mb_stream_route_acks), nothing of the
// app's run. A config stops the route until the app has taken it and routes it again.

typedef struct {
  uint64_t route, seq, used;
  int32_t video, audio;
} mb_route;
#define MB_ROUTES 8
static mb_route routes[MB_ROUTES];
static uint64_t routes_used;
static pthread_mutex_t routes_lock = PTHREAD_MUTEX_INITIALIZER;
static int (*route_ack)(double route, double ts);

// (under routes_lock) route's entry; made where `make` (in a free one, else one routing nothing used least lately)
static mb_route *route_at(uint64_t route, int make) {
  mb_route *empty = NULL, *old = NULL;
  for (int i = 0; i < MB_ROUTES; i++) {
    mb_route *r = &routes[i];
    if (r->route == route && route) {
      r->used = ++routes_used;
      return r;
    }
    if (!r->route) {
      if (!empty) empty = r;
    } else if (!r->video && !r->audio && (!old || r->used < old->used)) {
      old = r;
    }
  }
  if (!make || !route) return NULL;
  mb_route *r = empty ? empty : old;
  if (r) *r = (mb_route){route, 0, ++routes_used, 0, 0};
  return r;
}

// Stream sid no longer where a route's frames (`what` 1) or sound (2) go.
static void unroute(int32_t sid, int what) {
  pthread_mutex_lock(&routes_lock);
  for (int i = 0; i < MB_ROUTES; i++) {
    if ((what & 1) && routes[i].video == sid) routes[i].video = 0;
    if ((what & 2) && routes[i].audio == sid) routes[i].audio = 0;
  }
  pthread_mutex_unlock(&routes_lock);
}

void mb_stream_route_acks(int (*ack)(double route, double ts)) { route_ack = ack; }

// (Streams' decoder thread) whether route's frames still go to stream sid, and frame ts of route acknowledged
JNIEXPORT jboolean JNICALL Java_dev_mbui_Streams_routed(JNIEnv *env, jclass c, jlong route, jint sid) {
  pthread_mutex_lock(&routes_lock);
  mb_route *r = route_at((uint64_t)route, 0);
  int on = r && r->video == sid;
  pthread_mutex_unlock(&routes_lock);
  return on ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL Java_dev_mbui_Streams_routeAck(JNIEnv *env, jclass c, jlong route, jdouble ts) {
  if (route_ack) route_ack((double)route, ts);
}

// An engine's thread this attached to the VM is detached as it ends (a thread that ends attached aborts the process).
static pthread_key_t route_attached;
static pthread_once_t route_attached_once = PTHREAD_ONCE_INIT;
static void route_detach(void *unused) {
  (void)unused;
  (*vm)->DetachCurrentThread(vm);
}
static void route_attached_key(void) { pthread_key_create(&route_attached, route_detach); }

int mb_stream_route_take(uint64_t route, int kind, int key, uint64_t seq, uint64_t ts, const uint8_t *bytes, size_t len) {
  int32_t sid = 0;
  pthread_mutex_lock(&routes_lock);
  mb_route *r = route_at(route, 1);
  if (r) {
    r->seq = seq;
    // (a config: the app's to take, and what follows it, until it routes them again)
    if (kind == 1) r->video = 0;
    else if (kind == 5) r->audio = 0;
    else if (kind == 2) sid = r->video;
    else if (kind == 6 && len == 3840) sid = r->audio;
  }
  pthread_mutex_unlock(&routes_lock);
  if (!sid || !vm || !streams_cls || !m_st_direct || !m_st_audio || len > 0x7fffffff) return 0;
  JNIEnv *env = NULL;
  if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) {
    if ((*vm)->AttachCurrentThread(vm, &env, NULL) != JNI_OK) return 0;
    pthread_once(&route_attached_once, route_attached_key);
    pthread_setspecific(route_attached, (void *)1);
  }
  jbyteArray b = (*env)->NewByteArray(env, (jsize)len);
  if (!b) {
    if ((*env)->ExceptionCheck(env)) (*env)->ExceptionClear(env);
    return 0;
  }
  (*env)->SetByteArrayRegion(env, b, 0, (jsize)len, (const jbyte *)bytes);
  if (kind == 6) (*env)->CallStaticVoidMethod(env, streams_cls, m_st_audio, sid, b);
  else (*env)->CallStaticVoidMethod(env, streams_cls, m_st_direct, sid, (jlong)route, key ? JNI_TRUE : JNI_FALSE, (jdouble)ts, b);
  int took = !(*env)->ExceptionCheck(env);
  if (!took) (*env)->ExceptionClear(env);
  (*env)->DeleteLocalRef(env, b);
  return took;
}

// The app's (GL thread): stream sid takes route's frames (`what` 1) and sound (2) from now, where the last record
// offered by it is the `after`th (nothing of it left in the app's queue); those not asked no longer.
void mb_host_stream_direct(int32_t sid, double route, double after, int32_t what) {
  unroute(sid, ~what & 3);
  if (!(what & 3) || route < 1) return;
  // (the frames only to a stream decoded on its layer: Streams.Own)
  if (!mb_host_stream_layers()) what &= ~1;
  if (!(what & 3)) return;
  JNIEnv *env = layers_env();
  if (!m_st_audio) m_st_audio = (*env)->GetStaticMethodID(env, streams_cls, "audio", "(I[B)V");
  pthread_mutex_lock(&routes_lock);
  mb_route *r = route_at((uint64_t)route, 0);
  if (r && (double)r->seq == after) {
    if (what & 1) r->video = sid;
    if (what & 2) r->audio = sid;
  }
  pthread_mutex_unlock(&routes_lock);
}
