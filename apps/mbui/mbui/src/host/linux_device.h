// The device beyond the window on Linux (src/hostapi/device.mbt): a key catcher's keys, the clipboard read (words, a
// picture as a PNG, files a file manager copied: GTK's clipboard, read as the system hands them over) and written. No
// soft keyboard's height (0), no haptics, the display not kept on yet. Included by linux_app.c before its keys (its
// area, ime_active, marked_len, mods_of, schedule above).

// ---- a key catcher (@hostapi.key_catch) ----

static int key_catching;

void mb_host_key_catch(int32_t on) { key_catching = on != 0; }

// The framework's code of a named key (src/ui/desktop.mbt), 0 for another.
static int named_key(guint keyval) {
  switch (keyval) {
    case GDK_KEY_BackSpace: return 1;
    case GDK_KEY_Delete: case GDK_KEY_KP_Delete: return 2;
    case GDK_KEY_Left: case GDK_KEY_KP_Left: return 3;
    case GDK_KEY_Right: case GDK_KEY_KP_Right: return 4;
    case GDK_KEY_Up: case GDK_KEY_KP_Up: return 5;
    case GDK_KEY_Down: case GDK_KEY_KP_Down: return 6;
    case GDK_KEY_Return: case GDK_KEY_KP_Enter: case GDK_KEY_ISO_Enter: return 7;
    case GDK_KEY_Home: case GDK_KEY_KP_Home: return 8;
    case GDK_KEY_End: case GDK_KEY_KP_End: return 9;
    case GDK_KEY_Page_Up: case GDK_KEY_KP_Page_Up: return 15;
    case GDK_KEY_Page_Down: case GDK_KEY_KP_Page_Down: return 16;
    case GDK_KEY_Escape: return 17;
    case GDK_KEY_Tab: case GDK_KEY_ISO_Left_Tab: case GDK_KEY_KP_Tab: return 18;
    default: return 0;
  }
}

// The character a key types (lower case), 0 for none: the key's own without Shift (what is printed on it).
static int key_char(guint keyval) {
  gunichar c = gdk_keyval_to_unicode(gdk_keyval_to_lower(keyval));
  return c >= 32 && c != 0x7F ? (int)c : 0;
}

// A key down with the focus a key catcher's: the named keys, a character with Ctrl, Alt or Super held as its key
// (1000 + it, lower case; Ctrl with Alt is AltGr, a character typed). 0: not the catcher's as a key.
static int catch_key(guint keyval, int mods) {
  int code = named_key(keyval);
  if (!code && (mods & (2 | 4 | 8)) && (mods & (2 | 4)) != (2 | 4)) {
    int ch = key_char(keyval);
    if (ch) code = 1000 + ch;
  }
  if (code) mb_cb.key(code, mods);
  return code;
}

// ---- the soft keyboard: none told here ----

double mb_host_ime_inset(void) { return 0; }

int32_t mb_host_copy_shown(void) { return 0; }

// ---- the clipboard read ----

enum { CLIP_NONE = 0, CLIP_PNG = 1, CLIP_TOO_LARGE = 2, CLIP_UNREADABLE = 3 };
#define CLIP_READS 8
typedef struct {
  int32_t id;
  int waiting;  // the reads not answered yet
  int told;
  int picture;
  gunichar2 *text;
  glong text_len;
  GBytes *png;
  char **files;  // their paths, NULL-ended
} clip_read;
static clip_read clip_reads[CLIP_READS];
static int32_t clip_next = 1;

static clip_read *clip_of(int32_t id) {
  for (int i = 0; i < CLIP_READS; i++)
    if (clip_reads[i].id == id && id) return &clip_reads[i];
  return NULL;
}

static void clip_free(clip_read *r) {
  g_free(r->text);
  if (r->png) g_bytes_unref(r->png);
  g_strfreev(r->files);
  memset(r, 0, sizeof *r);
}

void mb_host_clip_end(int32_t id) {
  clip_read *r = clip_of(id);
  if (r) clip_free(r);
}

