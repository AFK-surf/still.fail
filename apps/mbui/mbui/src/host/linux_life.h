// The app's life on Linux, and what the system says of it (win_life.h's, the Linux way). Included by linux_app.c after
// its keys (its window, schedule, app_state above).
//
// A program that is an app has an identity: MBUI_APP_ID (and MBUI_APP_NAME, MBUI_SCHEMES), from its environment (its
// desktop entry runs it so: still.fail's linux/install.sh). Such an app:
// - runs once for its person: started again, the one that runs is brought to the front and handed the link this one
//   was started with, and this one ends, as the program starts, before any of it runs (its core on the same files:
//   life_begin, among the program's constructors). GApplication's own way, on the session bus: a GtkApplication of the
//   id (MbLifeApp), whose call carries the launcher's activation token along, so that the desktop lets the window come
//   to the front. The desktop's own Quit (GNOME's dash) asks the app's `quit` action: the app ends; its notifications
//   are the desktop's (GNotification), a click on one the app's `notice` action;
// - goes on with its window closed where the desktop shows apps' icons (a StatusNotifierWatcher on the session bus:
//   KDE's, Ubuntu's GNOME, Xfce's, Cinnamon's), put away to its icon there (its core, its notifications on): the icon
//   clicked, or the app started again, brings it back; the icon's menu (the app's words: menu_setup's `"role": "tray"`
//   menu) brings it back or quits. Where the desktop shows none (GNOME's own), its window closed ends it, as apps
//   there do: nothing would show that it runs;
// - is opened with a link of its schemes (MBUI_SCHEMES, "stillfail,ember"): as it starts, or the one running is.
// A program without one (a demo, a test app's scripted run) ends as its window closes, as before. So does a window of
// the app's own (@hostapi.window_open: the program run again with MBUI_WINDOW): it runs beside the app's one run, not
// handed to it, with no icon among the desktop's and none of its notifications.
// Said to the app on the system's channel (src/hostapi/system.mbt): `shown` with how long it was away as its window
// comes back after it was put away and as the computer wakes from sleep (logind's PrepareForSleep), `link`, `network`
// as the way out goes another way (another interface, another address), `menu` as an action of its icon's menu is
// chosen.
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include "mini_json.h"  // the menu the app gives (menu_setup)

static GtkApplication *life_app;  // the app's, registered as the program started (NULL: the program is none)
static char *started_link;        // the link the program was started with (NULL: none)
static char *window_title;
static char *activation_token;  // the desktop's leave for the window to come to the front, as its icon was clicked

// ---- who it is ----

// the app's identity ("": the program is none), its name (else the window's title)
static const char *app_id(void) {
  const char *v = getenv("MBUI_APP_ID");
  return v ? v : "";
}
static const char *app_name(void) {
  const char *v = getenv("MBUI_APP_NAME");
  return v && *v ? v : window_title ? window_title : app_id();
}

// a link of the app's schemes (MBUI_SCHEMES: "stillfail,ember"), else 0
static int app_link(const char *s) {
  const char *schemes = getenv("MBUI_SCHEMES");
  const char *colon = s ? strchr(s, ':') : NULL;
  if (!schemes || !colon || colon == s) return 0;
  size_t n = (size_t)(colon - s);
  for (const char *p = schemes; *p;) {
    const char *e = strchr(p, ',');
    size_t k = e ? (size_t)(e - p) : strlen(p);
    if (k == n && !g_ascii_strncasecmp(p, s, n)) return 1;
    p += k + (e ? 1 : 0);
  }
  return 0;
}

// the link the program was started with: the first of its arguments that is one of the app's (its command line as the
// kernel keeps it: each argument NUL-ended, the program's first)
static void read_started_with(void) {
  gchar *all = NULL;
  gsize n = 0;
  if (!g_file_get_contents("/proc/self/cmdline", &all, &n, NULL)) return;
  for (gsize i = strnlen(all, n) + 1; i < n && !started_link;) {
    const char *a = all + i;
    if (app_link(a)) started_link = g_strdup(a);
    i += strnlen(a, n - i) + 1;
  }
  g_free(all);
}

// ---- said on the system's channel ----

// `s` escaped for a JSON string, appended to `out`
static void json_put(GString *out, const char *s) {
  for (const char *c = s; *c; c++) {
    unsigned char u = (unsigned char)*c;
    if (u == '"' || u == '\\') g_string_append_printf(out, "\\%c", u);
    else if (u < 0x20) g_string_append_printf(out, "\\u%04x", u);
    else g_string_append_c(out, (char)u);
  }
}

static void say_system(const char *json, size_t n) { mb_post("system", json, n, NULL, 0); }

// a clock that counts a sleep's time (CLOCK_MONOTONIC stops while the computer sleeps)
static double boot_ms(void) {
  struct timespec t;
  clock_gettime(CLOCK_BOOTTIME, &t);
  return t.tv_sec * 1000.0 + t.tv_nsec / 1e6;
}

// away since `at` (boot_ms's)
static void say_shown(double at) {
  char b[64];
  int n = snprintf(b, sizeof b, "{\"shown\":{\"away\":%.0f}}", boot_ms() - at);
  say_system(b, (size_t)n);
}

