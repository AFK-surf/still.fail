// Notifications on Windows (src/hostapi/notify.mbt), as mac_app.m has them: the system's toasts (ToastNotificationManager,
// WinRT through its ABI and WRL, nothing packaged) where the program is an app (its identity, MBUI_APP_ID: win_life.h),
// one per tag (a newer one with the same tag takes its place in the system's list too), tapped it brings the app to
// the front with what it was shown with (its Activated, on a thread of the system's: what it opens kept for the app's
// next frame, the window brought back on its own thread: WM_MB_TAPPED). A program without one keeps them only. Either
// way each is kept (one per tag) and said on the log (NOTICE <tag>\t<title>\t<body>), and a scripted run taps one by
// its words (mb_notice_drive: drive 6), which gives the app what it opens as a tap would, or looks for one (7).
//
// An app outside a package shows toasts under its AppUserModelID (the process's: win_life.h life_identity) once the
// system knows that id's name and icon: HKCU\Software\Classes\AppUserModelId\<id> (DisplayName, IconUri), written as
// the first is shown, the icon the program's own (its resource 1's largest picture, a PNG: written beside its data).
// What the system allows: its settings for the app (the notifier's Setting), nothing to ask (Windows asks no app).
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <roapi.h>
#include <wrl.h>
#include <wrl/wrappers/corewrappers.h>
#include <windows.ui.notifications.h>
#include <windows.data.xml.dom.h>
#include <stdio.h>
#include <string>
#include <vector>
#include "win.h"

#pragma comment(lib, "runtimeobject.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "ole32.lib")

using namespace Microsoft::WRL;
using namespace Microsoft::WRL::Wrappers;
using namespace ABI::Windows::Data::Xml::Dom;
using namespace ABI::Windows::Foundation;
using namespace ABI::Windows::UI::Notifications;

namespace {

struct Notice {
  std::wstring tag, title, body, opens;
  ComPtr<IToastNotification> toast;
  EventRegistrationToken activated{};
};

std::vector<Notice> notices;
SRWLOCK opened_lock = SRWLOCK_INIT;
std::wstring opened;  // what the last one tapped opens, till the app takes it
int toasts = -1;      // -1 not tried yet, 0 none (no identity, no WinRT), 1 the system's
ComPtr<IToastNotifier> notifier;
ComPtr<IToastNotificationHistory> history;
std::wstring aumid;
const wchar_t *const group = L"mbui";

std::wstring wide(moonbit_string_t s) { return std::wstring((const wchar_t *)s, (size_t)Moonbit_array_length(s)); }

moonbit_string_t of(const std::wstring &s) {
  moonbit_string_t out = moonbit_make_string_raw((int32_t)s.size());
  if (!s.empty()) memcpy(out, s.data(), s.size() * sizeof(wchar_t));
  return out;
}

std::string utf8(const std::wstring &w) {
  int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), NULL, 0, NULL, NULL);
  std::string s((size_t)n, '\0');
  if (n) WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), &s[0], n, NULL, NULL);
  return s;
}

// a tag as the system takes it (at most 64 characters): its FNV-1a 64's hex
std::wstring system_tag(const std::wstring &tag) {
  unsigned long long h = 1469598103934665603ull;
  for (wchar_t c : tag) {
    h ^= (unsigned long long)c;
    h *= 1099511628211ull;
  }
  wchar_t b[17];
  _snwprintf(b, 17, L"%016llx", h);
  b[16] = 0;
  return b;
}

std::wstring xml_escaped(const std::wstring &s) {
  std::wstring o;
  for (wchar_t c : s) {
    switch (c) {
      case L'&': o += L"&amp;"; break;
      case L'<': o += L"&lt;"; break;
      case L'>': o += L"&gt;"; break;
      case L'"': o += L"&quot;"; break;
      case L'\'': o += L"&apos;"; break;
      default:
        // (control characters but a line's end are not XML's)
        if (c >= 0x20 || c == L'\n' || c == L'\t') o += c;
    }
  }
  return o;
}

