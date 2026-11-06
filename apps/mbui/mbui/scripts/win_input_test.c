// Exercise Windows' real TranslateMessage queue: the shortcut focuses a field while WM_KEYDOWN is dispatched.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <assert.h>
#include <stdio.h>
#include "win_input.h"

static HWND app;
static int ime_active;
static WCHAR typed[16];
static int length;

static LRESULT CALLBACK window_proc(HWND window, UINT message, WPARAM wp, LPARAM lp) {
  if (message == WM_KEYDOWN) {
    if (window == app && wp == VK_SPACE && !ime_active) ime_active = 1;
    if (window == app && wp == VK_F1) ime_active = !ime_active;
    return 0;
  }
  if (message == WM_CHAR) {
    assert(length < 15);
    typed[length++] = (WCHAR)wp;
    return 0;
  }
  return DefWindowProcW(window, message, wp, lp);
}

static void key(HWND window, WPARAM vk) {
  LPARAM lp = 1 | ((LPARAM)MapVirtualKeyW((UINT)vk, MAPVK_VK_TO_VSC) << 16);
  assert(PostMessageW(window, WM_KEYDOWN, vk, lp));
}

static void repeat_key(HWND window, WPARAM vk) {
  LPARAM lp = 1 | ((LPARAM)MapVirtualKeyW((UINT)vk, MAPVK_VK_TO_VSC) << 16) | ((LPARAM)1 << 30);
  assert(PostMessageW(window, WM_KEYDOWN, vk, lp));
}

static void dispatch(void) {
  MSG m;
  while (PeekMessageW(&m, NULL, 0, 0, PM_REMOVE)) {
    mb_win_input_dispatch(&m, app, ime_active);
  }
}

int main(void) {
  WNDCLASSW cls = {0};
  cls.lpfnWndProc = window_proc;
  cls.hInstance = GetModuleHandleW(NULL);
  cls.lpszClassName = L"mbui-input-test";
  assert(RegisterClassW(&cls));
  app = CreateWindowW(cls.lpszClassName, L"", 0, 0, 0, 1, 1, NULL, NULL, cls.hInstance, NULL);
  HWND child = CreateWindowW(cls.lpszClassName, L"", 0, 0, 0, 1, 1, NULL, NULL, cls.hInstance, NULL);
  assert(app && child);

  // The space is a shortcut; the next key, already queued before a frame, is the field's.
  key(app, VK_SPACE);
  key(app, 'A');
  dispatch();
  assert(ime_active && length == 1 && (typed[0] == L'a' || typed[0] == L'A'));

  // A held shortcut does not type the first Space, but subsequent repeats belong to the now-focused field.
  ime_active = 0;
  length = 0;
  key(app, VK_SPACE);
  for (int i = 0; i < 4; ++i) repeat_key(app, VK_SPACE);
  dispatch();
  assert(ime_active && length == 4);
  for (int i = 0; i < length; ++i) assert(typed[i] == L' ');

  // Losing the field gives later character keys back to the app; focusing it again accepts the next two keys.
  length = 0;
  key(app, VK_F1);
  dispatch();
  assert(!ime_active);
  key(app, 'A');
  dispatch();
  assert(length == 0);
  key(app, VK_SPACE);
  key(app, 'A');
  key(app, 'B');
  dispatch();
  assert(ime_active && length == 2);
  assert((typed[0] == L'a' || typed[0] == L'A') && (typed[1] == L'b' || typed[1] == L'B'));

  // With a field already focused Space is text; other native windows also get their own translated text.
  length = 0;
  key(app, VK_SPACE);
  dispatch();
  assert(length == 1 && typed[0] == L' ');
  length = 0;
  ime_active = 0;
  key(child, 'A');
  dispatch();
  assert(length == 1 && (typed[0] == L'a' || typed[0] == L'A'));

  // Exercise the Windows translation queue after changing keyboard layouts, where installed. These are keyboard
  // layouts, not evidence of a language IME's composition: that needs an installed IME and its own test.
  const WCHAR *layouts[] = {L"00000409", L"00000407"};  // US English, German
  HKL original = GetKeyboardLayout(0);
  for (int i = 0; i < 2; ++i) {
    HKL layout = LoadKeyboardLayoutW(layouts[i], KLF_ACTIVATE);
    if (!layout) {
      printf("keyboard layout %d unavailable\n", i);
      continue;
    }
    BYTE state[256] = {0};
    assert(SetKeyboardState(state));
    WCHAR expected[8] = {0};
    UINT scan = MapVirtualKeyExW(VK_OEM_1, MAPVK_VK_TO_VSC, layout);
    int n = ToUnicodeEx(VK_OEM_1, scan, state, expected, 8, 0, layout);
    if (n == 1 && expected[0] >= 0x20) {
      ime_active = 1;
      length = 0;
      key(app, VK_OEM_1);
      dispatch();
      assert(length == 1 && typed[0] == expected[0]);
      printf("keyboard layout %d: translated U+%04X\n", i, (unsigned)typed[0]);
    } else {
      printf("keyboard layout %d: no single character for OEM key\n", i);
    }
  }
  ActivateKeyboardLayout(original, 0);
  puts("Windows input dispatch: ok");
  return 0;
}
