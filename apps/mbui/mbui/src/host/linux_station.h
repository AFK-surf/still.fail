// This machine's station on Linux (@hostapi.local_station, local_station_act), as mac_app.m and win_station.h have it:
// its data (~/.stillfail), whether it runs (run/station.json's pid alive) and by what (the systemd user service the
// installer made, stillfail-station.service: cloud/src/install.ts; or a process started by hand), its release, whether
// the installer put one there (<data>/app), the workspace its data is in (mesh/cloud.json); what is being done to it
// and what went wrong last. "" where there is neither data nor a service. Its acts, on a thread of their own: start,
// stop, restart (the service's, systemctl --user; one started by hand only stopped), the log or the folder opened (the
// desktop's own app for them), and the station's installer (install.sh in sh, as the person would run it: with a token
// a workspace joined, without one the station here brought up to date and run as the service). Included by
// linux_app.c after linux_life.h (its json_put, and mini_json.h's jparse).
#include <errno.h>
#include <signal.h>

#define STATION_UNIT "stillfail-station.service"

static GMutex local_lock;
static char local_doing[16];  // what is being done ("": nothing), under local_lock
static char *local_failed;    // what went wrong last (NULL: nothing), under local_lock
static char *local_said;      // the last the installer said, under local_lock

static void local_set(char **at, const char *s) {
  g_free(*at);
  *at = g_strdup(s);
}

static char *local_data(void) { return g_build_filename(g_get_home_dir(), ".stillfail", NULL); }

// whether the installer's service is there (its unit, where systemd looks for a user's)
static int local_service(void) {
  char *unit = g_build_filename(g_get_user_config_dir(), "systemd", "user", STATION_UNIT, NULL);
  int there = g_file_test(unit, G_FILE_TEST_EXISTS);
  g_free(unit);
  return there;
}

// a JSON file of the data's, read: its value (jv_free it), kind 0 where there is none
static jv local_json(const char *data, const char *name) {
  jv v = {0};
  char *path = g_build_filename(data, name, NULL), *text = NULL;
  if (g_file_get_contents(path, &text, NULL, NULL)) {
    const char *p = text;
    if (!jparse(&p, &v, 0)) jv_free(&v), memset(&v, 0, sizeof v);
  }
  g_free(text);
  g_free(path);
  return v;
}

static int local_alive(double pid) { return pid > 0 && (kill((pid_t)pid, 0) == 0 || errno == EPERM); }

// `"key":"value"` (and a comma before it)
static void local_field(GString *o, const char *key, const char *value) {
  g_string_append_printf(o, ",\"%s\":\"", key);
  json_put(o, value);
  g_string_append_c(o, '"');
}