// the program's own icon's largest picture (its group 1's entries: PNGs, still.fail's scripts/win.sh), as a file
// beside the app's data the system can read: its path, "" none
std::wstring own_icon_file(const std::wstring &id) {
  HMODULE m = GetModuleHandleW(NULL);
  HRSRC g = FindResourceW(m, MAKEINTRESOURCEW(1), MAKEINTRESOURCEW(14));  // RT_GROUP_ICON
  const BYTE *dir = g ? (const BYTE *)LockResource(LoadResource(m, g)) : NULL;
  if (!dir) return L"";
  // GRPICONDIR: reserved, type, count; then 14-byte entries (width, height, colours, reserved, planes, bits, size, id)
  int count = dir[4] | dir[5] << 8, best = -1, best_w = -1;
  for (int i = 0; i < count; i++) {
    const BYTE *e = dir + 6 + 14 * i;
    int w = e[0] ? e[0] : 256;
    if (w > best_w) best_w = w, best = e[12] | e[13] << 8;
  }
  HRSRC r = best >= 0 ? FindResourceW(m, MAKEINTRESOURCEW(best), MAKEINTRESOURCEW(3))  /* RT_ICON */ : NULL;
  const BYTE *png = r ? (const BYTE *)LockResource(LoadResource(m, r)) : NULL;
  DWORD n = r ? SizeofResource(m, r) : 0;
  if (!png || n < 8 || memcmp(png, "\x89PNG", 4) != 0) return L"";
  PWSTR local = NULL;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, NULL, &local))) return L"";
  std::wstring dirpath = std::wstring(local) + L"\\" + id;
  CoTaskMemFree(local);
  SHCreateDirectoryExW(NULL, dirpath.c_str(), NULL);
  std::wstring path = dirpath + L"\\notice-icon.png";
  HANDLE f = CreateFileW(path.c_str(), GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
  if (f == INVALID_HANDLE_VALUE) return L"";
  DWORD put = 0;
  BOOL ok = WriteFile(f, png, n, &put, NULL) && put == n;
  CloseHandle(f);
  return ok ? path : L"";
}

// the system told the app's name and icon for its id (what an app outside a package shows toasts with)
void register_id(const std::wstring &id) {
  std::wstring key = L"Software\\Classes\\AppUserModelId\\" + id;
  HKEY k = NULL;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, key.c_str(), 0, NULL, 0, KEY_SET_VALUE, NULL, &k, NULL) != ERROR_SUCCESS) return;
  std::wstring shown = mb_win_app_name();
  if (shown.empty()) shown = id;
  RegSetValueExW(k, L"DisplayName", 0, REG_SZ, (const BYTE *)shown.c_str(), (DWORD)((shown.size() + 1) * sizeof(wchar_t)));
  std::wstring icon = own_icon_file(id);
  if (!icon.empty())
    RegSetValueExW(k, L"IconUri", 0, REG_SZ, (const BYTE *)icon.c_str(), (DWORD)((icon.size() + 1) * sizeof(wchar_t)));
  RegCloseKey(k);
}

// the system's notifier for the app's id, made as the first is shown: 1 when there is one
int toasts_ready() {
  if (toasts >= 0) return toasts;
  toasts = 0;
  aumid = mb_win_app_id();
  if (aumid.empty()) return 0;
  register_id(aumid);
  ComPtr<IToastNotificationManagerStatics> mgr;
  if (FAILED(::Windows::Foundation::GetActivationFactory(HStringReference(RuntimeClass_Windows_UI_Notifications_ToastNotificationManager).Get(), &mgr)))
    return 0;
  if (FAILED(mgr->CreateToastNotifierWithId(HStringReference(aumid.c_str()).Get(), &notifier))) return 0;
  ComPtr<IToastNotificationManagerStatics2> mgr2;
  if (SUCCEEDED(mgr.As(&mgr2))) mgr2->get_History(&history);
  toasts = 1;
  return 1;
}

// its toast, in the system's list under its tag
ComPtr<IToastNotification> toast_of(const Notice &n) {
  std::wstring xml = L"<toast><visual><binding template=\"ToastGeneric\"><text>" + xml_escaped(n.title) + L"</text><text>" +
                     xml_escaped(n.body) + L"</text></binding></visual></toast>";
  ComPtr<IInspectable> made;
  ComPtr<IXmlDocument> doc;
  ComPtr<IXmlDocumentIO> io;
  if (FAILED(RoActivateInstance(HStringReference(RuntimeClass_Windows_Data_Xml_Dom_XmlDocument).Get(), &made)) ||
      FAILED(made.As(&doc)) || FAILED(made.As(&io)) || FAILED(io->LoadXml(HStringReference(xml.c_str()).Get())))
    return nullptr;
  ComPtr<IToastNotificationFactory> factory;
  ComPtr<IToastNotification> toast;
  if (FAILED(::Windows::Foundation::GetActivationFactory(HStringReference(RuntimeClass_Windows_UI_Notifications_ToastNotification).Get(), &factory)) ||
      FAILED(factory->CreateToastNotification(doc.Get(), &toast)))
    return nullptr;
  ComPtr<IToastNotification2> tagged;
  if (SUCCEEDED(toast.As(&tagged))) {
    tagged->put_Tag(HStringReference(system_tag(n.tag).c_str()).Get());
    tagged->put_Group(HStringReference(group).Get());
  }
  return toast;
}