static void say_link(const char *url) {
  GString *b = g_string_new("{\"link\":\"");
  json_put(b, url);
  g_string_append(b, "\"}");
  const char *colon = strchr(url, ':');
  fprintf(stdout, "linux: opened with a link (%.*s)\n", colon ? (int)(colon - url) + 3 : 0, url);
  fflush(stdout);
  say_system(b->str, b->len);
  g_string_free(b, TRUE);
}

// ---- put away, brought back ----

static double put_away_at = -1;  // boot_ms() as the window was put away (-1: it is out)
static double asleep_at = -1;    // as the computer went to sleep (-1: awake)
static int tray_on;              // the desktop shows the app's icon (its watcher took it)

static void bring_back(void) {
  if (!win) return;
  if (put_away_at >= 0) {
    fprintf(stdout, "linux: brought back\n");
    fflush(stdout);
  }
  // (the desktop's leave its icon was clicked with, for the window to come to the front: Wayland's)
  if (activation_token) {
    gtk_window_set_startup_id(GTK_WINDOW(win), activation_token);
    g_clear_pointer(&activation_token, g_free);
  }
  gtk_window_present(GTK_WINDOW(win));
  if (put_away_at >= 0) {
    say_shown(put_away_at);
    put_away_at = -1;
  }
  schedule();
}

// the window closed: put away where the program is an app and the desktop shows its icon; else the program ends
static int put_away(void) {
  if (!life_app || !tray_on) return 0;
  fprintf(stdout, "linux: put away, to its icon\n");
  fflush(stdout);
  gtk_widget_set_visible(win, FALSE);
  if (put_away_at < 0) put_away_at = boot_ms();
  return 1;
}

static void quit(void) { exit(0); }

static gboolean on_close(GtkWindow *w, gpointer data) {
  (void)w, (void)data;
  if (!put_away()) quit();
  return TRUE;
}

// ---- notifications (notify.mbt) ----
// The desktop's (GNotification, through the app's GApplication: GNOME Shell's own, or the freedesktop notification
// server KDE's and the others run) when the program is an app: one per tag (sent with it as its id: a newer one
// replaces it), clicked it brings the app to the front with what it opens (the app's `notice` action, its target the
// tag and what it opens). A program that is none shows nothing: what would be shown is only kept. Either way it is kept
// (one per tag) and said on the log (NOTICE <tag>\t<title>\t<body>), and a scripted run clicks one by its words
// (drive 6), which gives the app what it opens as a click would. What the desktop allows is not asked here (it shows
// an app's unless the person turned them off in its settings, which it does not tell): allowed where the program is
// an app.

typedef struct {
  char *tag, *title, *body, *opens;
} notice_kept;
static GPtrArray *notices;   // notice_kept, the oldest first
static char *notice_opened;  // what the one clicked since the last look opens (NULL: none)

static void notice_free(gpointer p) {
  notice_kept *n = p;
  g_free(n->tag), g_free(n->title), g_free(n->body), g_free(n->opens);
  g_free(n);
}

// the one of `tag` no more kept: 1 when it was
static int notice_drop(const char *tag) {
  for (guint i = 0; notices && i < notices->len; i++)
    if (!strcmp(((notice_kept *)g_ptr_array_index(notices, i))->tag, tag)) {
      g_ptr_array_remove_index(notices, i);
      return 1;
    }
  return 0;
}

// one clicked (on the desktop, or by a scripted run): what it opens to the app, the window to the front
static void notice_clicked(const char *tag, const char *opens) {
  fprintf(stdout, "NOTICE TAP %s\n", tag);
  fflush(stdout);
  g_free(notice_opened);
  notice_opened = g_strdup(opens);
  notice_drop(tag);
  bring_back();
}

static void on_notice(GSimpleAction *a, GVariant *v, gpointer data) {
  (void)a, (void)data;
  const char *tag = NULL, *opens = NULL;
  g_variant_get(v, "(&s&s)", &tag, &opens);
  notice_clicked(tag, opens);
}

void mb_host_notice_show(moonbit_string_t channel, moonbit_string_t tag, moonbit_string_t title, moonbit_string_t body,
                         moonbit_string_t opens) {
  (void)channel;  // one kind of notification here: the desktop's settings list the app's, not channels
  notice_kept *n = g_new0(notice_kept, 1);
  n->tag = utf8(tag), n->title = utf8(title), n->body = utf8(body), n->opens = utf8(opens);
  if (!notices) notices = g_ptr_array_new_with_free_func(notice_free);
  notice_drop(n->tag);
  g_ptr_array_add(notices, n);
  fprintf(stdout, "NOTICE %s\t%s\t%s\n", n->tag, n->title, n->body);
  fflush(stdout);
  if (!life_app) return;
  GNotification *g = g_notification_new(n->title);
  g_notification_set_body(g, n->body);
  g_notification_set_default_action_and_target(g, "app.notice", "(ss)", n->tag, n->opens);
  g_application_send_notification(G_APPLICATION(life_app), n->tag, g);
  g_object_unref(g);
}

// The system's own bars (@hostapi.nav_bar): none here, the app draws its own.
int32_t mb_host_nav_bar(moonbit_string_t spec) {
  (void)spec;
  return 0;
}

int32_t mb_host_nav_able(void) { return 0; }

void mb_host_notice_cancel(moonbit_string_t tag) {
  char *t = utf8(tag);
  if (notice_drop(t)) {
    fprintf(stdout, "NOTICE CANCEL %s\n", t);
    fflush(stdout);
  }
  if (life_app) g_application_withdraw_notification(G_APPLICATION(life_app), t);
  g_free(t);
}

