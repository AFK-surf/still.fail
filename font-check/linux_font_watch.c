// An isolated fontconfig, with no fonts installed on the runner: the same inotify watch the Linux host uses sees a
// root created after the app starts, nested directories, a font installed and removed, and a root moved away.
#include <glib/gstdio.h>
#include "../../src/host/linux_font_watch.h"

static int changes;
static void changed(void) {
  g_assert_true(FcConfigBuildFonts(FcConfigGetCurrent()));
  changes++;
}

// inotify enqueues these events before the filesystem operation returns; dispatch them without a clock or a sleep.
static void dispatch(void) {
  while (g_main_context_pending(NULL)) g_main_context_iteration(NULL, FALSE);
}

static int system_fonts(void) {
  FcFontSet *set = FcConfigGetFonts(FcConfigGetCurrent(), FcSetSystem);
  return set ? set->nfont : 0;
}

int main(int argc, char **argv) {
  g_assert_cmpint(argc, ==, 2);
  char *tmp = g_dir_make_tmp("mbui-font-watch-XXXXXX", NULL);
  g_assert_nonnull(tmp);
  char *a = g_build_filename(tmp, "a", NULL);
  char *b = g_build_filename(a, "b", NULL);
  char *root = g_build_filename(b, "fonts", NULL);
  char *sub = g_build_filename(root, "nested", NULL);
  char *font = g_build_filename(sub, "font.ttf", NULL);
  char *noise = g_build_filename(tmp, "unrelated", NULL);
  char *moved = g_build_filename(b, "moved", NULL);
  char *cache = g_build_filename(tmp, "cache", NULL);
  char *xml = g_strdup_printf("<?xml version=\"1.0\"?><!DOCTYPE fontconfig SYSTEM \"fonts.dtd\">"
                              "<fontconfig><dir>%s</dir><cachedir>%s</cachedir></fontconfig>", root, cache);
  FcConfig *config = FcConfigCreate();
  g_assert_nonnull(config);
  g_assert_true(FcConfigParseAndLoadFromMemory(config, (const FcChar8 *)xml, FcTrue));
  g_assert_true(FcConfigBuildFonts(config));
  g_assert_true(FcConfigAppFontAddFile(config, (const FcChar8 *)argv[1]));
  g_assert_true(FcConfigSetCurrent(config));
  FcConfigDestroy(config);
  g_assert_true(mb_font_watch_start(changed));
  g_assert_cmpint(system_fonts(), ==, 0);
  FcFontSet *app = FcConfigGetFonts(NULL, FcSetApplication);
  g_assert_nonnull(app);
  int app_count = app->nfont;
  g_assert_cmpint(app_count, >, 0);

  // An unrelated file in the nearest parent does not cause a rescan.
  g_assert_true(g_file_set_contents(noise, "x", 1, NULL));
  dispatch();
  g_assert_cmpint(changes, ==, 0);
  g_assert_cmpint(g_mkdir(a, 0700), ==, 0);
  dispatch();
  g_assert_cmpint(changes, ==, 1);
  g_assert_cmpint(g_mkdir(b, 0700), ==, 0);
  dispatch();
  g_assert_cmpint(changes, ==, 2);
  g_assert_cmpint(g_mkdir(root, 0700), ==, 0);
  dispatch();
  g_assert_cmpint(changes, ==, 3);
  g_assert_cmpint(g_mkdir(sub, 0700), ==, 0);
  dispatch();
  g_assert_cmpint(changes, ==, 4);

  gchar *bytes = NULL;
  gsize len = 0;
  g_assert_true(g_file_get_contents(argv[1], &bytes, &len, NULL));
  g_assert_true(g_file_set_contents(font, bytes, len, NULL));
  g_free(bytes);
  dispatch();
  g_assert_cmpint(changes, ==, 5);
  g_assert_cmpint(system_fonts(), >, 0);
  g_assert_cmpint(FcConfigGetFonts(NULL, FcSetApplication)->nfont, ==, app_count);
  g_assert_cmpint(g_remove(font), ==, 0);
  dispatch();
  g_assert_cmpint(changes, ==, 6);
  g_assert_cmpint(system_fonts(), ==, 0);
  g_assert_cmpint(FcConfigGetFonts(NULL, FcSetApplication)->nfont, ==, app_count);
  g_assert_cmpint(g_rename(root, moved), ==, 0);
  dispatch();
  g_assert_cmpint(changes, ==, 7);
  g_assert_cmpint(g_mkdir(root, 0700), ==, 0);
  dispatch();
  g_assert_cmpint(changes, ==, 8);

  g_remove(noise);
  g_rmdir(root);
  char *moved_sub = g_build_filename(moved, "nested", NULL);
  g_rmdir(moved_sub);
  g_rmdir(moved);
  g_rmdir(b);
  g_rmdir(a);
  // fontconfig may leave cache files in its private directory; the test process and its temporary directory end here.
  g_free(moved_sub); g_free(cache); g_free(moved); g_free(noise); g_free(font); g_free(sub);
  g_free(root); g_free(b); g_free(a); g_free(xml); g_free(tmp);
  return 0;
}
