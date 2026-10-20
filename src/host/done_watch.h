// What a scripted run's runner has finished (src/ui/drive.mbt `done X`): the runner (still.fail's run.sh, beside the
// run) writes each thing it was asked to do and has done as a file of the directory the run names (MBUI_DONE_DIR, else
// $MBUI_SHOT_DIR/done), named as the thing, its words what came of it ("ok", or what went wrong), written as .NAME and
// then renamed NAME, so that it is whole as it comes. The host is told of the directory's change by its system (macOS
// and iOS: kqueue's EVFILT_VNODE; Android: inotify; Windows: ReadDirectoryChangesW), never by looking again and again,
// and posts each name that comes there on channel "runner" as {"done": NAME, "said": WORDS} (post.h): the frame it
// wakes hands it to the drive. What was there as the watch began is an earlier run's: not posted.
//
// Included once by each host's own file, after post.h (mac_app.m, ios_app.m, android_host.c, win_app.c):
//   mb_done_watch(text)   the watch begun on the directory `text` (a MoonBit string), made when it is not there; 1
//                         when it watches (or did already), 0 when it cannot
#pragma once
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "moonbit.h"
#include "post_api.h"

// A MoonBit string (UTF-16) as UTF-8 into `out` (`cap` bytes, NUL-terminated); false when it does not fit.
static int done_utf8(moonbit_string_t s, char *out, size_t cap) {
  int n = Moonbit_array_length(s);
  size_t m = 0;
  for (int i = 0; i < n; i++) {
    uint32_t cp = s[i];
    if (cp >= 0xD800 && cp < 0xDC00 && i + 1 < n && s[i + 1] >= 0xDC00 && s[i + 1] < 0xE000) {
      cp = 0x10000 + ((cp - 0xD800) << 10) + (s[i + 1] - 0xDC00);
      i++;
    }
    char b[4];
    int k = cp < 0x80 ? 1 : cp < 0x800 ? 2 : cp < 0x10000 ? 3 : 4;
    if (k == 1) b[0] = (char)cp;
    else if (k == 2) { b[0] = (char)(0xC0 | (cp >> 6)); b[1] = (char)(0x80 | (cp & 0x3F)); }
    else if (k == 3) {
      b[0] = (char)(0xE0 | (cp >> 12));
      b[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
      b[2] = (char)(0x80 | (cp & 0x3F));
    } else {
      b[0] = (char)(0xF0 | (cp >> 18));
      b[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
      b[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
      b[3] = (char)(0x80 | (cp & 0x3F));
    }
    if (m + (size_t)k + 1 > cap) return 0;
    memcpy(out + m, b, (size_t)k);
    m += (size_t)k;
  }
  out[m] = 0;
  return 1;
}

// `s` as a JSON string's insides onto `out` (at `*m`, `cap` bytes); what does not fit is left off.
static void done_json_str(const char *s, char *out, size_t *m, size_t cap) {
  for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
    char e[8];
    int k;
    if (*p == '"' || *p == '\\') { e[0] = '\\'; e[1] = (char)*p; k = 2; }
    else if (*p == '\n') { e[0] = '\\'; e[1] = 'n'; k = 2; }
    else if (*p < 0x20) k = snprintf(e, sizeof e, "\\u%04x", *p);
    else { e[0] = (char)*p; k = 1; }
    if (*m + (size_t)k + 8 > cap) return;
    memcpy(out + *m, e, (size_t)k);
    *m += (size_t)k;
  }
}

// The file `name` of `dir` come: its words (4 KB at most) posted with its name.
static void done_post(const char *dir, const char *name) {
  if (!name[0] || name[0] == '.') return;
  char path[4096];
  snprintf(path, sizeof path, "%s/%s", dir, name);
  char said[4096];
  size_t n = 0;
  FILE *f = fopen(path, "rb");
  if (f) {
    n = fread(said, 1, sizeof said - 1, f);
    fclose(f);
  }
  said[n] = 0;
  // (a NUL in it ends its words there)
  char json[12288];
  size_t m = 0;
  memcpy(json, "{\"done\":\"", 9);
  m = 9;
  done_json_str(name, json, &m, sizeof json);
  memcpy(json + m, "\",\"said\":\"", 10);
  m += 10;
  done_json_str(said, json, &m, sizeof json);
  memcpy(json + m, "\"}", 2);
  m += 2;
  mb_post("runner", json, m, NULL, 0);
}

// The names seen in the directory (kqueue says only that it changed: what is new is what was not seen).
static char **done_seen;
static int done_seen_n, done_seen_cap;

static int done_was_seen(const char *name) {
  for (int i = 0; i < done_seen_n; i++)
    if (strcmp(done_seen[i], name) == 0) return 1;
  if (done_seen_n == done_seen_cap) {
    done_seen_cap = done_seen_cap ? done_seen_cap * 2 : 16;
    done_seen = realloc(done_seen, (size_t)done_seen_cap * sizeof *done_seen);
  }
  done_seen[done_seen_n++] = strdup(name);
  return 0;
}

static char done_dir[4096];
static int done_watching;

#if defined(_WIN32)

static wchar_t done_wdir[4096];

static DWORD WINAPI done_loop(LPVOID arg) {
  HANDLE h = (HANDLE)arg;
  DWORD buf[4096];
  for (;;) {
    DWORD got = 0;
    if (!ReadDirectoryChangesW(h, buf, sizeof buf, FALSE, FILE_NOTIFY_CHANGE_FILE_NAME, &got, NULL, NULL)) break;
    if (got == 0) continue;
    for (FILE_NOTIFY_INFORMATION *e = (FILE_NOTIFY_INFORMATION *)buf;;
         e = (FILE_NOTIFY_INFORMATION *)((char *)e + e->NextEntryOffset)) {
      // a name come: renamed to it (the runner's way: whole as it comes), or made with it
      if (e->Action == FILE_ACTION_RENAMED_NEW_NAME || e->Action == FILE_ACTION_ADDED) {
        char name[1024];
        int k = WideCharToMultiByte(CP_UTF8, 0, e->FileName, (int)(e->FileNameLength / sizeof(WCHAR)), name,
                                    sizeof name - 1, NULL, NULL);
        name[k > 0 ? k : 0] = 0;
        if (name[0] && name[0] != '.' && !done_was_seen(name)) done_post(done_dir, name);
      }
      if (!e->NextEntryOffset) break;
    }
  }
  return 0;
}

static int32_t mb_done_watch(moonbit_string_t text) {
  if (done_watching) return 1;
  if (!done_utf8(text, done_dir, sizeof done_dir) || !done_dir[0]) return 0;
  MultiByteToWideChar(CP_UTF8, 0, done_dir, -1, done_wdir, 4096);
  CreateDirectoryW(done_wdir, NULL);
  // what is there already: an earlier run's
  wchar_t pat[4200];
  _snwprintf(pat, 4200, L"%ls\\*", done_wdir);
  WIN32_FIND_DATAW fd;
  HANDLE fh = FindFirstFileW(pat, &fd);
  if (fh != INVALID_HANDLE_VALUE) {
    do {
      char name[1024];
      WideCharToMultiByte(CP_UTF8, 0, fd.cFileName, -1, name, sizeof name, NULL, NULL);
      done_was_seen(name);
    } while (FindNextFileW(fh, &fd));
    FindClose(fh);
  }
  HANDLE h = CreateFileW(done_wdir, FILE_LIST_DIRECTORY, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
                         OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
  if (h == INVALID_HANDLE_VALUE) return 0;
  HANDLE t = CreateThread(NULL, 0, done_loop, h, 0, NULL);
  if (!t) return 0;
  CloseHandle(t);
  done_watching = 1;
  return 1;
}

#else
#include <dirent.h>
#include <fcntl.h>
#include <pthread.h>
#include <sys/stat.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <sys/event.h>
#else
#include <sys/inotify.h>
#endif

// The directory's names, each not seen before posted (seen: what is there as the watch begins, posted: false).
static void done_scan(int post) {
  DIR *d = opendir(done_dir);
  if (!d) return;
  struct dirent *e;
  while ((e = readdir(d)) != NULL) {
    if (e->d_name[0] == '.') continue;
    if (!done_was_seen(e->d_name) && post) done_post(done_dir, e->d_name);
  }
  closedir(d);
}

static void *done_loop(void *arg) {
  int fd = (int)(intptr_t)arg;
#if defined(__APPLE__)
  // the directory written (a name come or gone): what is new in it posted
  int kq = kqueue();
  struct kevent ch;
  EV_SET(&ch, fd, EVFILT_VNODE, EV_ADD | EV_CLEAR, NOTE_WRITE, 0, NULL);
  if (kq < 0 || kevent(kq, &ch, 1, NULL, 0, NULL) < 0) return NULL;
  for (;;) {
    struct kevent ev;
    int n = kevent(kq, NULL, 0, &ev, 1, NULL);
    if (n < 0) break;
    if (n > 0) done_scan(1);
  }
#else
  // a name come: renamed to it, or a file of it written and closed
  char buf[4096] __attribute__((aligned(__alignof__(struct inotify_event))));
  for (;;) {
    ssize_t n = read(fd, buf, sizeof buf);
    if (n <= 0) break;
    for (char *p = buf; p < buf + n;) {
      struct inotify_event *e = (struct inotify_event *)p;
      if (e->len && e->name[0] != '.' && !done_was_seen(e->name)) done_post(done_dir, e->name);
      p += sizeof *e + e->len;
    }
  }
#endif
  return NULL;
}

static int32_t mb_done_watch(moonbit_string_t text) {
  if (done_watching) return 1;
  if (!done_utf8(text, done_dir, sizeof done_dir) || !done_dir[0]) return 0;
  mkdir(done_dir, 0755);
#if defined(__APPLE__)
  int fd = open(done_dir, O_EVTONLY);
  if (fd < 0) return 0;
#else
  int fd = inotify_init1(IN_CLOEXEC);
  if (fd < 0 || inotify_add_watch(fd, done_dir, IN_MOVED_TO | IN_CLOSE_WRITE) < 0) return 0;
#endif
  // what is there already: an earlier run's (seen, not posted)
  done_scan(0);
  pthread_t t;
  if (pthread_create(&t, NULL, done_loop, (void *)(intptr_t)fd) != 0) return 0;
  pthread_detach(t);
  done_watching = 1;
  return 1;
}
#endif