// the desktop's settings of notifications opened: its own first (XDG_CURRENT_DESKTOP), else any of them there is
static int notice_settings(void) {
  static const struct {
    const char *desktop, *program, *page;
  } ways[] = {{"GNOME", "gnome-control-center", "notifications"},
              {"KDE", "systemsettings", "kcm_notifications"},
              {"XFCE", "xfce4-notifyd-config", NULL}};
  const char *now = getenv("XDG_CURRENT_DESKTOP");
  for (int pass = 0; pass < 2; pass++)
    for (size_t i = 0; i < G_N_ELEMENTS(ways); i++) {
      if (pass == 0 && !(now && strstr(now, ways[i].desktop))) continue;
      char *path = g_find_program_in_path(ways[i].program);
      char *argv[] = {path, (char *)ways[i].page, NULL};
      gboolean ok = path && g_spawn_async(NULL, argv, NULL, G_SPAWN_DEFAULT, NULL, NULL, NULL, NULL);
      g_free(path);
      if (ok) return 1;
    }
  return 0;
}

// 0: what the desktop allows (1 where the program is an app, 0 not known); 1: ask it (nothing to ask here: 0); 2: its
// answer to an ask (none: -1); 3: its settings of notifications opened (1); 4: the number on the app's icon shown (not
// drawn here: 0)
int32_t mb_host_notice_state(int32_t what) {
  if (what == 0) return life_app ? 1 : 0;
  if (what == 2) return -1;
  if (what == 3) return notice_settings();
  return 0;
}

// the one clicked since the last look, once; no push here
moonbit_string_t mb_host_notice_text(int32_t what) {
  if (what != 0 || !notice_opened) return moonbit_make_string_raw(0);
  moonbit_string_t s = mstr(notice_opened);
  g_clear_pointer(&notice_opened, g_free);
  return s;
}

// a scripted run's (drive 6, 7): the first kept whose title or words hold `words`, clicked (6) or only looked for
static int32_t notice_drive(int click, const char *words) {
  for (guint i = 0; notices && i < notices->len; i++) {
    notice_kept *n = g_ptr_array_index(notices, i);
    if (!strstr(n->title, words) && !strstr(n->body, words)) continue;
    if (click) {
      char *tag = g_strdup(n->tag), *opens = g_strdup(n->opens);
      if (life_app) g_application_withdraw_notification(G_APPLICATION(life_app), tag);
      notice_clicked(tag, opens);
      g_free(tag), g_free(opens);
    }
    return 1;
  }
  return 0;
}

// ---- windows of its own ----

// a window of the app's own (@hostapi.window_open): MBUI_WINDOW said by whoever started it
static int window_run(void) {
  const char *w = getenv("MBUI_WINDOW");
  return w && *w;
}

// Another window of the app's (@hostapi.window_open): the program run again (/proc/self/exe), its environment this
// one's with MBUI_WINDOW=<what>; a run of its own beside this one (window_run), ending as its window closes. (GLib
// reaps it: no G_SPAWN_DO_NOT_REAP_CHILD.)
int32_t mb_host_window_opens(void) { return 1; }
int32_t mb_host_window_open(moonbit_string_t what_s) {
  char *what = utf8(what_s);
  if (!*what) {
    g_free(what);
    return 0;
  }
  char **env = g_environ_setenv(g_get_environ(), "MBUI_WINDOW", what, TRUE);
  g_free(what);
  char *argv[] = {"/proc/self/exe", NULL};
  GError *e = NULL;
  gboolean ok = g_spawn_async(NULL, argv, env, G_SPAWN_DEFAULT, NULL, NULL, NULL, &e);
  g_strfreev(env);
  if (!ok) {
    fprintf(stdout, "linux: no window of its own (%s)\n", e ? e->message : "");
    fflush(stdout);
    g_clear_error(&e);
    return 0;
  }
  return 1;
}

// ---- once for its person ----

// the app's GtkApplication: started again, the call it hands over with carries the launcher's activation token (its
// environment's: Wayland's XDG_ACTIVATION_TOKEN, X11's DESKTOP_STARTUP_ID), which the one that runs takes (GTK's own,
// as it emits `activate` or `open`) for its window to come to the front with
typedef GtkApplication MbLifeApp;
typedef GtkApplicationClass MbLifeAppClass;
G_DEFINE_TYPE(MbLifeApp, mb_life_app, GTK_TYPE_APPLICATION)

static void life_platform_data(GApplication *a, GVariantBuilder *b) {
  G_APPLICATION_CLASS(g_type_class_peek(G_TYPE_APPLICATION))->add_platform_data(a, b);
  const char *token = getenv("XDG_ACTIVATION_TOKEN"), *startup = getenv("DESKTOP_STARTUP_ID");
  if (token && *token) g_variant_builder_add(b, "{sv}", "activation-token", g_variant_new_string(token));
  if (startup && *startup) g_variant_builder_add(b, "{sv}", "desktop-startup-id", g_variant_new_string(startup));
}
static void mb_life_app_class_init(MbLifeAppClass *k) { G_APPLICATION_CLASS(k)->add_platform_data = life_platform_data; }
static void mb_life_app_init(MbLifeApp *a) { (void)a; }

