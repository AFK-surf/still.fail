// Installed fonts change outside the app. Watch fontconfig's directories with inotify, not a periodic rescan.
// A watch on each directory is necessary: inotify does not watch descendants. The parent of each configured root is
// watched too, including the nearest existing parent of a root that has not been created yet.
#pragma once
#include <errno.h>
#include <glib-unix.h>
#include <glib.h>
#include <fontconfig/fontconfig.h>
#include <string.h>
#include <sys/inotify.h>
#include <sys/stat.h>
#include <unistd.h>

typedef struct {
  gboolean tree;
  char *path;
  GHashTable *children;  // names of configured roots (or the next missing component) in this parent
} mb_font_dir;

typedef struct {
  int fd;
  GHashTable *dirs;       // inotify watch descriptor -> mb_font_dir
  GHashTable *visited;    // device and inode, to avoid cycles through symbolic links
  void (*changed)(void);
} mb_font_watch;

static void mb_font_dir_free(gpointer data) {
  mb_font_dir *dir = data;
  g_free(dir->path);
  g_hash_table_unref(dir->children);
  g_free(dir);
}

static void mb_font_watch_dir(mb_font_watch *w, const char *path, gboolean tree, const char *child) {
  int wd = inotify_add_watch(w->fd, path, IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO | IN_CLOSE_WRITE |
                                         IN_ATTRIB | IN_DELETE_SELF | IN_MOVE_SELF | IN_ONLYDIR);
  if (wd < 0) return;  // a directory may have gone away while the watch was being made
  mb_font_dir *dir = g_hash_table_lookup(w->dirs, GINT_TO_POINTER(wd));
  if (!dir) {
    dir = g_new0(mb_font_dir, 1);
    dir->path = g_strdup(path);
    dir->children = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
    g_hash_table_insert(w->dirs, GINT_TO_POINTER(wd), dir);
  }
  if (tree) dir->tree = TRUE;
  if (child) g_hash_table_add(dir->children, g_strdup(child));
}

static void mb_font_watch_tree(mb_font_watch *w, const char *path) {
  struct stat st;
  if (stat(path, &st) != 0 || !S_ISDIR(st.st_mode)) return;
  char *inode = g_strdup_printf("%llu:%llu", (unsigned long long)st.st_dev, (unsigned long long)st.st_ino);
  if (g_hash_table_contains(w->visited, inode)) { g_free(inode); return; }
  g_hash_table_add(w->visited, inode);
  // Install this watch before enumerating: a directory made during the enumeration will be reported by its parent.
  mb_font_watch_dir(w, path, TRUE, NULL);
  GDir *dir = g_dir_open(path, 0, NULL);
  if (!dir) return;
  const char *name;
  while ((name = g_dir_read_name(dir))) {
    char *next = g_build_filename(path, name, NULL);
    mb_font_watch_tree(w, next);
    g_free(next);
  }
  g_dir_close(dir);
}

static void mb_font_watch_root(mb_font_watch *w, const char *root) {
  if (!root || !*root) return;
  char *parent = g_path_get_dirname(root), *child = g_path_get_basename(root);
  while (!g_file_test(parent, G_FILE_TEST_IS_DIR) && strcmp(parent, "/") != 0) {
    char *up = g_path_get_dirname(parent);
    g_free(child);
    child = g_path_get_basename(parent);
    g_free(parent);
    parent = up;
  }
  mb_font_watch_dir(w, parent, FALSE, child);
  mb_font_watch_tree(w, root);
  g_free(parent);
  g_free(child);
}

static gboolean mb_font_watch_event(gint fd, GIOCondition condition, gpointer data);

// Make the replacement before dropping the previous watches, so there is no unobserved gap. Its first rescan after
// this also sees anything that changed before a newly discovered directory was watched.
static gboolean mb_font_watch_install(mb_font_watch *w) {
  int fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
  if (fd < 0) return FALSE;
  int old_fd = w->fd;
  GHashTable *old_dirs = w->dirs, *old_visited = w->visited;
  w->fd = fd;
  w->dirs = g_hash_table_new_full(g_direct_hash, g_direct_equal, NULL, mb_font_dir_free);
  w->visited = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
  FcStrList *roots = FcConfigGetConfigDirs(NULL);
  if (roots) {
    FcChar8 *root;
    while ((root = FcStrListNext(roots))) mb_font_watch_root(w, (const char *)root);
    FcStrListDone(roots);
  }
  roots = FcConfigGetFontDirs(NULL);
  if (roots) {
    FcChar8 *root;
    while ((root = FcStrListNext(roots))) mb_font_watch_root(w, (const char *)root);
    FcStrListDone(roots);
  }
  g_unix_fd_add(fd, G_IO_IN | G_IO_ERR | G_IO_HUP, mb_font_watch_event, w);
  if (old_fd >= 0) close(old_fd);
  if (old_dirs) g_hash_table_unref(old_dirs);
  if (old_visited) g_hash_table_unref(old_visited);
  return TRUE;
}

static gboolean mb_font_watch_event(gint fd, GIOCondition condition, gpointer data) {
  mb_font_watch *w = data;
  gboolean changed = (condition & (G_IO_ERR | G_IO_HUP)) != 0;
  GHashTable *written = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
  char buf[16384] __attribute__((aligned(__alignof__(struct inotify_event))));
  ssize_t len;
  while ((len = read(fd, buf, sizeof buf)) > 0) {
    for (char *p = buf; p < buf + len;) {
      struct inotify_event *event = (struct inotify_event *)p;
      mb_font_dir *dir = g_hash_table_lookup(w->dirs, GINT_TO_POINTER(event->wd));
      if ((event->mask & IN_Q_OVERFLOW) || (dir && (dir->tree || !event->len ||
          g_hash_table_contains(dir->children, event->name)))) changed = TRUE;
      // Replacing a font in place does not alter its directory's timestamp. Refresh that directory's cache explicitly
      // on close, before FcConfigBuildFonts, so fontconfig cannot reuse a stale but apparently valid cache.
      if (dir && dir->tree && (event->mask & IN_CLOSE_WRITE)) g_hash_table_add(written, g_strdup(dir->path));
      p += sizeof *event + event->len;
    }
  }
  if (len < 0 && errno != EAGAIN && errno != EINTR) changed = TRUE;
  GHashTableIter it;
  gpointer path;
  g_hash_table_iter_init(&it, written);
  while (g_hash_table_iter_next(&it, &path, NULL)) {
    FcCache *cache = FcDirCacheRescan((const FcChar8 *)path, FcConfigGetCurrent());
    if (cache) FcDirCacheUnload(cache);
  }
  g_hash_table_unref(written);
  if (!changed) return G_SOURCE_CONTINUE;
  if (!mb_font_watch_install(w)) return G_SOURCE_CONTINUE;
  w->changed();
  return G_SOURCE_REMOVE;
}

static gboolean mb_font_watch_start(void (*changed)(void)) {
  static mb_font_watch *watch;
  if (watch) return FALSE;
  watch = g_new0(mb_font_watch, 1);
  watch->fd = -1;
  watch->changed = changed;
  if (!mb_font_watch_install(watch)) {
    g_free(watch);
    watch = NULL;
    return FALSE;
  }
  return TRUE;
}