// a tap: what it opens kept for the app, the window brought back on its own thread
void tapped(const std::wstring &tag, const std::wstring &opens) {
  AcquireSRWLockExclusive(&opened_lock);
  opened = opens;
  ReleaseSRWLockExclusive(&opened_lock);
  fprintf(stdout, "NOTICE TAP %s\n", utf8(tag).c_str());
  fflush(stdout);
  PostMessageW((HWND)mb_app_hwnd(), WM_MB_TAPPED, 0, 0);
  mb_app_wake();
}

void forget(const std::wstring &tag) {
  for (size_t i = 0; i < notices.size(); i++)
    if (notices[i].tag == tag) {
      if (notices[i].toast) notices[i].toast->remove_Activated(notices[i].activated);
      notices.erase(notices.begin() + (long)i);
      return;
    }
}

}  // namespace

extern "C" {

void mb_host_notice_show(moonbit_string_t channel, moonbit_string_t tag, moonbit_string_t title, moonbit_string_t body,
                         moonbit_string_t opens) {
  (void)channel;  // (one list per app: Windows has no channels of an app's)
  Notice n{wide(tag), wide(title), wide(body), wide(opens), nullptr, {}};
  forget(n.tag);
  fprintf(stdout, "NOTICE %s\t%s\t%s\n", utf8(n.tag).c_str(), utf8(n.title).c_str(), utf8(n.body).c_str());
  fflush(stdout);
  if (toasts_ready() && (n.toast = toast_of(n))) {
    std::wstring t = n.tag, o = n.opens;
    n.toast->add_Activated(Callback<ITypedEventHandler<ToastNotification *, IInspectable *>>(
                               [t, o](IToastNotification *, IInspectable *) -> HRESULT {
                                 tapped(t, o);
                                 return S_OK;
                               })
                               .Get(),
                           &n.activated);
    HRESULT shown = notifier->Show(n.toast.Get());
    fprintf(stdout, SUCCEEDED(shown) ? "NOTICE shown by the system\n" : "NOTICE not shown by the system (%08lx)\n",
            (unsigned long)shown);
    fflush(stdout);
  }
  notices.push_back(n);
}

void mb_host_notice_cancel(moonbit_string_t tag_s) {
  std::wstring tag = wide(tag_s);
  forget(tag);
  if (toasts == 1 && history)
    history->RemoveGroupedTagWithId(HStringReference(system_tag(tag).c_str()).Get(), HStringReference(group).Get(),
                                    HStringReference(aumid.c_str()).Get());
}

int32_t mb_host_notice_state(int32_t what) {
  switch (what) {
    // what the system allows: the app's settings there (on unless turned off), unknown without its notifier
    case 0: {
      if (!toasts_ready()) return 0;
      NotificationSetting s = NotificationSetting_Enabled;
      if (FAILED(notifier->get_Setting(&s))) return 0;
      return s == NotificationSetting_Enabled ? 1 : 2;
    }
    // (nothing to ask on Windows: no answer)
    case 1: return 0;
    case 2: return -1;
    // the system's settings of notifications opened
    case 3: return (INT_PTR)ShellExecuteW(NULL, L"open", L"ms-settings:notifications", NULL, NULL, SW_SHOWNORMAL) > 32 ? 1 : 0;
    // the number on the app's icon: not shown here (the taskbar's overlay is not drawn)
    default: return 0;
  }
}

moonbit_string_t mb_host_notice_text(int32_t what) {
  if (what != 0) return moonbit_make_string_raw(0);  // (no push service here)
  AcquireSRWLockExclusive(&opened_lock);
  std::wstring o = opened;
  opened.clear();
  ReleaseSRWLockExclusive(&opened_lock);
  return of(o);
}

// A scripted run's: the one whose title or words hold `text` tapped (1 when there is one), or only looked for.
int32_t mb_notice_drive(int32_t tap, const wchar_t *text) {
  for (size_t i = 0; i < notices.size(); i++) {
    const Notice &n = notices[i];
    if (n.title.find(text) == std::wstring::npos && n.body.find(text) == std::wstring::npos) continue;
    if (tap) {
      std::wstring tag = n.tag, opens = n.opens;
      if (toasts == 1 && history)
        history->RemoveGroupedTagWithId(HStringReference(system_tag(tag).c_str()).Get(), HStringReference(group).Get(),
                                        HStringReference(aumid.c_str()).Get());
      forget(tag);
      tapped(tag, opens);
    }
    return 1;
  }
  return 0;
}

}  // extern "C"