// started again with nothing, or with links: the window to the front, the links (the app's) to the app
static void on_life_activate(GApplication *a, gpointer data) {
  (void)a, (void)data;
  bring_back();
}
static void on_life_open(GApplication *a, GFile **files, gint n, const char *hint, gpointer data) {
  (void)a, (void)hint, (void)data;
  bring_back();
  for (gint i = 0; i < n; i++) {
    char *u = g_file_get_uri(files[i]);
    if (u && app_link(u)) say_link(u);
    g_free(u);
  }
}
static void on_life_quit(GSimpleAction *q, GVariant *v, gpointer data) {
  (void)q, (void)v, (void)data;
  quit();
}

// As the program starts, before main (its constructors): whether it is the app's one run (else it has handed what it
// was started with over to the one that runs, and ends here).
__attribute__((constructor)) static void life_begin(void) {
  const char *id = app_id();
  if (!*id) return;
  // what the desktop knows its window by (Wayland's app id, X11's class), its icon's name
  g_set_prgname(id);
  // (a window of its own: beside the one run, not handed to it)
  if (window_run()) return;
  if (!g_application_id_is_valid(id)) {
    fprintf(stdout, "linux: MBUI_APP_ID %s is no application id: not once for its person\n", id);
    fflush(stdout);
    return;
  }
  read_started_with();
  life_app = g_object_new(mb_life_app_get_type(), "application-id", id, "flags", G_APPLICATION_HANDLES_OPEN, NULL);
  GSimpleAction *q = g_simple_action_new("quit", NULL);
  g_signal_connect(q, "activate", G_CALLBACK(on_life_quit), NULL);
  g_action_map_add_action(G_ACTION_MAP(life_app), G_ACTION(q));
  g_object_unref(q);
  GSimpleAction *notice = g_simple_action_new("notice", G_VARIANT_TYPE("(ss)"));
  g_signal_connect(notice, "activate", G_CALLBACK(on_notice), NULL);
  g_action_map_add_action(G_ACTION_MAP(life_app), G_ACTION(notice));
  g_object_unref(notice);
  GError *e = NULL;
  if (!g_application_register(G_APPLICATION(life_app), NULL, &e)) {
    // (no session bus: it runs, though not once for its person)
    fprintf(stdout, "linux: not on the session bus (%s): not once for its person\n", e ? e->message : "");
    fflush(stdout);
    g_clear_error(&e);
    g_clear_object(&life_app);
    return;
  }
  if (!g_application_get_is_remote(G_APPLICATION(life_app))) {
    g_signal_connect(life_app, "activate", G_CALLBACK(on_life_activate), NULL);
    g_signal_connect(life_app, "open", G_CALLBACK(on_life_open), NULL);
    return;
  }
  if (started_link) {
    GFile *f = g_file_new_for_uri(started_link);
    g_application_open(G_APPLICATION(life_app), &f, 1, "");
    g_object_unref(f);
  } else {
    g_application_activate(G_APPLICATION(life_app));
  }
  // (the call sent before the program ends)
  GDBusConnection *bus = g_application_get_dbus_connection(G_APPLICATION(life_app));
  if (bus) g_dbus_connection_flush_sync(bus, NULL, NULL);
  fprintf(stdout, "linux: the app runs already: handed to it%s\n", started_link ? " with a link" : "");
  fflush(stdout);
  exit(0);
}

// ---- its icon among the desktop's apps' icons (StatusNotifierItem), and its menu (dbusmenu) ----
// KDE's StatusNotifierItem, which the desktops that show apps' icons take (Ubuntu's GNOME through its AppIndicator
// extension), on the session bus: the item (/StatusNotifierItem) under a name of its own, given to the desktop's
// watcher as it comes (and again as it comes back), its menu (/MenuBar) by Canonical's dbusmenu, which those hosts
// draw themselves.

static const char tray_xml[] =
    "<node>"
    " <interface name='org.kde.StatusNotifierItem'>"
    "  <property name='Category' type='s' access='read'/>"
    "  <property name='Id' type='s' access='read'/>"
    "  <property name='Title' type='s' access='read'/>"
    "  <property name='Status' type='s' access='read'/>"
    "  <property name='WindowId' type='i' access='read'/>"
    "  <property name='IconName' type='s' access='read'/>"
    "  <property name='ItemIsMenu' type='b' access='read'/>"
    "  <property name='Menu' type='o' access='read'/>"
    "  <property name='ToolTip' type='(sa(iiay)ss)' access='read'/>"
    "  <method name='ContextMenu'><arg type='i' direction='in'/><arg type='i' direction='in'/></method>"
    "  <method name='Activate'><arg type='i' direction='in'/><arg type='i' direction='in'/></method>"
    "  <method name='SecondaryActivate'><arg type='i' direction='in'/><arg type='i' direction='in'/></method>"
    "  <method name='Scroll'><arg type='i' direction='in'/><arg type='s' direction='in'/></method>"
    "  <method name='ProvideXdgActivationToken'><arg type='s' direction='in'/></method>"
    "  <signal name='NewTitle'/>"
    " </interface>"
    " <interface name='com.canonical.dbusmenu'>"
    "  <property name='Version' type='u' access='read'/>"
    "  <property name='TextDirection' type='s' access='read'/>"
    "  <property name='Status' type='s' access='read'/>"
    "  <property name='IconThemePath' type='as' access='read'/>"
    "  <method name='GetLayout'>"
    "   <arg type='i' direction='in'/><arg type='i' direction='in'/><arg type='as' direction='in'/>"
    "   <arg type='u' direction='out'/><arg type='(ia{sv}av)' direction='out'/>"
    "  </method>"
    "  <method name='GetGroupProperties'>"
    "   <arg type='ai' direction='in'/><arg type='as' direction='in'/><arg type='a(ia{sv})' direction='out'/>"
    "  </method>"
    "  <method name='GetProperty'>"
    "   <arg type='i' direction='in'/><arg type='s' direction='in'/><arg type='v' direction='out'/>"
    "  </method>"
    "  <method name='Event'>"
    "   <arg type='i' direction='in'/><arg type='s' direction='in'/><arg type='v' direction='in'/>"
    "   <arg type='u' direction='in'/>"
    "  </method>"
    "  <method name='EventGroup'><arg type='a(isvu)' direction='in'/><arg type='ai' direction='out'/></method>"
    "  <method name='AboutToShow'><arg type='i' direction='in'/><arg type='b' direction='out'/></method>"
    "  <method name='AboutToShowGroup'>"
    "   <arg type='ai' direction='in'/><arg type='ai' direction='out'/><arg type='ai' direction='out'/>"
    "  </method>"
    "  <signal name='LayoutUpdated'><arg type='u'/><arg type='i'/></signal>"
    " </interface>"
    "</node>";

