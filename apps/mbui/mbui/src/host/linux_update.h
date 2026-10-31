// Updates (@hostapi.app_version, update_fetch, update_apply, update_state) on Linux: the app keeping itself current, as the Mac's
// does (mac_app.m's Updates), where it is installed as an app: an identity (MBUI_APP_ID) and its version in a VERSION
// file beside its program (0.1.<n>, which still.fail's linux/install.sh puts there with it). A newer build the core
// found (`app.update`: the release's .tar.gz of the app's folder, still.fail's scripts/beta.sh linux) downloaded into
// the app's cache ($XDG_CACHE_HOME/<id>/updates), picking up where a cut connection left off (the bytes so far kept in
// `<name>.part`, the rest asked for as a range, a few times over with a growing pause while each try gets further),
// checked against its size and SHA-256 (update_fetch: ready); asked to (update_apply), unpacked there, and taken only
// when it is for this machine (its name says its
// architecture: -x64-linux, -arm64-linux), this app (its folder holds this program, by its name, and its installer,
// install.sh) and newer (its VERSION). It is put in place as a person puts it: its own installer run (the folder copied
// where the app lives, its desktop entry written again), and the program opened again as this one quits (a shell waits
// for this process to end first: two cores never share the data, nor the bus's name); the app quit with one ready, it
// is put in place as it goes (update_at_quit), not opened again. How it goes the app reads
// (`update_state`: the phase, how far, what went wrong, the build), told each time it changes (MB_OUTSIDE_UPDATE, id 1:
// 0 while the host works at it, 1 once it is ready, -1 failed). Included by linux_app.c after linux_life.h (app_id, quit).
#include <glib/gstdio.h>
#include <libsoup/soup.h>
#include <sys/utsname.h>

static char *own_exe;  // the program's path as it started (the one opened again: its installer puts the new one there)
static const char *update_phase = "idle";  // idle | downloading | retrying | ready | installing | failed
// the build asked for (its file's name), and once ready, its archive (main thread's)
static char *update_file, *update_ready;
static int update_percent = -1;
static char *update_error;
static int update_working, update_told = 1;

// (read before anything can take the program's place: /proc/self/exe says "(deleted)" after)
__attribute__((constructor)) static void update_begin(void) { own_exe = g_file_read_link("/proc/self/exe", NULL); }

// The build of the app installed (VERSION's last number), 0 where the program is no installed app.
int32_t mb_host_app_version(void) {
  static int v = -1;
  if (v >= 0) return v;
  v = 0;
  if (!*app_id() || !own_exe) return v;
  char *dir = g_path_get_dirname(own_exe), *path = g_build_filename(dir, "VERSION", NULL), *text = NULL;
  if (g_file_get_contents(path, &text, NULL, NULL)) {
    const char *dot = strrchr(g_strstrip(text), '.');
    v = dot ? atoi(dot + 1) : 0;
  }
  g_free(text), g_free(path), g_free(dir);
  return v;
}

// where its updates and what they did are kept: $XDG_CACHE_HOME/<id>/
static char *update_dir(const char *name) { return g_build_filename(g_get_user_cache_dir(), app_id(), name, NULL); }

// What an update did, on the log and in the app's cache (update.log: a program the desktop starts writes to nowhere
// else), where the shell that opens the new build adds its own line.
static void update_log(const char *s) {
  fprintf(stdout, "update: %s\n", s);
  fflush(stdout);
  char *path = update_dir("update.log"), *dir = g_path_get_dirname(path);
  g_mkdir_with_parents(dir, 0700);
  FILE *f = fopen(path, "a");
  if (f) {
    GDateTime *now = g_date_time_new_now_local();
    char *at = g_date_time_format_iso8601(now);
    fprintf(f, "%s %s\n", at, s);
    g_free(at);
    g_date_time_unref(now);
    fclose(f);
  }
  g_free(dir), g_free(path);
}

