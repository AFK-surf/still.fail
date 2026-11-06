// A character key with no input method belongs to the app as a key. It may focus an editor synchronously, but its
// WM_CHAR must not also go to that editor. Child windows keep their own input handling; the next key is translated
// once the editor has the keyboard.
static void mb_win_input_dispatch(const MSG *m, HWND app, int ime_active) {
  if (m->hwnd != app || m->message != WM_KEYDOWN || ime_active) TranslateMessage(m);
  DispatchMessageW(m);
}