static GDBusNodeInfo *tray_node;
static GDBusConnection *tray_bus;
static char *tray_name;          // the item's name on the bus
static int tray_named;           // that name is the item's (the watcher reads it only then)
static int tray_watched;         // a watcher on the bus, to give the item to
static guint tray_revision = 1;

// the menu's items, as the app gave them (its "tray" menu): their words ({app} the app's name), their role ("show",
// "quit"), or the action said back to the app (`menu`); item i is the menu's id i + 1 (0 the menu itself)
#define TRAY_MOST 16
static struct {
  char *title;
  char role[16];
  char *action;
  int separator;
} tray_items[TRAY_MOST];
static int tray_n;

// one of the menu's items chosen
static void tray_chose(int i) {
  if (i < 0 || i >= tray_n) return;
  if (!strcmp(tray_items[i].role, "quit")) quit();
  bring_back();
  const char *a = tray_items[i].action;
  if (strcmp(tray_items[i].role, "show") == 0 || !a || !*a) return;
  GString *b = g_string_new("{\"menu\":\"");
  json_put(b, a);
  g_string_append(b, "\"}");
  say_system(b->str, b->len);
  g_string_free(b, TRUE);
}

// an item's properties (dbusmenu's: its words, mnemonics' underscores doubled; a separator's type)
static GVariant *tray_props(int id) {
  GVariantBuilder p;
  g_variant_builder_init(&p, G_VARIANT_TYPE("a{sv}"));
  if (id == 0) {
    g_variant_builder_add(&p, "{sv}", "children-display", g_variant_new_string("submenu"));
  } else if (tray_items[id - 1].separator) {
    g_variant_builder_add(&p, "{sv}", "type", g_variant_new_string("separator"));
  } else {
    GString *w = g_string_new(NULL);
    for (const char *c = tray_items[id - 1].title ? tray_items[id - 1].title : ""; *c; c++) {
      if (*c == '_') g_string_append_c(w, '_');
      g_string_append_c(w, *c);
    }
    g_variant_builder_add(&p, "{sv}", "label", g_variant_new_string(w->str));
    g_string_free(w, TRUE);
  }
  return g_variant_builder_end(&p);
}

// the menu from `id` down (its items under the menu itself)
static GVariant *tray_layout(int id) {
  GVariantBuilder kids;
  g_variant_builder_init(&kids, G_VARIANT_TYPE("av"));
  for (int i = 0; id == 0 && i < tray_n; i++) g_variant_builder_add(&kids, "v", tray_layout(i + 1));
  return g_variant_new("(i@a{sv}@av)", id, tray_props(id), g_variant_builder_end(&kids));
}

static int tray_has(int id) { return id >= 0 && id <= tray_n; }

