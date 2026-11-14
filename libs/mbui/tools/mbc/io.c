// mbc's few needs from the system: files read and written whole as bytes (paths as UTF-8 bytes), a directory's
// names, a file removed or renamed, an environment variable, and the process ended with a status.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#if defined(_WIN32)
#include <direct.h>
#include <io.h>
#include <windows.h>
#else
#include <dirent.h>
#include <unistd.h>
#endif
#include "moonbit.h"

// a path given as bytes (UTF-8), NUL-terminated; the caller frees it
static char *cpath(moonbit_bytes_t p) {
  int32_t n = Moonbit_array_length(p);
  char *s = malloc((size_t)n + 1);
  memcpy(s, p, (size_t)n);
  s[n] = 0;
  return s;
}

static moonbit_bytes_t bytes_of(const char *s, size_t n) {
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)n, 0);
  memcpy(out, s, n);
  return out;
}

// the file's bytes; its length -1 (an empty Bytes, `ok` 0) when it cannot be read
int32_t mbc_file_ok;

moonbit_bytes_t mbc_read_file(moonbit_bytes_t path) {
  char *p = cpath(path);
  FILE *f = fopen(p, "rb");
  free(p);
  mbc_file_ok = 0;
  if (!f) return moonbit_make_bytes(0, 0);
  fseek(f, 0, SEEK_END);
  long n = ftell(f);
  fseek(f, 0, SEEK_SET);
  if (n < 0) {
    fclose(f);
    return moonbit_make_bytes(0, 0);
  }
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)n, 0);
  size_t got = fread(out, 1, (size_t)n, f);
  fclose(f);
  if ((long)got != n) return moonbit_make_bytes(0, 0);
  mbc_file_ok = 1;
  return out;
}

int32_t mbc_read_ok(void) { return mbc_file_ok; }

int32_t mbc_write_file(moonbit_bytes_t path, moonbit_bytes_t data) {
  char *p = cpath(path);
  FILE *f = fopen(p, "wb");
  free(p);
  if (!f) return 0;
  int32_t n = Moonbit_array_length(data);
  size_t put = fwrite(data, 1, (size_t)n, f);
  int ok = fclose(f) == 0 && (int32_t)put == n;
  return ok;
}

int32_t mbc_rename(moonbit_bytes_t from, moonbit_bytes_t to) {
  char *a = cpath(from), *b = cpath(to);
#if defined(_WIN32)
  int r = MoveFileExA(a, b, MOVEFILE_REPLACE_EXISTING) ? 0 : -1;
#else
  int r = rename(a, b);
#endif
  free(a);
  free(b);
  return r == 0;
}

int32_t mbc_remove(moonbit_bytes_t path) {
  char *p = cpath(path);
  int r = remove(p);
  free(p);
  return r == 0;
}

int32_t mbc_mkdir(moonbit_bytes_t path) {
  // (and the directories it is in, as os.makedirs)
  char *p = cpath(path);
  for (char *q = p + 1; *q; q++) {
    if (*q == '/' || *q == '\\') {
      char c = *q;
      *q = 0;
#if defined(_WIN32)
      _mkdir(p);
#else
      mkdir(p, 0777);
#endif
      *q = c;
    }
  }
#if defined(_WIN32)
  int r = _mkdir(p);
#else
  int r = mkdir(p, 0777);
#endif
  free(p);
  return r == 0;
}

// the names in a directory (not . and ..), each ended by a NUL, in one Bytes
moonbit_bytes_t mbc_list_dir(moonbit_bytes_t path) {
  char *p = cpath(path);
  size_t cap = 4096, len = 0;
  char *buf = malloc(cap);
#if defined(_WIN32)
  char *pat = malloc(strlen(p) + 3);
  sprintf(pat, "%s\\*", p);
  WIN32_FIND_DATAA fd;
  HANDLE h = FindFirstFileA(pat, &fd);
  free(pat);
  if (h != INVALID_HANDLE_VALUE) {
    do {
      const char *n = fd.cFileName;
#else
  DIR *d = opendir(p);
  struct dirent *e;
  if (d) {
    while ((e = readdir(d))) {
      const char *n = e->d_name;
#endif
      if (strcmp(n, ".") == 0 || strcmp(n, "..") == 0) continue;
      size_t k = strlen(n) + 1;
      while (len + k > cap) buf = realloc(buf, cap *= 2);
      memcpy(buf + len, n, k);
      len += k;
#if defined(_WIN32)
    } while (FindNextFileA(h, &fd));
    FindClose(h);
  }
#else
    }
    closedir(d);
  }
#endif
  free(p);
  moonbit_bytes_t out = bytes_of(buf, len);
  free(buf);
  return out;
}

