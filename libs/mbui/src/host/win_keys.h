// A key catcher's Windows keys. The shell takes Win+K, Win+R and Win+arrows before WM_KEYDOWN reaches the window.
// While the catcher owns the foreground canvas, keep those keys from the shell and post their codes to our queue.
// Never call the app from the low-level hook: its work must finish before LowLevelHooksTimeout.

static int key_catching;
static HHOOK catch_hook;
static int catch_win_held;
static unsigned char catch_pressed[256];

static int mods_now(void) {
  return (GetKeyState(VK_SHIFT) < 0 ? 1 : 0) | (GetKeyState(VK_CONTROL) < 0 ? 2 : 0) |
         (GetKeyState(VK_MENU) < 0 ? 4 : 0) |
         ((catch_win_held || GetKeyState(VK_LWIN) < 0 || GetKeyState(VK_RWIN) < 0) ? 8 : 0);
}

// A named key, or a character with Ctrl, Alt or Win (1000 + it, lower case). Ctrl+Alt is AltGr: text through WM_CHAR.
static int catch_code(WPARAM vk, int mods) {
  int code = 0;
  switch (vk) {
    case VK_BACK: code = 1; break;
    case VK_DELETE: code = 2; break;
    case VK_LEFT: code = 3; break;
    case VK_RIGHT: code = 4; break;
    case VK_UP: code = 5; break;
    case VK_DOWN: code = 6; break;
    case VK_RETURN: code = 7; break;
    case VK_HOME: code = 8; break;
    case VK_END: code = 9; break;
    case VK_PRIOR: code = 15; break;
    case VK_NEXT: code = 16; break;
    case VK_ESCAPE: code = 17; break;
    case VK_TAB: code = 18; break;
    default: break;
  }
  if (!code && (mods & (2 | 4 | 8)) && ((mods & 8) || (mods & (2 | 4)) != (2 | 4))) {
    UINT ch = MapVirtualKeyW((UINT)vk, MAPVK_VK_TO_CHAR) & 0x7FFF;
    if (ch >= 'A' && ch <= 'Z') ch += 'a' - 'A';
    if (ch >= 32) code = 1000 + (int)ch;
  }
  return code;
}

static int catch_vk(WPARAM vk) {
  int mods = mods_now(), code = catch_code(vk, mods);
  if (code) mb_cb.key(code, mods);
  return code;
}

static int catch_canvas(void) {
  return key_catching && ime_active && !marked_len && GetForegroundWindow() == hwnd && GetFocus() == hwnd;
}

static LRESULT CALLBACK catch_keyboard(int n, WPARAM kind, LPARAM data) {
  if (n != HC_ACTION) return CallNextHookEx(catch_hook, n, kind, data);
  const KBDLLHOOKSTRUCT *key = (const KBDLLHOOKSTRUCT *)data;
  DWORD vk = key->vkCode;
  int down = kind == WM_KEYDOWN || kind == WM_SYSKEYDOWN;
  int up = kind == WM_KEYUP || kind == WM_SYSKEYUP;
  if (!down && !up) return CallNextHookEx(catch_hook, n, kind, data);
  int win = vk == VK_LWIN ? 1 : vk == VK_RWIN ? 2 : 0;
  if (win && up && (catch_win_held & win)) {
    catch_win_held &= ~win;
    return 1;
  }
  if (vk < 256 && up && catch_pressed[vk]) {
    catch_pressed[vk] = 0;
    return 1;
  }
  if (!catch_canvas()) return CallNextHookEx(catch_hook, n, kind, data);
  if (win && down) {
    catch_win_held |= win;
    return 1;
  }
  if (down && catch_win_held) {
    // This callback precedes the key's async state update. Track Win ourselves (it never enters the queue), and
    // read the other modifiers already held, rather than GetKeyState's state of the last dequeued message.
    int mods = 8 | (GetAsyncKeyState(VK_SHIFT) < 0 ? 1 : 0) | (GetAsyncKeyState(VK_CONTROL) < 0 ? 2 : 0) |
               (GetAsyncKeyState(VK_MENU) < 0 ? 4 : 0);
    int code = catch_code(vk, mods);
    if (code && PostMessageW(hwnd, WM_MB_CAUGHT_KEY, (WPARAM)code, (LPARAM)mods)) {
      if (vk < 256) catch_pressed[vk] = 1;
      return 1;
    }
  }
  return CallNextHookEx(catch_hook, n, kind, data);
}

// Installed only while a key catcher has the canvas's focus. Closing it or leaving the window restores the shell.
static void catch_keys_focus(int focused) {
  if (key_catching && focused) {
    if (!catch_hook) catch_hook = SetWindowsHookExW(WH_KEYBOARD_LL, catch_keyboard, GetModuleHandleW(NULL), 0);
  } else {
    if (catch_hook) UnhookWindowsHookEx(catch_hook);
    catch_hook = NULL;
    catch_win_held = 0;
    memset(catch_pressed, 0, sizeof catch_pressed);
  }
}

void mb_host_key_catch(int32_t on) {
  key_catching = on != 0;
  catch_keys_focus(GetForegroundWindow() == hwnd && GetFocus() == hwnd);
}