static void tray_call(GDBusConnection *c, const char *sender, const char *path, const char *iface, const char *method,
                      GVariant *args, GDBusMethodInvocation *inv, gpointer data) {
  (void)c, (void)sender, (void)path, (void)data;
  if (!strcmp(iface, "org.kde.StatusNotifierItem")) {
    if (!strcmp(method, "ProvideXdgActivationToken")) {
      const char *t = NULL;
      g_variant_get(args, "(&s)", &t);
      g_free(activation_token);
      activation_token = g_strdup(t);
    }
    g_dbus_method_invocation_return_value(inv, NULL);
    // clicked: the window back (Scroll and the context menu: nothing; the host draws the menu)
    if (!strcmp(method, "Activate") || !strcmp(method, "SecondaryActivate")) bring_back();
    return;
  }
  if (!strcmp(method, "GetLayout")) {
    gint parent = 0;
    g_variant_get_child(args, 0, "i", &parent);
    g_dbus_method_invocation_return_value(inv, g_variant_new("(u@(ia{sv}av))", tray_revision,
                                                             tray_layout(tray_has(parent) ? parent : 0)));
  } else if (!strcmp(method, "GetGroupProperties")) {
    // (none asked for: all of them)
    GVariantIter *ids = NULL;
    gint id;
    g_variant_get_child(args, 0, "ai", &ids);
    GVariantBuilder out;
    g_variant_builder_init(&out, G_VARIANT_TYPE("a(ia{sv})"));
    if (g_variant_iter_n_children(ids) == 0)
      for (id = 0; id <= tray_n; id++) g_variant_builder_add(&out, "(i@a{sv})", id, tray_props(id));
    while (g_variant_iter_next(ids, "i", &id))
      if (tray_has(id)) g_variant_builder_add(&out, "(i@a{sv})", id, tray_props(id));
    g_variant_iter_free(ids);
    g_dbus_method_invocation_return_value(inv, g_variant_new("(@a(ia{sv}))", g_variant_builder_end(&out)));
  } else if (!strcmp(method, "GetProperty")) {
    gint id = 0;
    const char *name = NULL;
    g_variant_get(args, "(i&s)", &id, &name);
    GVariant *props = tray_props(tray_has(id) ? id : 0), *v = g_variant_lookup_value(props, name, NULL);
    g_variant_unref(g_variant_ref_sink(props));
    if (v) {
      g_dbus_method_invocation_return_value(inv, g_variant_new("(v)", v));
      g_variant_unref(v);
    } else {
      g_dbus_method_invocation_return_dbus_error(inv, "com.canonical.dbusmenu.Error", "no such property");
    }
  } else if (!strcmp(method, "Event") || !strcmp(method, "EventGroup")) {
    // (answered first: a chosen `quit` ends the program)
    int chose = -1;
    if (!strcmp(method, "Event")) {
      gint id = 0;
      const char *what = NULL;
      g_variant_get(args, "(i&svu)", &id, &what, NULL, NULL);
      if (!strcmp(what, "clicked")) chose = id - 1;
      g_dbus_method_invocation_return_value(inv, NULL);
    } else {
      GVariantIter *events = NULL;
      gint id;
      const char *what;
      g_variant_get(args, "(a(isvu))", &events);
      while (g_variant_iter_next(events, "(i&svu)", &id, &what, NULL, NULL))
        if (!strcmp(what, "clicked")) chose = id - 1;
      g_variant_iter_free(events);
      g_dbus_method_invocation_return_value(inv, g_variant_new("(@ai)", g_variant_new_array(G_VARIANT_TYPE_INT32, NULL, 0)));
    }
    if (chose >= 0) tray_chose(chose);
  } else if (!strcmp(method, "AboutToShow")) {
    g_dbus_method_invocation_return_value(inv, g_variant_new("(b)", FALSE));
  } else if (!strcmp(method, "AboutToShowGroup")) {
    GVariant *none = g_variant_new_array(G_VARIANT_TYPE_INT32, NULL, 0);
    g_dbus_method_invocation_return_value(inv, g_variant_new("(@ai@ai)", none, g_variant_new_array(G_VARIANT_TYPE_INT32, NULL, 0)));
  } else {
    g_dbus_method_invocation_return_dbus_error(inv, "org.freedesktop.DBus.Error.UnknownMethod", method);
  }
}

static GVariant *tray_get(GDBusConnection *c, const char *sender, const char *path, const char *iface, const char *name,
                          GError **e, gpointer data) {
  (void)c, (void)sender, (void)path, (void)e, (void)data;
  if (!strcmp(iface, "com.canonical.dbusmenu")) {
    if (!strcmp(name, "Version")) return g_variant_new_uint32(3);
    if (!strcmp(name, "TextDirection")) return g_variant_new_string("ltr");
    if (!strcmp(name, "Status")) return g_variant_new_string("normal");
    return g_variant_new_strv(NULL, 0);  // IconThemePath
  }
  if (!strcmp(name, "Category")) return g_variant_new_string("ApplicationStatus");
  if (!strcmp(name, "Id") || !strcmp(name, "IconName")) return g_variant_new_string(app_id());
  if (!strcmp(name, "Title")) return g_variant_new_string(app_name());
  if (!strcmp(name, "Status")) return g_variant_new_string("Active");
  if (!strcmp(name, "WindowId")) return g_variant_new_int32(0);
  if (!strcmp(name, "ItemIsMenu")) return g_variant_new_boolean(FALSE);
  if (!strcmp(name, "Menu")) return g_variant_new_object_path("/MenuBar");
  // ToolTip: no icon of its own, the app's name
  return g_variant_new("(s@a(iiay)ss)", "", g_variant_new_array(G_VARIANT_TYPE("(iiay)"), NULL, 0), app_name(), "");
}

static const GDBusInterfaceVTable tray_vtable = {tray_call, tray_get, NULL, {0}};

// the item given to the watcher: taken, its icon shows
static void on_tray_taken(GObject *o, GAsyncResult *r, gpointer data) {
  (void)data;
  GError *e = NULL;
  GVariant *v = g_dbus_connection_call_finish(G_DBUS_CONNECTION(o), r, &e);
  tray_on = v != NULL;
  fprintf(stdout, "linux: its icon %s\n", v ? "among the desktop's apps' icons" : e ? e->message : "not taken");
  fflush(stdout);
  if (v) g_variant_unref(v);
  g_clear_error(&e);
}

// the item given to the watcher, once both are there
static void tray_give(void) {
  if (!tray_named || !tray_watched) return;
  g_dbus_connection_call(tray_bus, "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
                         "org.kde.StatusNotifierWatcher", "RegisterStatusNotifierItem", g_variant_new("(s)", tray_name),
                         NULL, G_DBUS_CALL_FLAGS_NONE, -1, NULL, on_tray_taken, NULL);
}