// words as the app's: CR LF as LF, in UTF-16
static gunichar2 *app_words(const char *s, glong *n) {
  GString *t = g_string_new(NULL);
  for (const char *p = s; *p; p++)
    if (!(p[0] == '\r' && p[1] == '\n')) g_string_append_c(t, *p);
  gunichar2 *u = g_utf8_to_utf16(t->str, -1, NULL, n, NULL);
  g_string_free(t, TRUE);
  if (!u) *n = 0;
  return u;
}

// one read of a clip answered: when it was its last, the clip is done (told as the next frame begins)
static void clip_answered(int32_t id) {
  clip_read *r = clip_of(id);
  if (r && r->waiting > 0 && --r->waiting == 0) schedule();
}

static void clip_text_done(GObject *src, GAsyncResult *res, gpointer data) {
  int32_t id = GPOINTER_TO_INT(data);
  char *s = gdk_clipboard_read_text_finish(GDK_CLIPBOARD(src), res, NULL);
  clip_read *r = clip_of(id);
  if (r && s) r->text = app_words(s, &r->text_len);
  g_free(s);
  clip_answered(id);
}

static void clip_picture_done(GObject *src, GAsyncResult *res, gpointer data) {
  int32_t id = GPOINTER_TO_INT(data);
  GdkTexture *t = gdk_clipboard_read_texture_finish(GDK_CLIPBOARD(src), res, NULL);
  clip_read *r = clip_of(id);
  if (r) {
    GBytes *png = t ? gdk_texture_save_to_png_bytes(t) : NULL;
    if (!png) {
      r->picture = CLIP_UNREADABLE;
    } else if (g_bytes_get_size(png) > 8u * 1024 * 1024) {
      r->picture = CLIP_TOO_LARGE;
      g_bytes_unref(png);
    } else {
      r->picture = CLIP_PNG;
      r->png = png;
    }
  }
  if (t) g_object_unref(t);
  clip_answered(id);
}

static void clip_files_done(GObject *src, GAsyncResult *res, gpointer data) {
  int32_t id = GPOINTER_TO_INT(data);
  const GValue *v = gdk_clipboard_read_value_finish(GDK_CLIPBOARD(src), res, NULL);
  clip_read *r = clip_of(id);
  if (r && v && G_VALUE_HOLDS(v, GDK_TYPE_FILE_LIST)) {
    GSList *files = gdk_file_list_get_files(g_value_get_boxed(v));
    GPtrArray *paths = g_ptr_array_new();
    for (GSList *f = files; f; f = f->next) {
      char *p = g_file_get_path(f->data);
      if (p) g_ptr_array_add(paths, p);
    }
    g_slist_free(files);
    g_ptr_array_add(paths, NULL);
    r->files = (char **)g_ptr_array_free(paths, FALSE);
  }
  clip_answered(id);
}

// What the clipboard has, as GTK can read it (its own types the formats are read into).
static GdkContentFormats *clip_formats(void) {
  GdkContentFormats *f = gdk_clipboard_get_formats(gtk_widget_get_clipboard(area));
  return gdk_content_formats_union_deserialize_gtypes(gdk_content_formats_ref(f));
}

// Read as the system hands it over (another program's clipboard comes later), told as the next frame begins.
int32_t mb_host_clip_read(void) {
  clip_read *r = NULL;
  for (int k = 0; k < CLIP_READS && !r; k++)
    if (!clip_reads[k].id) r = &clip_reads[k];
  if (!r) return 0;
  int32_t id = clip_next++;
  r->id = id;
  GdkClipboard *cb = gtk_widget_get_clipboard(area);
  GdkContentFormats *f = clip_formats();
  gpointer d = GINT_TO_POINTER(id);
  r->waiting = 1;  // (this call's own: none may be asked)
  if (gdk_content_formats_contain_gtype(f, G_TYPE_STRING)) {
    r->waiting++;
    gdk_clipboard_read_text_async(cb, NULL, clip_text_done, d);
  }
  if (gdk_content_formats_contain_gtype(f, GDK_TYPE_FILE_LIST)) {
    r->waiting++;
    gdk_clipboard_read_value_async(cb, GDK_TYPE_FILE_LIST, G_PRIORITY_DEFAULT, NULL, clip_files_done, d);
  } else if (gdk_content_formats_contain_gtype(f, GDK_TYPE_TEXTURE)) {
    r->waiting++;
    gdk_clipboard_read_texture_async(cb, NULL, clip_picture_done, d);
  }
  gdk_content_formats_unref(f);
  clip_answered(id);
  return id;
}