// How it goes, from the worker: kept and told on the main thread (where the frames read it).
typedef struct {
  const char *phase;
  int percent;
  char *error;
} update_word;

static gboolean update_said(gpointer p) {
  update_word *w = p;
  int changed = strcmp(w->phase, update_phase) != 0 || w->percent != update_percent;
  update_phase = w->phase;
  update_percent = w->percent;
  g_free(update_error);
  update_error = w->error;
  if (!strcmp(w->phase, "failed") || !strcmp(w->phase, "ready")) update_working = 0;
  g_free(w);
  if (changed) {
    update_told = 0;
    schedule();
  }
  return G_SOURCE_REMOVE;
}

static void update_say(const char *phase, int percent, const char *error) {
  update_word *w = g_new0(update_word, 1);
  w->phase = phase, w->percent = percent, w->error = g_strdup(error ? error : "");
  g_main_context_invoke(NULL, update_said, w);
}

// told as each frame begins (on_render): how it goes changed since
static void update_tell(mb_outside_fn tell) {
  if (update_told) return;
  update_told = 1;
  if (tell) tell(MB_OUTSIDE_UPDATE, 1, !strcmp(update_phase, "failed") ? -1 : !strcmp(update_phase, "ready") ? 1 : 0);
}

// One try of the download (its bytes appended to the part as they come): whether the file is whole, or why not
// (`retry`: a cut connection or the server's trouble, tried again; else given up at once).
static int update_fetch(const char *url, const char *part, gint64 size, int *retry, char **why) {
  *retry = 0;
  FILE *out = fopen(part, "ab");
  if (!out) {
    *why = g_strdup_printf("can't write %s", part);
    return 0;
  }
  fseeko(out, 0, SEEK_END);
  gint64 done = ftello(out);
  SoupSession *s = soup_session_new_with_options("timeout", 30, NULL);
  SoupMessage *m = soup_message_new("GET", url);
  int ok = 0;
  if (!m) {
    *why = g_strdup_printf("no such address: %s", url);
    goto end;
  }
  SoupMessageHeaders *h = soup_message_get_request_headers(m);
  soup_message_headers_append(h, "Cache-Control", "no-cache");
  if (done > 0) soup_message_headers_set_range(h, done, -1);
  GError *e = NULL;
  GInputStream *in = soup_session_send(s, m, NULL, &e);
  guint status = soup_message_get_status(m);
  // asked from its end: it is all here
  if (status == 416) {
    ok = 1;
  } else if (!in || (status != 200 && status != 206)) {
    *why = status ? g_strdup_printf("status %u", status) : g_strdup(e ? e->message : "failed");
    *retry = status == 0 || status >= 500;
  } else {
    // the whole file again (the server took no range): from its start
    if (status == 200 && done > 0) {
      fclose(out);
      out = fopen(part, "wb");
      done = 0;
    }
    char buf[1 << 16];
    gssize n;
    int said = -1;
    while (out && (n = g_input_stream_read(in, buf, sizeof buf, NULL, &e)) > 0) {
      if (fwrite(buf, 1, (size_t)n, out) != (size_t)n) break;
      done += n;
      int now = size > 0 ? (int)(done * 100 / size) : -1;
      if (now != said) update_say("downloading", said = now, NULL);
    }
    if (e) {
      *why = g_strdup(e->message);
      *retry = 1;
    } else if (!out || (size > 0 && done < size)) {
      *why = g_strdup_printf("connection closed at %" G_GINT64_FORMAT " of %" G_GINT64_FORMAT, done, size);
      *retry = 1;
    } else {
      ok = 1;
    }
  }
  g_clear_error(&e);
  if (in) g_object_unref(in);
end:
  if (m) g_object_unref(m);
  g_object_unref(s);
  if (out) fclose(out);
  return ok;
}