static void on_tray_named(GDBusConnection *c, const char *name, gpointer data) {
  (void)c, (void)name, (void)data;
  tray_named = 1;
  tray_give();
}

static void on_watcher_up(GDBusConnection *c, const char *name, const char *owner, gpointer data) {
  (void)c, (void)name, (void)owner, (void)data;
  tray_watched = 1;
  tray_give();
}

// the desktop shows apps' icons no more: the window back, if it was put away (nothing else would bring it)
static void on_watcher_gone(GDBusConnection *c, const char *name, gpointer data) {
  (void)c, (void)name, (void)data;
  tray_watched = 0;
  if (!tray_on) return;
  tray_on = 0;
  fprintf(stdout, "linux: no apps' icons on the desktop now\n");
  fflush(stdout);
  if (put_away_at >= 0) bring_back();
}

static void tray_start(void) {
  tray_bus = g_application_get_dbus_connection(G_APPLICATION(life_app));
  tray_node = tray_bus ? g_dbus_node_info_new_for_xml(tray_xml, NULL) : NULL;
  if (!tray_node) return;
  g_dbus_connection_register_object(tray_bus, "/StatusNotifierItem", tray_node->interfaces[0], &tray_vtable, NULL, NULL,
                                    NULL);
  g_dbus_connection_register_object(tray_bus, "/MenuBar", tray_node->interfaces[1], &tray_vtable, NULL, NULL, NULL);
  tray_name = g_strdup_printf("org.kde.StatusNotifierItem-%d-1", (int)getpid());
  g_bus_own_name_on_connection(tray_bus, tray_name, G_BUS_NAME_OWNER_FLAGS_NONE, on_tray_named, NULL, NULL, NULL);
  g_bus_watch_name_on_connection(tray_bus, "org.kde.StatusNotifierWatcher", G_BUS_NAME_WATCHER_FLAGS_NONE, on_watcher_up,
                                 on_watcher_gone, NULL, NULL);
}

// `in`'s words with {app} the app's name
static char *tray_words(const char *in) {
  const char *at = strstr(in, "{app}");
  if (!at) return g_strdup(in);
  return g_strdup_printf("%.*s%s%s", (int)(at - in), in, app_name(), at + 5);
}

// The app's menus (@hostapi.menu_setup): no menu bar of the app's here; its "tray" menu is its icon's.
void mb_host_menu_setup(moonbit_string_t json_s) {
  char *text = utf8(json_s);
  const char *p = text;
  jv menus;
  int ok = jparse(&p, &menus, 0) && menus.kind == 'a';
  for (int i = 0; ok && i < menus.n; i++) {
    const jv *m = &menus.at[i];
    if (strcmp(jtext(m, "role"), "tray") != 0) continue;
    const jv *items = jget(m, "items");
    if (!items || items->kind != 'a') break;
    for (int k = 0; k < tray_n; k++) g_free(tray_items[k].title), g_free(tray_items[k].action);
    tray_n = 0;
    for (int k = 0; k < items->n && tray_n < TRAY_MOST; k++) {
      const jv *it = &items->at[k];
      if (it->kind != 'o') continue;
      memset(&tray_items[tray_n], 0, sizeof tray_items[0]);
      const jv *sep = jget(it, "separator");
      tray_items[tray_n].separator = sep && sep->kind == 't';
      tray_items[tray_n].title = tray_words(jtext(it, "title"));
      g_strlcpy(tray_items[tray_n].role, jtext(it, "role"), sizeof tray_items[0].role);
      tray_items[tray_n].action = g_strdup(jtext(it, "action"));
      tray_n++;
    }
    // (the hosts that show it asked to read it again)
    tray_revision++;
    if (tray_bus)
      g_dbus_connection_emit_signal(tray_bus, NULL, "/MenuBar", "com.canonical.dbusmenu", "LayoutUpdated",
                                    g_variant_new("(ui)", tray_revision, 0), NULL);
    break;
  }
  jv_free(&menus);
  g_free(text);
}

// ---- the network ----

// the way out now: the interface and the address a datagram to any address out there goes from ("": none), as the
// kernel routes it (a UDP socket connected: nothing is sent)
static void network_way(char *out, size_t cap) {
  out[0] = 0;
  int s = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);
  if (s < 0) return;
  struct sockaddr_in to = {0}, from = {0};
  socklen_t n = sizeof from;
  to.sin_family = AF_INET;
  to.sin_port = htons(53);
  to.sin_addr.s_addr = htonl(0x01010101);  // 1.1.1.1
  if (connect(s, (struct sockaddr *)&to, sizeof to) == 0 && getsockname(s, (struct sockaddr *)&from, &n) == 0) {
    char a[INET_ADDRSTRLEN] = "";
    inet_ntop(AF_INET, &from.sin_addr, a, sizeof a);
    struct ifaddrs *all = NULL;
    const char *name = "";
    if (getifaddrs(&all) == 0)
      for (struct ifaddrs *i = all; i; i = i->ifa_next)
        if (i->ifa_addr && i->ifa_addr->sa_family == AF_INET &&
            ((struct sockaddr_in *)i->ifa_addr)->sin_addr.s_addr == from.sin_addr.s_addr) {
          name = i->ifa_name;
          break;
        }
    snprintf(out, cap, "%s/%s", name, a);
    if (all) freeifaddrs(all);
  }
  close(s);
}