moonbit_string_t mb_host_local_station(void) {
  char *data = local_data();
  int there = g_file_test(data, G_FILE_TEST_IS_DIR), service = local_service();
  g_mutex_lock(&local_lock);
  int busy = local_doing[0] || local_failed;
  g_mutex_unlock(&local_lock);
  // none here, and nothing being done or gone wrong about it: ""; one being installed is said before it is there
  if (!there && !service && !busy) {
    g_free(data);
    return moonbit_make_string_raw(0);
  }
  GString *o = g_string_new("{");
  jv run = local_json(data, "run/station.json");
  int alive = local_alive(jnum(&run, "pid", -1));
  g_string_append_printf(o, "\"runner\":\"%s\"", !alive ? "none" : service ? "service" : "other");
  if (there || service) local_field(o, "data", data);
  const char *version = alive ? jtext(&run, "version") : "";
  char *build = NULL;
  if (!*version && service) {
    char *path = g_build_filename(data, "app", "BUILD", NULL), *text = NULL;
    if (g_file_get_contents(path, &text, NULL, NULL) && g_ascii_isdigit(g_strstrip(text)[0]))
      build = g_strdup_printf("0.1.%d", atoi(text)), version = build;
    g_free(text);
    g_free(path);
  }
  if (*version) local_field(o, "version", version);
  g_free(build);
  jv_free(&run);
  char *app = g_build_filename(data, "app", NULL);
  if (g_file_test(app, G_FILE_TEST_IS_DIR)) g_string_append(o, ",\"installed\":true");
  g_free(app);
  if (service) g_string_append(o, ",\"service\":{\"kind\":\"systemd\",\"name\":\"" STATION_UNIT "\"}");
  jv cloud = local_json(data, "mesh/cloud.json");
  const char *ws = jtext(&cloud, "workspace");
  if (*ws) {
    g_string_append(o, ",\"workspace\":{\"id\":\"");
    json_put(o, ws);
    g_string_append_c(o, '"');
    static const char *const keys[][2] = {{"workspace_name", "name"}, {"station", "station"}, {"name", "stationName"}};
    for (int i = 0; i < 3; i++)
      if (*jtext(&cloud, keys[i][0])) local_field(o, keys[i][1], jtext(&cloud, keys[i][0]));
    const jv *removed = jget(&cloud, "removed_at");
    g_string_append_printf(o, ",\"removed\":%s}", removed && removed->kind != 'z' ? "true" : "false");
  }
  jv_free(&cloud);
  g_mutex_lock(&local_lock);
  if (local_doing[0]) {
    g_string_append_printf(o, ",\"doing\":\"%s\"", local_doing);
    if (local_said) local_field(o, "said", local_said);
  }
  if (local_failed) local_field(o, "failed", local_failed);
  g_mutex_unlock(&local_lock);
  g_string_append_c(o, '}');
  moonbit_string_t s = mstr(o->str);
  g_string_free(o, TRUE);
  g_free(data);
  return s;
}

typedef struct {
  char **argv;
  char *channel;  // the installer's release channel (STILLFAIL_CHANNEL), NULL none
} local_job;

// `argv` run, what it says read as it comes (the installer's steps: its last line, local_said); NULL when it ended well,
// else what it said last (g_free it)
static char *local_run(local_job *j) {
  GSubprocessLauncher *l = g_subprocess_launcher_new(G_SUBPROCESS_FLAGS_STDOUT_PIPE | G_SUBPROCESS_FLAGS_STDERR_MERGE);
  if (j->channel) g_subprocess_launcher_setenv(l, "STILLFAIL_CHANNEL", j->channel, TRUE);
  GError *e = NULL;
  GSubprocess *p = g_subprocess_launcher_spawnv(l, (const char *const *)j->argv, &e);
  g_object_unref(l);
  if (!p) {
    char *why = g_strdup(e ? e->message : "not started");
    g_clear_error(&e);
    return why;
  }
  GDataInputStream *in = g_data_input_stream_new(g_subprocess_get_stdout_pipe(p));
  char *line, *last = NULL;
  while ((line = g_data_input_stream_read_line_utf8(in, NULL, NULL, NULL))) {
    g_strstrip(line);
    if (!*line) {
      g_free(line);
      continue;
    }
    g_free(last);
    last = g_strdup(line);
    g_mutex_lock(&local_lock);
    local_set(&local_said, line);
    g_mutex_unlock(&local_lock);
    g_free(line);
    mb_app_wake();
  }
  g_object_unref(in);
  g_subprocess_wait(p, NULL, NULL);
  int ok = g_subprocess_get_successful(p);
  int code = g_subprocess_get_if_exited(p) ? g_subprocess_get_exit_status(p) : -1;
  g_object_unref(p);
  fprintf(stdout, "linux: %s exited %d\n", j->argv[0], code);
  fflush(stdout);
  if (ok) {
    g_free(last);
    return NULL;
  }
  return last ? last : g_strdup_printf("exit %d", code);
}

static gpointer local_thread(gpointer arg) {
  local_job *j = arg;
  char *failed = local_run(j);
  g_mutex_lock(&local_lock);
  local_doing[0] = 0;
  local_set(&local_failed, failed);
  local_set(&local_said, NULL);
  g_mutex_unlock(&local_lock);
  g_free(failed);
  g_strfreev(j->argv);
  g_free(j->channel);
  g_free(j);
  mb_app_wake();
  return NULL;
}