static char *update_sha256(const char *path) {
  FILE *f = fopen(path, "rb");
  if (!f) return g_strdup("");
  GChecksum *c = g_checksum_new(G_CHECKSUM_SHA256);
  guchar buf[1 << 16];
  size_t n;
  while ((n = fread(buf, 1, sizeof buf, f)) > 0) g_checksum_update(c, buf, (gssize)n);
  fclose(f);
  char *s = g_strdup(g_checksum_get_string(c));
  g_checksum_free(c);
  return s;
}

static gint64 file_size(const char *path) {
  GStatBuf st;
  return g_stat(path, &st) == 0 ? (gint64)st.st_size : 0;
}

// The release downloaded whole into `dir` (what is there from before kept only if it is the part of this one), checked
// against its SHA-256: its path, or NULL and why not.
static char *update_download(const char *dir, const char *url, const char *sha256, gint64 size, const char *name,
                             char **why) {
  g_mkdir_with_parents(dir, 0700);
  char *tgz = g_build_filename(dir, name, NULL), *part = g_strconcat(tgz, ".part", NULL);
  GDir *d = g_dir_open(dir, 0, NULL);
  for (const char *f; d && (f = g_dir_read_name(d));) {
    char *p = g_build_filename(dir, f, NULL);
    if (strcmp(p, tgz) && strcmp(p, part)) {
      char *argv[] = {"rm", "-rf", p, NULL};
      g_spawn_sync(NULL, argv, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, NULL, NULL, NULL);
    }
    g_free(p);
  }
  if (d) g_dir_close(d);
  if (g_file_test(tgz, G_FILE_TEST_EXISTS)) {
    char *got = update_sha256(tgz);
    int same = !g_ascii_strcasecmp(got, sha256);
    g_free(got);
    if (same) {
      g_free(part);
      return tgz;
    }
    g_unlink(tgz);
  }
  if (size > 0 && file_size(part) > size) g_unlink(part);
  // how far from the first: what an earlier try kept (0 none), not "not known" till the first bytes come
  if (size > 0) update_say("downloading", (int)(file_size(part) * 100 / size), NULL);
  // tries in a row that got no further before it gives up (pauses of 1, 2, 4, 8, 16 s between them)
  const int retries = 6;
  int failures = 0;
  for (;;) {
    gint64 before = file_size(part);
    int retry = 0;
    g_clear_pointer(why, g_free);
    if (update_fetch(url, part, size, &retry, why)) break;
    if (!retry) goto fail;
    if (file_size(part) > before) failures = 0;
    if (++failures >= retries) goto fail;
    update_say("retrying", update_percent, NULL);
    g_usleep((gulong)(1 << (failures - 1)) * G_USEC_PER_SEC);
    update_say("downloading", update_percent, NULL);
  }
  char *got = update_sha256(part);
  if (g_ascii_strcasecmp(got, sha256) != 0 || g_rename(part, tgz) != 0) {
    g_unlink(part);
    g_free(got);
    g_free(*why);
    *why = g_strdup("incomplete");
    goto fail;
  }
  char *said = g_strdup_printf("%s downloaded, sha256 %s as the feed says", name, got);
  update_log(said);
  g_free(said), g_free(got), g_free(part);
  return tgz;
fail:
  g_free(part), g_free(tgz);
  return NULL;
}

// this machine's architecture as a release names it
static const char *own_arch(void) {
  struct utsname u;
  if (uname(&u) != 0) return "";
  if (!strcmp(u.machine, "x86_64")) return "x64";
  if (!strcmp(u.machine, "aarch64")) return "arm64";
  return "";
}

// whether a release by its name is for this machine (stillfail-mbui-<n>-<x64|arm64>-linux.tar.gz)
static int update_for_here(const char *name) {
  char *arch = g_strdup_printf("-%s-linux.", own_arch());
  int here = *own_arch() && strstr(name, arch) != NULL;
  g_free(arch);
  return here;
}

