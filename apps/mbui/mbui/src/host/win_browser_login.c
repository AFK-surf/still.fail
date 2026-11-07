// A sign-in in the browser that comes back to this machine, for the Windows host (host_native.mbt `browser_login`), on
// the loopback listener of win_listen.c: apple_browser_login.m's way. Listen on 127.0.0.1 at a port the system picks,
// let the app make its login page with http://127.0.0.1:<port><path> as where to come back, open it in the browser,
// take the one GET that comes back to <path> under that host name, answer it, stop listening. Nothing here knows whose
// sign-in it is: the app checks what came back (its state) and exchanges it. Opening is $BROWSER (a command given the
// address, as a station's remote login sets it, and as CI's runs stand in for a person with it), else the system's
// browser (ShellExecute). The app polls it each frame (a frame is asked for when the browser comes back).
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "listen_api.h"
#include "win.h"

#pragma comment(lib, "shell32.lib")

#include "browser_login.h"

static char *utf8(moonbit_string_t s) {
  int n = Moonbit_array_length(s);
  int bytes = WideCharToMultiByte(CP_UTF8, 0, (const WCHAR *)s, n, NULL, 0, NULL, NULL);
  char *u = malloc((size_t)bytes + 1);
  WideCharToMultiByte(CP_UTF8, 0, (const WCHAR *)s, n, u, bytes, NULL, NULL);
  u[bytes] = 0;
  return u;
}

static WCHAR *wide(const char *s) {
  int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
  WCHAR *w = malloc((size_t)n * sizeof(WCHAR));
  MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n);
  return w;
}

int32_t mb_host_browser_login_open(int32_t id, moonbit_string_t url) {
  (void)id;
  char *u = utf8(url);
  WCHAR *w = wide(u);
  int ok = 0;
  const WCHAR *browser = _wgetenv(L"BROWSER");
  if (browser && *browser) {
    // its first program (BROWSER's list is ':'-separated elsewhere; a Windows path has its own ':', so all of it here)
    size_t n = wcslen(browser) + wcslen(w) + 8;
    WCHAR *cmd = malloc(n * sizeof(WCHAR));
    _snwprintf(cmd, n, L"\"%ls\" \"%ls\"", browser, w);
    cmd[n - 1] = 0;
    STARTUPINFOW si = {sizeof si};
    PROCESS_INFORMATION pi;
    // Not waited for: a browser started directly keeps running after us.
    ok = CreateProcessW(NULL, cmd, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi) != 0;
    if (ok) CloseHandle(pi.hThread), CloseHandle(pi.hProcess);
    else fprintf(stderr, "browser login: BROWSER did not start (%lu)\n", GetLastError());
    free(cmd);
  } else {
    ok = (INT_PTR)ShellExecuteW(NULL, L"open", w, NULL, NULL, SW_SHOWNORMAL) > 32;
  }
  free(w);
  free(u);
  return ok;
}

moonbit_string_t mb_host_browser_login_back(int32_t id) {
  AcquireSRWLockShared(&lock);
  login *l = find(id);
  WCHAR *w = l && l->back ? wide(l->back) : NULL;
  ReleaseSRWLockShared(&lock);
  int n = w ? (int)wcslen(w) : 0;
  moonbit_string_t out = moonbit_make_string_raw(n);
  if (n) memcpy(out, w, (size_t)n * sizeof(WCHAR));
  free(w);
  return out;
}

