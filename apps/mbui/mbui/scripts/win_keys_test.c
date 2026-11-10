// The host's actual hook, with the window, held keys and queue supplied: no keyboard input sent to this machine.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#pragma comment(lib, "user32.lib")

#define CHECK(c) do { if (!(c)) { printf("line %d: %s\n", __LINE__, #c); exit(1); } } while (0)
static HWND hwnd = (HWND)1, foreground = (HWND)1, focus = (HWND)1;
static int ime_active = 1, marked_len;
enum { WM_MB_CAUGHT_KEY = WM_APP + 10 };
static SHORT held[256];
static int installs, removals, posts, forwards, told, post_ok = 1;
static int posted_code[32], posted_mods[32], told_code, told_mods;
static void key_told(int32_t code, int32_t mods) { told++; told_code = code; told_mods = mods; }
static struct { void (*key)(int32_t, int32_t); } mb_cb = {key_told};

static HWND test_foreground(void) { return foreground; }
static HWND test_focus(void) { return focus; }
static SHORT test_state(int vk) { return held[vk]; }
static HMODULE test_module(LPCWSTR name) { CHECK(name == NULL); return (HMODULE)1; }
static HHOOK test_install(int kind, HOOKPROC proc, HINSTANCE module, DWORD thread) {
  CHECK(kind == WH_KEYBOARD_LL && proc != NULL && module == (HMODULE)1 && thread == 0);
  installs++;
  return (HHOOK)1;
}
static BOOL test_remove(HHOOK hook) { CHECK(hook == (HHOOK)1); removals++; return TRUE; }
static LRESULT test_next(HHOOK hook, int n, WPARAM kind, LPARAM data) {
  (void)hook; (void)n; (void)kind; (void)data;
  forwards++;
  return 7;
}
static BOOL test_post(HWND target, UINT msg, WPARAM code, LPARAM mods) {
  CHECK(target == hwnd && msg == WM_MB_CAUGHT_KEY);
  if (!post_ok) return FALSE;
  CHECK(posts < 32);
  posted_code[posts] = (int)code;
  posted_mods[posts++] = (int)mods;
  return TRUE;
}
#define GetForegroundWindow test_foreground
#define GetFocus test_focus
#define GetKeyState test_state
#define GetAsyncKeyState test_state
#define GetModuleHandleW test_module
#define SetWindowsHookExW test_install
#define UnhookWindowsHookEx test_remove
#define CallNextHookEx test_next
#define PostMessageW test_post
#include "win_keys.h"

static LRESULT press(UINT vk, int down) {
  KBDLLHOOKSTRUCT key = {0};
  key.vkCode = vk;
  return catch_keyboard(HC_ACTION, down ? WM_KEYDOWN : WM_KEYUP, (LPARAM)&key);
}

int main(void) {
  // A focused screen's Win+K is queued once per press (including repeats), with Meta held; no app call in the hook.
  mb_host_key_catch(1);
  mb_host_key_catch(1);
  CHECK(installs == 1 && catch_hook != NULL);
  CHECK(press(VK_LWIN, 1) == 1 && (mods_now() & 8));
  CHECK(press('K', 1) == 1 && press('K', 1) == 1);
  CHECK(posts == 2 && posted_code[0] == 1000 + 'k' && posted_mods[0] == 8 && told == 0);
  CHECK(press(VK_LWIN, 0) == 1 && mods_now() == 0);
  CHECK(press('K', 0) == 1);  // key up after Win was let go is still ours
  CHECK(press('K', 1) == 7 && posts == 2);

  // Both Windows keys, named keys, and every other modifier; no async Win state (the hook swallowed that key).
  CHECK(press(VK_LWIN, 1) == 1 && press(VK_RWIN, 1) == 1 && press(VK_LWIN, 0) == 1);
  held[VK_SHIFT] = held[VK_CONTROL] = held[VK_MENU] = -32768;
  CHECK(press(VK_RIGHT, 1) == 1);
  CHECK(posted_code[2] == 4 && posted_mods[2] == 15);
  CHECK(press(VK_RIGHT, 0) == 1);
  CHECK(press('R', 1) == 1 && posted_code[3] == 1000 + 'r' && posted_mods[3] == 15);
  CHECK(press('R', 0) == 1 && press(VK_RWIN, 0) == 1);
  memset(held, 0, sizeof held);

  // A different foreground window, a native child, and the input method composing retain their keys.
  foreground = (HWND)2;
  CHECK(press(VK_LWIN, 1) == 7 && press('K', 1) == 7 && catch_win_held == 0);
  foreground = hwnd;
  focus = (HWND)2;
  CHECK(press(VK_LWIN, 1) == 7);
  focus = hwnd;
  marked_len = 1;
  CHECK(press(VK_LWIN, 1) == 7);
  marked_len = 0;
  CHECK(press(VK_LWIN, 1) == 1 && press('K', 1) == 1);
  marked_len = 1;
  CHECK(press('K', 0) == 1 && press(VK_LWIN, 0) == 1 && catch_win_held == 0);
  marked_len = 0;
  ime_active = 0;
  CHECK(press(VK_LWIN, 1) == 7);
  ime_active = 1;
  CHECK(catch_keyboard(-1, WM_KEYDOWN, 0) == 7);

  // Leaving the canvas and closing the catcher each remove the hook and all its held state.
  CHECK(press(VK_LWIN, 1) == 1 && press('K', 1) == 1);
  catch_keys_focus(0);
  CHECK(removals == 1 && catch_hook == NULL && catch_win_held == 0 && !catch_pressed['K']);
  catch_keys_focus(1);
  CHECK(installs == 2);
  mb_host_key_catch(0);
  CHECK(removals == 2 && catch_hook == NULL && press(VK_LWIN, 1) == 7);
  foreground = (HWND)2;
  mb_host_key_catch(1);
  CHECK(installs == 2);
  foreground = hwnd;
  catch_keys_focus(1);
  CHECK(installs == 3);

  // Ordinary Ctrl, text and AltGr keep their previous routes, while a full queue does not swallow a character.
  held[VK_CONTROL] = -32768;
  CHECK(catch_vk('K') == 1000 + 'k' && told_code == 1000 + 'k' && told_mods == 2);
  held[VK_MENU] = -32768;
  CHECK(catch_vk('K') == 0);
  memset(held, 0, sizeof held);
  CHECK(catch_vk('K') == 0 && catch_vk(VK_RETURN) == 7);
  CHECK(press(VK_LWIN, 1) == 1);
  post_ok = 0;
  CHECK(press('K', 1) == 7);
  CHECK(press(VK_LWIN, 0) == 1);
  mb_host_key_catch(0);
  printf("win_keys: passed (Win shortcuts, modifiers, focus, composition, teardown, Ctrl and AltGr)\n");
  return 0;
}