// The archive unpacked beside it, checked to be this app's newer build, and its installer run: NULL, or why not.
static char *update_put(const char *tgz) {
  char *why = NULL;
  char *dir = g_path_get_dirname(tgz), *stage = g_build_filename(dir, "stage", NULL);
  char *exe = g_path_get_basename(own_exe), *folder = NULL, *program = NULL, *installer = NULL, *version = NULL;
  int status = -1;
  char *rm[] = {"rm", "-rf", stage, NULL}, *mk[] = {"mkdir", "-p", stage, NULL};
  char *untar[] = {"tar", "-xzf", (char *)tgz, "-C", stage, NULL};
  g_spawn_sync(NULL, rm, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, NULL, NULL, NULL);
  g_spawn_sync(NULL, mk, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, NULL, NULL, NULL);
  if (!g_spawn_sync(NULL, untar, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, NULL, &status, NULL) ||
      !g_spawn_check_wait_status(status, NULL)) {
    why = g_strdup("incomplete");
    goto end;
  }
  // its one folder (still.fail-mbui/)
  GDir *d = g_dir_open(stage, 0, NULL);
  const char *first = d ? g_dir_read_name(d) : NULL;
  if (first) folder = g_build_filename(stage, first, NULL);
  if (d) g_dir_close(d);
  if (folder) {
    program = g_build_filename(folder, exe, NULL);
    installer = g_build_filename(folder, "install.sh", NULL);
    char *vpath = g_build_filename(folder, "VERSION", NULL);
    g_file_get_contents(vpath, &version, NULL, NULL);
    g_free(vpath);
  }
  const char *dot = version ? strrchr(g_strstrip(version), '.') : NULL;
  if (!folder || !g_file_test(program, G_FILE_TEST_IS_EXECUTABLE) || !g_file_test(installer, G_FILE_TEST_EXISTS)) {
    why = g_strdup_printf("not this app (no %s and install.sh in it)", exe);
  } else if (!dot || atoi(dot + 1) <= mb_host_app_version()) {
    why = g_strdup("not newer");
  } else {
    char *argv[] = {"sh", installer, NULL}, *out = NULL;
    if (!g_spawn_sync(folder, argv, NULL, G_SPAWN_SEARCH_PATH | G_SPAWN_STDERR_TO_DEV_NULL, NULL, NULL, &out, NULL,
                      &status, NULL) ||
        !g_spawn_check_wait_status(status, NULL))
      why = g_strdup("its installer failed");
    else if (out)
      update_log(g_strstrip(out));
    g_free(out);
  }
  g_spawn_sync(NULL, rm, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, NULL, NULL, NULL);
end:
  g_free(dir), g_free(stage), g_free(exe), g_free(folder), g_free(program), g_free(installer);
  g_free(version);
  return why;
}

typedef struct {
  char *url, *sha256, *name;
  gint64 size;
} update_ask;

// in place: opened again once this process has ended (the program's path as $0, the log's as $1: nothing in them read
// as the shell's), and this one quits
static gboolean update_again(gpointer data) {
  (void)data;
  char *log = update_dir("update.log"), *pid = g_strdup_printf("%d", (int)getpid());
  char *script = g_strdup_printf("while kill -0 %s 2>/dev/null; do sleep 0.2; done; "
                                 "echo \"$(date -Iseconds) opened $0\" >> \"$1\"; exec \"$0\"",
                                 pid);
  char *argv[] = {"/bin/sh", "-c", script, own_exe, log, NULL};
  g_spawn_async(NULL, argv, NULL, G_SPAWN_DEFAULT, NULL, NULL, NULL, NULL);
  g_free(script), g_free(pid), g_free(log);
  quit();
  return G_SOURCE_REMOVE;
}

// The app quitting with a build ready (the person never said 重启更新): put in place as it goes, its installer run, not
// opened again (the next time the person opens it, it is the newer build).
static void update_at_quit(void) {
  if (!update_ready || strcmp(update_phase, "ready")) return;
  char *tgz = update_ready;
  update_ready = NULL;
  char *why = update_put(tgz);
  update_log(why ? why : "in place as this one quits");
  if (!why) g_unlink(tgz);
  g_free(why), g_free(tgz);
}