static char network_was[96];
static int network_seen;

// another way out than the one before (not the first seen, nor none): said
static void network_look(void) {
  char now[96];
  network_way(now, sizeof now);
  int changed = network_seen && now[0] && strcmp(now, network_was) != 0;
  if (now[0] || !network_seen) {
    g_strlcpy(network_was, now, sizeof network_was);
    network_seen = 1;
  }
  if (changed) {
    fprintf(stdout, "linux: network now %s\n", now);
    fflush(stdout);
    say_system("{\"network\":true}", 16);
  }
}

static void on_network_changed(GNetworkMonitor *m, gboolean up, gpointer data) {
  (void)m, (void)up, (void)data;
  network_look();
}

// ---- sleep ----

// logind's PrepareForSleep: true as the computer goes to sleep, false as it wakes
static void on_sleep(GDBusConnection *c, const char *sender, const char *path, const char *iface, const char *signal,
                     GVariant *args, gpointer data) {
  (void)c, (void)sender, (void)path, (void)iface, (void)signal, (void)data;
  gboolean going = FALSE;
  g_variant_get(args, "(b)", &going);
  if (going) {
    asleep_at = boot_ms();
    return;
  }
  // (a sleep whose start was not seen taken as a minute's, as the Mac's)
  say_shown(asleep_at >= 0 ? asleep_at : boot_ms() - 60000);
  asleep_at = -1;
}

static void on_system_bus(GObject *o, GAsyncResult *r, gpointer data) {
  (void)o, (void)data;
  GDBusConnection *sys = g_bus_get_finish(r, NULL);
  if (!sys) return;
  g_dbus_connection_signal_subscribe(sys, "org.freedesktop.login1", "org.freedesktop.login1.Manager", "PrepareForSleep",
                                     "/org/freedesktop/login1", NULL, G_DBUS_SIGNAL_FLAGS_NONE, on_sleep, NULL, NULL);
}

// ---- the number on its icon in the desktop's dock (@hostapi.set_badge) ----
// Canonical's LauncherEntry, which Ubuntu's dock and KDE's task manager draw (GNOME's own dock shows none): the count
// said on the session bus for the app's desktop entry (application://<id>.desktop) as it changes, and given to a dock
// that asks for it (Query: one started after it was said). Only where the program is an app (its id: its entry's name).
#define BADGE_PATH "/com/canonical/unity/launcherentry/mbui"
static int badge_n;
static guint badge_object;

static GVariant *badge_state(void) {
  char *uri = g_strdup_printf("application://%s.desktop", app_id());
  GVariantBuilder b;
  g_variant_builder_init(&b, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&b, "{sv}", "count", g_variant_new_int64(badge_n));
  g_variant_builder_add(&b, "{sv}", "count-visible", g_variant_new_boolean(badge_n > 0));
  GVariant *v = g_variant_new("(sa{sv})", uri, &b);
  g_free(uri);
  return v;
}

static void on_badge_call(GDBusConnection *c, const char *sender, const char *path, const char *iface,
                          const char *method, GVariant *args, GDBusMethodInvocation *inv, gpointer data) {
  (void)c, (void)sender, (void)path, (void)iface, (void)args, (void)data;
  if (!strcmp(method, "Query")) g_dbus_method_invocation_return_value(inv, badge_state());
  else g_dbus_method_invocation_return_dbus_error(inv, "org.freedesktop.DBus.Error.UnknownMethod", method);
}

void mb_host_set_badge(int32_t n) {
  if (n < 0) n = 0;
  if (n == badge_n && badge_object) return;
  badge_n = n;
  GDBusConnection *bus = life_app && *app_id() ? g_application_get_dbus_connection(G_APPLICATION(life_app)) : NULL;
  if (!bus) return;
  if (!badge_object) {
    static const char xml[] =
        "<node><interface name='com.canonical.Unity.LauncherEntry'>"
        "<method name='Query'><arg type='s' direction='out'/><arg type='a{sv}' direction='out'/></method>"
        "<signal name='Update'><arg type='s'/><arg type='a{sv}'/></signal></interface></node>";
    static const GDBusInterfaceVTable vt = {on_badge_call, NULL, NULL, {0}};
    GDBusNodeInfo *info = g_dbus_node_info_new_for_xml(xml, NULL);
    badge_object = g_dbus_connection_register_object(bus, BADGE_PATH, info->interfaces[0], &vt, NULL, NULL, NULL);
    g_dbus_node_info_unref(info);
  }
  g_dbus_connection_emit_signal(bus, NULL, BADGE_PATH, "com.canonical.Unity.LauncherEntry", "Update", badge_state(),
                                NULL);
}

// ---- as the window is made ----

// once the window is made, before it shows: the app's (the desktop knows it by the app's id, its Quit asks the app's),
// its icon among the desktop's, the network and sleep watched, the link it was started with to the app
static void life_start(const char *title) {
  window_title = g_strdup(title);
  g_signal_connect(win, "close-request", G_CALLBACK(on_close), NULL);
  if (life_app) {
    gtk_window_set_application(GTK_WINDOW(win), life_app);
    tray_start();
  }
  network_look();
  g_signal_connect(g_network_monitor_get_default(), "network-changed", G_CALLBACK(on_network_changed), NULL);
  g_bus_get(G_BUS_TYPE_SYSTEM, NULL, on_system_bus, NULL);
  if (started_link) say_link(started_link);
}
