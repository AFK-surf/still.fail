// cl.exe (and lib.exe, link.exe) for moon on Windows: scripts/mbc shim compiles it and copies it under those names
// into a directory that scripts/win.sh puts first on PATH. Each runs the command line in its .txt next to it (cl.txt:
// mbc wrap --real <the real cl.exe> --; lib.txt and link.txt: the real ones) with its own
// arguments after it, and exits with its exit code. mbc wrap hands every command to the real cl as it is, except
// the one compiling moonc's C into the program, which it splits and compiles in parallel.
#include <windows.h>
#include <stdio.h>
#include <wchar.h>

int wmain(void) {
  wchar_t path[MAX_PATH];
  DWORD n = GetModuleFileNameW(NULL, path, MAX_PATH);
  if (n < 4 || n >= MAX_PATH) return 101;
  wcscpy(path + n - 4, L".txt");  // cl.exe -> cl.txt
  FILE *f = _wfopen(path, L"rb");
  if (!f) {
    fwprintf(stderr, L"mbc-cl: no %ls\n", path);
    return 102;
  }
  static char prefix[32768];
  size_t len = fread(prefix, 1, sizeof prefix - 1, f);
  fclose(f);
  while (len && (prefix[len - 1] == '\n' || prefix[len - 1] == '\r')) len--;
  prefix[len] = 0;
  static wchar_t wprefix[32768];
  if (!MultiByteToWideChar(CP_UTF8, 0, prefix, -1, wprefix, 32768)) return 103;
  // this one's arguments: its command line after its own name (quoted or not)
  wchar_t *cmd = GetCommandLineW();
  if (*cmd == L'"') {
    cmd++;
    while (*cmd && *cmd != L'"') cmd++;
    if (*cmd) cmd++;
  } else {
    while (*cmd && *cmd != L' ' && *cmd != L'\t') cmd++;
  }
  size_t total = wcslen(wprefix) + wcslen(cmd) + 2;
  wchar_t *line = (wchar_t *)HeapAlloc(GetProcessHeap(), 0, total * sizeof(wchar_t));
  if (!line) return 104;
  wcscpy(line, wprefix);
  if (*cmd && *cmd != L' ' && *cmd != L'\t') wcscat(line, L" ");
  wcscat(line, cmd);
  STARTUPINFOW si = {sizeof si};
  PROCESS_INFORMATION pi;
  if (!CreateProcessW(NULL, line, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi)) {
    fwprintf(stderr, L"mbc-cl: cannot run %ls (error %lu)\n", line, GetLastError());
    return 105;
  }
  WaitForSingleObject(pi.hProcess, INFINITE);
  DWORD code = 1;
  GetExitCodeProcess(pi.hProcess, &code);
  CloseHandle(pi.hProcess);
  CloseHandle(pi.hThread);
  return (int)code;
}