// the archive downloaded and checked: kept as ready (on the main thread, where it is read)
static gboolean update_readied(gpointer tgz) {
  static int at_quit;
  g_free(update_ready);
  update_ready = tgz;
  if (!at_quit) at_quit = 1, atexit(update_at_quit);
  return G_SOURCE_REMOVE;
}

static gpointer update_work(gpointer data) {
  update_ask *a = data;
  char *dir = update_dir("updates"), *why = NULL, *tgz = NULL;
  // (another machine's not downloaded at all)
  if (!update_for_here(a->name)) why = g_strdup_printf("another machine's (%s)", a->name);
  else tgz = update_download(dir, a->url, a->sha256, a->size, a->name, &why);
  if (why) {
    char *said = g_strdup_printf("failed: %s", why);
    update_log(said);
    g_free(said);
    update_say("failed", -1, why);
    g_free(tgz);
  } else {
    char *said = g_strdup_printf("%s ready", tgz);
    update_log(said);
    g_free(said);
    g_main_context_invoke(NULL, update_readied, tgz);
    update_say("ready", -1, NULL);
  }
  g_free(why), g_free(dir);
  g_free(a->url), g_free(a->sha256), g_free(a->name), g_free(a);
  return NULL;
}

void mb_host_update_fetch(moonbit_string_t url, moonbit_string_t sha256, double size, moonbit_string_t name, int32_t now) {
  (void)now;  // (no network here is told apart as costing more)
  if (update_working || mb_host_app_version() <= 0) return;
  update_ask *a = g_new0(update_ask, 1);
  char *n = utf8(name);
  a->url = utf8(url), a->sha256 = utf8(sha256), a->name = g_path_get_basename(n), a->size = (gint64)size;
  g_free(n);
  // (ready already, or being put in place)
  if (update_file && !strcmp(update_file, a->name) && (!strcmp(update_phase, "ready") || !strcmp(update_phase, "installing"))) {
    g_free(a->url), g_free(a->sha256), g_free(a->name), g_free(a);
    return;
  }
  g_free(update_file);
  update_file = g_strdup(a->name);
  g_free(update_ready);
  update_ready = NULL;
  update_working = 1;
  update_phase = "downloading";
  update_percent = -1;
  g_free(update_error);
  update_error = g_strdup("");
  update_told = 0;
  schedule();
  g_thread_unref(g_thread_new("update", update_work, a));
}

// the archive ready unpacked, checked and installed; in place, opened again as this one quits
static gpointer update_put_work(gpointer tgz) {
  char *why = update_put(tgz);
  if (why) {
    char *said = g_strdup_printf("failed: %s", why);
    update_log(said);
    g_free(said);
    update_say("failed", -1, why);
  } else {
    g_unlink(tgz);
    update_log("in place; opened again as this one quits");
    g_main_context_invoke(NULL, update_again, NULL);
  }
  g_free(why), g_free(tgz);
  return NULL;
}

void mb_host_update_apply(moonbit_string_t said) {
  (void)said;  // (opened again here: nothing to say)
  if (!update_ready || strcmp(update_phase, "ready")) return;
  char *tgz = update_ready;
  update_ready = NULL;
  update_working = 1;
  update_phase = "installing";
  update_percent = -1;
  update_told = 0;
  schedule();
  g_thread_unref(g_thread_new("update", update_put_work, tgz));
}

moonbit_string_t mb_host_update_state(void) {
  if (mb_host_app_version() <= 0) return moonbit_make_string_raw(0);
  GString *b = g_string_new(NULL);
  g_string_printf(b, "{\"phase\":\"%s\",\"percent\":%d,\"error\":\"", update_phase, update_percent);
  json_put(b, update_error ? update_error : "");
  g_string_append(b, "\",\"file\":\"");
  json_put(b, update_file ? update_file : "");
  g_string_append(b, "\"}");
  moonbit_string_t s = mstr(b->str);
  g_string_free(b, TRUE);
  return s;
}