// The reads done since the last frame, told before it is drawn.
static void device_tell(mb_outside_fn tell) {
  for (int i = 0; i < CLIP_READS; i++) {
    if (clip_reads[i].id && !clip_reads[i].told && clip_reads[i].waiting == 0) {
      clip_reads[i].told = 1;
      if (tell) tell(MB_OUTSIDE_CLIP, clip_reads[i].id, 1);
    }
  }
}

int32_t mb_host_clip_state(int32_t id) {
  clip_read *r = clip_of(id);
  return !r ? -1 : r->told ? 1 : 0;
}

int32_t mb_host_clip_picture(int32_t id) {
  clip_read *r = clip_of(id);
  return r ? r->picture : CLIP_NONE;
}

moonbit_string_t mb_host_clip_text(int32_t id) {
  clip_read *r = clip_of(id);
  int n = r ? (int)r->text_len : 0;
  moonbit_string_t s = moonbit_make_string_raw(n);
  if (n) memcpy(s, r->text, (size_t)n * 2);
  return s;
}

moonbit_bytes_t mb_host_clip_png(int32_t id) {
  clip_read *r = clip_of(id);
  gsize n = 0;
  const void *p = r && r->png ? g_bytes_get_data(r->png, &n) : NULL;
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)n, 0);
  if (n) memcpy(b, p, n);
  return b;
}

int32_t mb_host_clip_files(int32_t id) {
  clip_read *r = clip_of(id);
  return r && r->files ? (int32_t)g_strv_length(r->files) : 0;
}

static moonbit_string_t mstr(const char *s);

moonbit_string_t mb_host_clip_file_name(int32_t id, int32_t i) {
  if (i < 0 || i >= mb_host_clip_files(id)) return moonbit_make_string_raw(0);
  char *base = g_path_get_basename(clip_of(id)->files[i]);
  moonbit_string_t s = mstr(base);
  g_free(base);
  return s;
}

moonbit_bytes_t mb_host_clip_file(int32_t id, int32_t i) {
  gchar *d = NULL;
  gsize n = 0;
  if (i < 0 || i >= mb_host_clip_files(id) || !g_file_get_contents(clip_of(id)->files[i], &d, &n, NULL))
    return moonbit_make_bytes(0, 0);
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)n, 0);
  if (n) memcpy(b, d, n);
  g_free(d);
  return b;
}

// ---- the clipboard written: words (as @hostapi.clipboard_set), or a PNG as a picture (no label here) ----

void mb_host_clipboard_set(moonbit_string_t s);
void mb_host_clipboard_image(moonbit_bytes_t data);

void mb_host_clip_set(moonbit_string_t text, moonbit_bytes_t png, moonbit_string_t label) {
  (void)label;
  if (!Moonbit_array_length(png)) mb_host_clipboard_set(text);
  else mb_host_clipboard_image(png);
}

// ---- the display not kept on yet; no haptics ----

void mb_host_keep_awake(int32_t on) { (void)on; }

void mb_host_haptic(int32_t kind) { (void)kind; }
void mb_host_ime_action(int32_t kind) { (void)kind; }

// An app's own native calls (src/hostapi/native.mbt): none on this host yet.
int32_t mb_host_native_call(moonbit_string_t name, moonbit_string_t params) {
  (void)name, (void)params;
  return 0;
}
int32_t mb_host_native_state(int32_t id) {
  (void)id;
  return -1;
}
moonbit_string_t mb_host_native_result(int32_t id) {
  (void)id;
  return moonbit_make_string_raw(0);
}
void mb_host_native_end(int32_t id) { (void)id; }