// an environment variable's value; `set` says whether it was
int32_t mbc_env_set;

moonbit_bytes_t mbc_getenv(moonbit_bytes_t name) {
  char *n = cpath(name);
  const char *v = getenv(n);
  free(n);
  mbc_env_set = v != NULL;
  return v ? bytes_of(v, strlen(v)) : moonbit_make_bytes(0, 0);
}

int32_t mbc_env_was_set(void) { return mbc_env_set; }

int32_t mbc_cpu_count(void) {
#if defined(_WIN32)
  SYSTEM_INFO si;
  GetSystemInfo(&si);
  return (int32_t)si.dwNumberOfProcessors;
#else
  long n = sysconf(_SC_NPROCESSORS_ONLN);
  return n > 0 ? (int32_t)n : 1;
#endif
}

void mbc_write_err(moonbit_bytes_t s) {
  fwrite(s, 1, (size_t)Moonbit_array_length(s), stderr);
  fflush(stderr);
}

void mbc_exit(int32_t code) { exit(code); }

#if !defined(_WIN32)
#include <sys/wait.h>
#endif

int32_t mbc_fork(void) {
#if defined(_WIN32)
  return -1;
#else
  fflush(stdout);
  fflush(stderr);
  return (int32_t)fork();
#endif
}

int32_t mbc_wait_all(void) {
#if defined(_WIN32)
  return 0;
#else
  int st, bad = 0;
  while (wait(&st) > 0) {
    if (!WIFEXITED(st) || WEXITSTATUS(st) != 0) bad = 1;
  }
  return bad;
#endif
}

void mbc_child_exit(int32_t code) {
#if defined(_WIN32)
  exit(code);
#else
  _exit(code);
#endif
}

// ---------------------------------------------------------------- mbc's: processes, files' metadata, locks

#if defined(_WIN32)
#include <sys/utime.h>
#else
#include <fcntl.h>
#include <spawn.h>
#include <sys/file.h>
#include <utime.h>
#include <limits.h>
extern char **environ;
#endif

int32_t mbc_is_windows(void) {
#if defined(_WIN32)
  return 1;
#else
  return 0;
#endif
}

int32_t mbc_is_linux(void) {
#if defined(__linux__)
  return 1;
#else
  return 0;
#endif
}

void mbc_write_out(moonbit_bytes_t s) {
  fwrite(s, 1, (size_t)Moonbit_array_length(s), stdout);
  fflush(stdout);
}

int32_t mbc_setenv(moonbit_bytes_t name, moonbit_bytes_t value) {
  char *n = cpath(name), *v = cpath(value);
#if defined(_WIN32)
  int r = _putenv_s(n, v);
#else
  int r = setenv(n, v, 1);
#endif
  free(n);
  free(v);
  return r == 0;
}

// a file's kind (0 none, 1 file, 2 directory, 3 other), size and mtime in ns, by mbc_stat
static int64_t st_size, st_mtime_ns;

int32_t mbc_stat(moonbit_bytes_t path) {
  char *p = cpath(path);
#if defined(_WIN32)
  struct _stat64 st;
  int r = _stat64(p, &st);
#else
  struct stat st;
  int r = stat(p, &st);
#endif
  free(p);
  if (r != 0) return 0;
  st_size = (int64_t)st.st_size;
#if defined(__APPLE__)
  st_mtime_ns = (int64_t)st.st_mtimespec.tv_sec * 1000000000 + st.st_mtimespec.tv_nsec;
#elif defined(_WIN32)
  st_mtime_ns = (int64_t)st.st_mtime * 1000000000;
#else
  st_mtime_ns = (int64_t)st.st_mtim.tv_sec * 1000000000 + st.st_mtim.tv_nsec;
#endif
  if ((st.st_mode & S_IFMT) == S_IFREG) return 1;
  if ((st.st_mode & S_IFMT) == S_IFDIR) return 2;
  return 3;
}

int64_t mbc_stat_size(void) { return st_size; }
int64_t mbc_stat_mtime(void) { return st_mtime_ns; }

