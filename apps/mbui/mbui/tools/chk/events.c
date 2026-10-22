// The system's word that a watched file was written, a directory changed or a process ended (chk logwait): kqueue on
// macOS, inotify and a pidfd on Linux. Elsewhere none (chk_ev_init fails).
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "moonbit.h"

static char *ev_cstr(moonbit_bytes_t b) {
  int32_t n = Moonbit_array_length(b);
  char *s = malloc((size_t)n + 1);
  memcpy(s, b, (size_t)n);
  s[n] = 0;
  return s;
}

// the files read as they are written: 0 the log, 1 the failing one
static FILE *ev_files[2];

// a file opened to be read from its start on; 0 when it cannot be
int32_t chk_ev_open(int32_t k, moonbit_bytes_t path) {
  char *p = ev_cstr(path);
  ev_files[k] = fopen(p, "rb");
  free(p);
  return ev_files[k] != NULL;
}

// what was written to file k since it was last read
moonbit_bytes_t chk_ev_read(int32_t k) {
  FILE *f = ev_files[k];
  size_t cap = 1 << 14, n = 0, got;
  char *buf = malloc(cap);
  if (f) {
    clearerr(f);
    while ((got = fread(buf + n, 1, cap - n, f)) > 0) {
      n += got;
      if (n == cap) {
        cap *= 2;
        buf = realloc(buf, cap);
      }
    }
  }
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)n, 0);
  memcpy(out, buf, n);
  free(buf);
  return out;
}

#if defined(__APPLE__) || defined(__FreeBSD__)
#include <fcntl.h>
#include <sys/event.h>
#include <sys/time.h>
#include <unistd.h>

static int kq = -1;

int32_t chk_ev_init(void) {
  kq = kqueue();
  return kq >= 0;
}

int32_t chk_ev_file(int32_t k) {
  struct kevent e;
  EV_SET(&e, fileno(ev_files[k]), EVFILT_VNODE, EV_ADD | EV_CLEAR, NOTE_WRITE | NOTE_EXTEND, 0, NULL);
  return kevent(kq, &e, 1, NULL, 0, NULL) == 0;
}

int32_t chk_ev_dir(moonbit_bytes_t path) {
  char *p = ev_cstr(path);
  int d = open(p, O_RDONLY);
  free(p);
  if (d < 0) return 0;
  struct kevent e;
  EV_SET(&e, d, EVFILT_VNODE, EV_ADD | EV_CLEAR, NOTE_WRITE, 0, NULL);
  return kevent(kq, &e, 1, NULL, 0, NULL) == 0;
}

// the process's end watched; 0 when it is gone already
int32_t chk_ev_pid(int32_t pid) {
  struct kevent e;
  EV_SET(&e, pid, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, NULL);
  return kevent(kq, &e, 1, NULL, 0, NULL) == 0;
}

// until an event or ms: 1 when the process ended
int32_t chk_ev_wait(int32_t ms) {
  struct kevent got[4];
  struct timespec ts = {ms / 1000, (long)(ms % 1000) * 1000000L};
  int n = kevent(kq, NULL, 0, got, 4, &ts);
  for (int i = 0; i < n; i++)
    if (got[i].filter == EVFILT_PROC) return 1;
  return 0;
}

#elif defined(__linux__)
#include <fcntl.h>
#include <poll.h>
#include <sys/inotify.h>
#include <sys/syscall.h>
#include <unistd.h>

static int ino = -1, pidfd = -1;
static char ev_paths[2][4096];

int32_t chk_ev_init(void) {
  ino = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
  return ino >= 0;
}

int32_t chk_ev_open_path(int32_t k, moonbit_bytes_t path) {
  char *p = ev_cstr(path);
  if (!realpath(p, ev_paths[k])) snprintf(ev_paths[k], sizeof ev_paths[k], "%s", p);
  free(p);
  return 1;
}

int32_t chk_ev_file(int32_t k) {
  return inotify_add_watch(ino, ev_paths[k], IN_MODIFY | IN_CLOSE_WRITE | IN_ATTRIB) >= 0;
}

int32_t chk_ev_dir(moonbit_bytes_t path) {
  char *p = ev_cstr(path);
  int r = inotify_add_watch(ino, p, IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO);
  free(p);
  return r >= 0;
}

int32_t chk_ev_pid(int32_t pid) {
  pidfd = (int)syscall(SYS_pidfd_open, pid, 0);
  return pidfd >= 0;
}

int32_t chk_ev_wait(int32_t ms) {
  struct pollfd fds[2] = {{ino, POLLIN, 0}, {pidfd, POLLIN, 0}};
  int n = poll(fds, pidfd >= 0 ? 2 : 1, ms);
  int ended = 0;
  if (n > 0) {
    if (fds[0].revents & POLLIN) {
      char buf[65536];
      while (read(ino, buf, sizeof buf) > 0) {
      }
    }
    if (pidfd >= 0 && (fds[1].revents & POLLIN)) ended = 1;
  }
  return ended;
}

#else
int32_t chk_ev_init(void) { return 0; }
int32_t chk_ev_file(int32_t k) { (void)k; return 0; }
int32_t chk_ev_dir(moonbit_bytes_t path) { (void)path; return 0; }
int32_t chk_ev_pid(int32_t pid) { (void)pid; return 0; }
int32_t chk_ev_wait(int32_t ms) { (void)ms; return 0; }
#endif

#if !defined(__linux__)
int32_t chk_ev_open_path(int32_t k, moonbit_bytes_t path) { (void)k; (void)path; return 1; }
#endif