// `verb` begun with `argv` (taken) on a thread of its own, unless something is being done already ("busy")
static void local_begin(const char *verb, char **argv, const char *channel) {
  g_mutex_lock(&local_lock);
  if (local_doing[0]) {
    local_set(&local_failed, "busy");
    g_mutex_unlock(&local_lock);
    g_strfreev(argv);
    schedule();
    return;
  }
  g_strlcpy(local_doing, verb, sizeof local_doing);
  local_set(&local_failed, NULL);
  local_set(&local_said, NULL);
  g_mutex_unlock(&local_lock);
  local_job *j = g_new0(local_job, 1);
  j->argv = argv;
  j->channel = g_strdup(channel);
  g_thread_unref(g_thread_new("station", local_thread, j));
  schedule();
}

static void local_fail(const char *why) {
  g_mutex_lock(&local_lock);
  local_set(&local_failed, why);
  g_mutex_unlock(&local_lock);
  schedule();
}

// what may be put in a shell's command as it is: nothing but what a URL or a token is made of
static int sh_plain(const char *s) {
  for (; *s; s++)
    if (!g_ascii_isalnum(*s) && !strchr(":/.-_~?&=%+", *s)) return 0;
  return 1;
}

void mb_host_local_station_act(moonbit_string_t action) {
  char *a = utf8(action), *data = local_data();
  // `install {…}`, `update {…}`: the station's installer, install.sh of the cloud (`origin`), a token or none, the
  // channel the app is on
  int install = g_str_has_prefix(a, "install "), update = g_str_has_prefix(a, "update ");
  if (install || update) {
    jv ask = {0};
    const char *p = a + (install ? 8 : 7);
    int ok = jparse(&p, &ask, 0) && ask.kind == 'o';
    const char *origin = ok ? jtext(&ask, "origin") : "", *token = ok ? jtext(&ask, "token") : "";
    if ((g_str_has_prefix(origin, "https://") || g_str_has_prefix(origin, "http://")) && sh_plain(origin) &&
        sh_plain(token)) {
      char *script = g_strdup_printf("curl -fsSL '%s/install.sh' | sh -s -- %s", origin, token);
      char **argv = g_new0(char *, 4);
      argv[0] = g_strdup("sh"), argv[1] = g_strdup("-c"), argv[2] = script;
      local_begin(install ? "install" : "update", argv, !strcmp(jtext(&ask, "channel"), "beta") ? "beta" : NULL);
    } else {
      local_fail("origin");
    }
    jv_free(&ask);
  } else if (!strcmp(a, "log") || !strcmp(a, "folder")) {
    // (the desktop's own app for it: its text editor, its file manager)
    char *path = !strcmp(a, "log") ? g_build_filename(data, "stillfail.log", NULL) : g_strdup(data);
    GFile *f = g_file_new_for_path(path);
    GtkFileLauncher *l = gtk_file_launcher_new(f);
    gtk_file_launcher_launch(l, GTK_WINDOW(win), NULL, NULL, NULL);
    g_object_unref(l);
    g_object_unref(f);
    g_free(path);
  } else if (!strcmp(a, "start") || !strcmp(a, "stop") || !strcmp(a, "restart")) {
    if (local_service()) {
      char **argv = g_new0(char *, 5);
      argv[0] = g_strdup("systemctl"), argv[1] = g_strdup("--user"), argv[2] = g_strdup(a);
      argv[3] = g_strdup(STATION_UNIT);
      local_begin(a, argv, NULL);
    } else {
      jv run = local_json(data, "run/station.json");
      double pid = jnum(&run, "pid", -1);
      jv_free(&run);
      // started by hand: only stopped from here, it has nothing to start it again
      if (!strcmp(a, "stop") && local_alive(pid)) {
        char **argv = g_new0(char *, 3);
        argv[0] = g_strdup("kill"), argv[1] = g_strdup_printf("%d", (int)pid);
        local_begin(a, argv, NULL);
      } else {
        local_fail(local_alive(pid) ? "byHand" : "noService");
      }
    }
  }
  g_free(data);
  g_free(a);
}