// (a file's or a directory's: Windows' _utime opens what it touches as a file, and a directory then is not touched,
// so MBC_STORE's units taken from it were pruned as unused)
int32_t mbc_touch(moonbit_bytes_t path) {
  char *p = cpath(path);
#if defined(_WIN32)
  int r = -1;
  HANDLE h = CreateFileA(p, FILE_WRITE_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
                         OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
  if (h != INVALID_HANDLE_VALUE) {
    FILETIME t;
    GetSystemTimeAsFileTime(&t);
    if (SetFileTime(h, NULL, &t, &t)) r = 0;
    CloseHandle(h);
  }
#else
  int r = utime(p, NULL);
#endif
  free(p);
  return r == 0;
}

int32_t mbc_rmdir(moonbit_bytes_t path) {
  char *p = cpath(path);
#if defined(_WIN32)
  int r = _rmdir(p);
#else
  int r = rmdir(p);
#endif
  free(p);
  return r == 0;
}

int32_t mbc_symlink(moonbit_bytes_t target, moonbit_bytes_t link) {
#if defined(_WIN32)
  return 0;
#else
  char *t = cpath(target), *l = cpath(link);
  int r = symlink(t, l);
  free(t);
  free(l);
  return r == 0;
#endif
}

int32_t mbc_chmod(moonbit_bytes_t path, int32_t mode) {
#if defined(_WIN32)
  return 1;
#else
  char *p = cpath(path);
  int r = chmod(p, (mode_t)mode);
  free(p);
  return r == 0;
#endif
}

int32_t mbc_executable(moonbit_bytes_t path) {
#if defined(_WIN32)
  return 1;
#else
  char *p = cpath(path);
  int r = access(p, X_OK);
  free(p);
  return r == 0;
#endif
}

moonbit_bytes_t mbc_getcwd(void) {
  char buf[4096];
#if defined(_WIN32)
  if (!_getcwd(buf, sizeof buf)) buf[0] = 0;
#else
  if (!getcwd(buf, sizeof buf)) buf[0] = 0;
#endif
  return bytes_of(buf, strlen(buf));
}

moonbit_bytes_t mbc_realpath(moonbit_bytes_t path) {
  char *p = cpath(path);
#if defined(_WIN32)
  char *r = _fullpath(NULL, p, 0);
#else
  char *r = realpath(p, NULL);
#endif
  free(p);
  if (!r) return moonbit_make_bytes(0, 0);
  moonbit_bytes_t out = bytes_of(r, strlen(r));
  free(r);
  return out;
}

int32_t mbc_getpid(void) {
#if defined(_WIN32)
  return (int32_t)GetCurrentProcessId();
#else
  return (int32_t)getpid();
#endif
}

// an exclusive lock on a file (made if it is not there), the system's to let go when its holder ends however it
// ends (flock): its handle, -1 when another holds it (wait 0) or it cannot be had; Windows: no lock, 0
int32_t mbc_lock(moonbit_bytes_t path, int32_t wait) {
#if defined(_WIN32)
  return 0;
#else
  char *p = cpath(path);
  int fd = open(p, O_WRONLY | O_CREAT | O_APPEND, 0666);
  free(p);
  if (fd < 0) return -1;
  if (flock(fd, LOCK_EX | (wait ? 0 : LOCK_NB)) != 0) {
    close(fd);
    return -1;
  }
  return fd;
#endif
}

void mbc_unlock(int32_t fd) {
#if !defined(_WIN32)
  if (fd > 0) {
    flock(fd, LOCK_UN);
    close(fd);
  }
#endif
}

// processes: started with mbc_spawn (argv as NUL-ended words; on Windows the command line), their output into a
// file (or this one's when out is empty); mbc_wait_any answers the slot of one that ended, mbc_status its exit code.
// A slot is free again only when mbc_release says its end was taken: one that ended while another was waited for is
// not given to the next process (its end was a job's still)
#define MBC_SLOTS 256
#if defined(_WIN32)
static HANDLE slots[MBC_SLOTS];
#else
static pid_t slots[MBC_SLOTS];
#endif
static int32_t slot_used[MBC_SLOTS]; // 0 free, 1 running, 2 ended (its end not yet taken)
static int32_t last_status;

int32_t mbc_spawn(moonbit_bytes_t words, moonbit_bytes_t cmdline, moonbit_bytes_t out) {
  int32_t s = -1;
  for (int32_t i = 0; i < MBC_SLOTS; i++)
    if (!slot_used[i]) {
      s = i;
      break;
    }
  if (s < 0) return -1;
#if defined(_WIN32)
  (void)words;
  char *cl = cpath(cmdline);
  STARTUPINFOA si;
  PROCESS_INFORMATION pi;
  memset(&si, 0, sizeof si);
  si.cb = sizeof si;
  HANDLE f = INVALID_HANDLE_VALUE;
  if (Moonbit_array_length(out) > 0) {
    char *o = cpath(out);
    SECURITY_ATTRIBUTES sa = {sizeof sa, NULL, TRUE};
    f = CreateFileA(o, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, &sa, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    free(o);
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    si.hStdOutput = f;
    si.hStdError = f;
  }
  BOOL ok = CreateProcessA(NULL, cl, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi);
  DWORD error = ok ? 0 : GetLastError();
  free(cl);
  if (f != INVALID_HANDLE_VALUE) CloseHandle(f);
  if (!ok) {
    fprintf(stderr, "mbc: CreateProcess failed (%lu), command length %d\n", (unsigned long)error,
            (int)Moonbit_array_length(cmdline));
    return -1;
  }
  CloseHandle(pi.hThread);
  slots[s] = pi.hProcess;
#else
  (void)cmdline;
  int32_t n = Moonbit_array_length(words);
  int argc = 0;
  for (int32_t i = 0; i < n; i++)
    if (words[i] == 0) argc++;
  char **argv = calloc((size_t)argc + 1, sizeof(char *));
  char *buf = malloc((size_t)n + 1);
  memcpy(buf, words, (size_t)n);
  buf[n] = 0;
  int k = 0;
  for (int32_t i = 0; i < n; i++) {
    if (i == 0 || words[i - 1] == 0) argv[k++] = buf + i;
  }
  argv[argc] = NULL;
  posix_spawn_file_actions_t fa;
  posix_spawn_file_actions_init(&fa);
  char *o = NULL;
  if (Moonbit_array_length(out) > 0) {
    o = cpath(out);
    posix_spawn_file_actions_addopen(&fa, 1, o, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    posix_spawn_file_actions_adddup2(&fa, 1, 2);
  }
  pid_t pid;
  int r = posix_spawnp(&pid, argv[0], &fa, NULL, argv, environ);
  posix_spawn_file_actions_destroy(&fa);
  free(o);
  free(argv);
  free(buf);
  if (r != 0) return -1;
  slots[s] = pid;
#endif
  slot_used[s] = 1;
  return s;
}

int32_t mbc_wait_any(void) {
#if defined(_WIN32)
  HANDLE hs[MAXIMUM_WAIT_OBJECTS];
  int32_t ids[MAXIMUM_WAIT_OBJECTS];
  int n = 0;
  for (int32_t i = 0; i < MBC_SLOTS && n < MAXIMUM_WAIT_OBJECTS; i++)
    if (slot_used[i] == 1) {
      hs[n] = slots[i];
      ids[n++] = i;
    }
  if (n == 0) return -1;
  DWORD w = WaitForMultipleObjects((DWORD)n, hs, FALSE, INFINITE);
  if (w >= WAIT_OBJECT_0 + (DWORD)n) return -1;
  int32_t s = ids[w - WAIT_OBJECT_0];
  DWORD code = 1;
  GetExitCodeProcess(slots[s], &code);
  CloseHandle(slots[s]);
  last_status = (int32_t)code;
  slot_used[s] = 2;
  return s;
#else
  for (;;) {
    int st;
    pid_t p = wait(&st);
    if (p < 0) return -1;
    for (int32_t i = 0; i < MBC_SLOTS; i++)
      if (slot_used[i] == 1 && slots[i] == p) {
        slot_used[i] = 2;
        last_status = WIFEXITED(st) ? WEXITSTATUS(st) : 128 + (WIFSIGNALED(st) ? WTERMSIG(st) : 0);
        return i;
      }
  }
#endif
}

int32_t mbc_status(void) { return last_status; }

void mbc_release(int32_t s) {
  if (s >= 0 && s < MBC_SLOTS) slot_used[s] = 0;
}

int32_t mbc_append(moonbit_bytes_t path, moonbit_bytes_t data) {
  char *p = cpath(path);
  FILE *f = fopen(p, "ab");
  free(p);
  if (!f) return 0;
  size_t n = (size_t)Moonbit_array_length(data);
  int ok = fwrite(data, 1, n, f) == n;
  return fclose(f) == 0 && ok;
}

int32_t mbc_chdir(moonbit_bytes_t path) {
  char *p = cpath(path);
#if defined(_WIN32)
  int r = _chdir(p);
#else
  int r = chdir(p);
#endif
  free(p);
  return r == 0;
}
