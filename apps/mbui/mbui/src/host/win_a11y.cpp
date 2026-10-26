// The app's widgets for Windows' UI Automation (Narrator, NVDA, voice access, whatever reads the screen through it), as
// Android's A11y.java gives them to TalkBack: a provider for each node the app last said (src/ui/a11y.mbt,
// @hostapi.a11y_tree), kept by the node's number from frame to frame (one whose node is gone answers that it is no
// more), under the window's own (the fragment root, which WM_GETOBJECT hands out: mb_a11y_object). Each says its control
// type by the node's role, its name, its state and its rectangle on the screen, and the patterns its node can take:
// Invoke, Toggle, ExpandCollapse, SelectionItem, Value, RangeValue. What the reader asks (Invoke, Toggle, a slider's
// value) goes to the app on @hostapi.a11y_channel for its next frame, as on Android. The app tells its widgets once a
// reader asked for the window, while one listens (@hostapi.a11y_on); that first ask asks for a frame, so that they are
// told. As they change the readers are told: the window's children anew, the focus moved, a node's
// name, check, expansion, selection or value. All of it on the window's thread (COM's threading: the UI thread is a
// single-threaded apartment), the app's and the readers' calls alike.
//
// And the size of words the person set for reading (Settings, Accessibility, Text size: UISettings' TextScaleFactor,
// 1 to 2.25), the app's words that much bigger (@hostapi.font_scale, as Android's fontScale): read once, then as the
// system says it changed (a frame asked for then).
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <ole2.h>
#include <oleauto.h>
#include <uiautomation.h>
#include <roapi.h>
#include <wrl.h>
#include <wrl/wrappers/corewrappers.h>
#include <windows.ui.viewmanagement.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string>
#include <unordered_map>
#include <vector>
#include "win.h"

#pragma comment(lib, "uiautomationcore.lib")
#pragma comment(lib, "oleaut32.lib")
#pragma comment(lib, "runtimeobject.lib")

extern "C" void mb_post(const char *channel, const char *json, size_t len, const uint8_t *bytes, size_t blen);

namespace {

// A node as the app said it (a11y.mbt's line)
struct Node {
  int id = 0, parent = 0, widget = 0;
  std::wstring role, flags, label, value, description, actions;
  double x = 0, y = 0, w = 0, h = 0;
  bool range = false;
  double low = 0, at = 0, high = 0;
  std::vector<int> kids;
  bool has(wchar_t flag) const { return flags.find(flag) != std::wstring::npos; }
  bool can(wchar_t action) const { return actions.find(action) != std::wstring::npos; }
};

HWND win;
std::unordered_map<int, Node> nodes;
std::vector<int> tops;  // the nodes whose parent is the window, in order
int focused;            // the node with the keyboard's focus (0: none)
bool asked;             // a reader asked for the window (a frame asked for then, for the app to tell its widgets)

class Item;
class Root;
Root *root;
std::unordered_map<int, Item *> items;  // this side's providers, by node (one held here while its node is)

const Node *node_of(int id) {
  auto it = nodes.find(id);
  return it == nodes.end() ? nullptr : &it->second;
}

// what is asked of the node's widget, posted to the app (its next frame does it)
void ask(const Node *n, const char *action) {
  if (!n || !n->widget) return;
  char json[96];
  int len = snprintf(json, sizeof json, "{\"id\":%d,\"action\":\"%s\"}", n->widget, action);
  mb_post("a11y", json, (size_t)len, NULL, 0);
}

double scale_now() { return mb_app_scale(); }

// a node's rectangle on the screen (pixels)
UiaRect screen_rect(const Node *n) {
  POINT o = {0, 0};
  ClientToScreen(win, &o);
  double s = scale_now();
  return {o.x + n->x * s, o.y + n->y * s, n->w * s, n->h * s};
}

// a role's control type (ARIA's roles as UIA's: a switch a button that toggles, as Windows' own toggle switch is)
long control_type(const std::wstring &r) {
  static const std::unordered_map<std::wstring, long> types = {
      {L"Text", UIA_TextControlTypeId},           {L"Group", UIA_GroupControlTypeId},
      {L"Button", UIA_ButtonControlTypeId},       {L"Link", UIA_HyperlinkControlTypeId},
      {L"Checkbox", UIA_CheckBoxControlTypeId},   {L"Switch", UIA_ButtonControlTypeId},
      {L"Radio", UIA_RadioButtonControlTypeId},   {L"RadioGroup", UIA_GroupControlTypeId},
      {L"Slider", UIA_SliderControlTypeId},       {L"ProgressBar", UIA_ProgressBarControlTypeId},
      {L"Tab", UIA_TabItemControlTypeId},         {L"TabList", UIA_TabControlTypeId},
      {L"TabPanel", UIA_PaneControlTypeId},       {L"Dialog", UIA_WindowControlTypeId},
      {L"AlertDialog", UIA_WindowControlTypeId},  {L"Tooltip", UIA_ToolTipControlTypeId},
      {L"Menu", UIA_MenuControlTypeId},           {L"MenuBar", UIA_MenuBarControlTypeId},
      {L"MenuItem", UIA_MenuItemControlTypeId},   {L"MenuItemCheckbox", UIA_MenuItemControlTypeId},
      {L"MenuItemRadio", UIA_MenuItemControlTypeId}, {L"Listbox", UIA_ListControlTypeId},
      {L"Option", UIA_ListItemControlTypeId},     {L"Combobox", UIA_ComboBoxControlTypeId},
      {L"Toolbar", UIA_ToolBarControlTypeId},     {L"Separator", UIA_SeparatorControlTypeId},
      {L"Image", UIA_ImageControlTypeId},         {L"TextField", UIA_EditControlTypeId},
      {L"Status", UIA_TextControlTypeId},         {L"Region", UIA_GroupControlTypeId},
      {L"Navigation", UIA_GroupControlTypeId},    {L"Form", UIA_GroupControlTypeId},
      {L"Heading", UIA_TextControlTypeId},        {L"ScrollArea", UIA_PaneControlTypeId},
  };
  auto it = types.find(r);
  return it == types.end() ? UIA_GroupControlTypeId : it->second;
}

void put_bstr(VARIANT *v, const std::wstring &s) {
  v->vt = VT_BSTR;
  v->bstrVal = SysAllocStringLen(s.data(), (UINT)s.size());
}
void put_bool(VARIANT *v, bool b) {
  v->vt = VT_BOOL;
  v->boolVal = b ? VARIANT_TRUE : VARIANT_FALSE;
}
void put_i4(VARIANT *v, long n) {
  v->vt = VT_I4;
  v->lVal = n;
}

// the provider of the window's node `id` (0: the window's own), made where it is not yet
IRawElementProviderFragment *fragment_of(int id);

class Item : public IRawElementProviderSimple,
             public IRawElementProviderFragment,
             public IInvokeProvider,
             public IToggleProvider,
             public IExpandCollapseProvider,
             public ISelectionItemProvider,
             public IValueProvider,
             public IRangeValueProvider {
  LONG refs = 1;

 public:
  const int id;
  explicit Item(int id) : id(id) {}
  const Node *node() const { return node_of(id); }

  // IUnknown
  ULONG STDMETHODCALLTYPE AddRef() override { return (ULONG)InterlockedIncrement(&refs); }
  ULONG STDMETHODCALLTYPE Release() override {
    LONG r = InterlockedDecrement(&refs);
    if (r == 0) delete this;
    return (ULONG)r;
  }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **out) override {
    if (riid == __uuidof(IUnknown) || riid == __uuidof(IRawElementProviderSimple))
      *out = static_cast<IRawElementProviderSimple *>(this);
    else if (riid == __uuidof(IRawElementProviderFragment)) *out = static_cast<IRawElementProviderFragment *>(this);
    else if (riid == __uuidof(IInvokeProvider)) *out = static_cast<IInvokeProvider *>(this);
    else if (riid == __uuidof(IToggleProvider)) *out = static_cast<IToggleProvider *>(this);
    else if (riid == __uuidof(IExpandCollapseProvider)) *out = static_cast<IExpandCollapseProvider *>(this);
    else if (riid == __uuidof(ISelectionItemProvider)) *out = static_cast<ISelectionItemProvider *>(this);
    else if (riid == __uuidof(IValueProvider)) *out = static_cast<IValueProvider *>(this);
    else if (riid == __uuidof(IRangeValueProvider)) *out = static_cast<IRangeValueProvider *>(this);
    else {
      *out = NULL;
      return E_NOINTERFACE;
    }
    AddRef();
    return S_OK;
  }

  // IRawElementProviderSimple
  HRESULT STDMETHODCALLTYPE get_ProviderOptions(ProviderOptions *o) override {
    *o = (ProviderOptions)(ProviderOptions_ServerSideProvider | ProviderOptions_UseComThreading);
    return S_OK;
  }
  // which patterns its node takes
  bool takes(PATTERNID p, const Node *n) const {
    switch (p) {
      case UIA_InvokePatternId: return n->can(L'a') && !n->has(L'c') && !n->has(L'e');
      case UIA_TogglePatternId: return n->has(L'c');
      case UIA_ExpandCollapsePatternId: return n->has(L'e');
      case UIA_SelectionItemPatternId:
        return n->role == L"Tab" || n->role == L"Option" || n->role == L"Radio" || n->role == L"MenuItemRadio";
      case UIA_ValuePatternId: return n->role == L"TextField" || n->role == L"Combobox";
      case UIA_RangeValuePatternId: return n->range;
      default: return false;
    }
  }
  HRESULT STDMETHODCALLTYPE GetPatternProvider(PATTERNID p, IUnknown **out) override {
    *out = NULL;
    const Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    if (!takes(p, n)) return S_OK;
    switch (p) {
      case UIA_InvokePatternId: *out = static_cast<IInvokeProvider *>(this); break;
      case UIA_TogglePatternId: *out = static_cast<IToggleProvider *>(this); break;
      case UIA_ExpandCollapsePatternId: *out = static_cast<IExpandCollapseProvider *>(this); break;
      case UIA_SelectionItemPatternId: *out = static_cast<ISelectionItemProvider *>(this); break;
      case UIA_ValuePatternId: *out = static_cast<IValueProvider *>(this); break;
      case UIA_RangeValuePatternId: *out = static_cast<IRangeValueProvider *>(this); break;
    }
    AddRef();
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetPropertyValue(PROPERTYID p, VARIANT *v) override {
    v->vt = VT_EMPTY;
    const Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    switch (p) {
      case UIA_ControlTypePropertyId: put_i4(v, control_type(n->role)); break;
      case UIA_NamePropertyId:
        if (!n->label.empty()) put_bstr(v, n->label);
        break;
      case UIA_HelpTextPropertyId:
        if (!n->description.empty()) put_bstr(v, n->description);
        break;
      case UIA_AutomationIdPropertyId:
        if (n->widget) put_bstr(v, std::to_wstring(n->widget));
        break;
      case UIA_FrameworkIdPropertyId: put_bstr(v, L"mbui"); break;
      case UIA_IsEnabledPropertyId: put_bool(v, !n->has(L'd')); break;
      case UIA_HasKeyboardFocusPropertyId: put_bool(v, n->has(L'f')); break;
      case UIA_IsKeyboardFocusablePropertyId: put_bool(v, n->can(L'f') || n->has(L'f')); break;
      case UIA_IsControlElementPropertyId:
      case UIA_IsContentElementPropertyId: put_bool(v, true); break;
      case UIA_IsOffscreenPropertyId: put_bool(v, n->w <= 0 || n->h <= 0); break;
      case UIA_IsDialogPropertyId: put_bool(v, n->role == L"Dialog" || n->role == L"AlertDialog"); break;
      case UIA_LiveSettingPropertyId:
        if (n->role == L"Status") put_i4(v, Polite);
        break;
      case UIA_LandmarkTypePropertyId:
        if (n->role == L"Navigation") put_i4(v, UIA_NavigationLandmarkTypeId);
        else if (n->role == L"Form") put_i4(v, UIA_FormLandmarkTypeId);
        break;
      case UIA_HeadingLevelPropertyId:
        if (n->role == L"Heading") put_i4(v, HeadingLevel2);
        break;
    }
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE get_HostRawElementProvider(IRawElementProviderSimple **out) override {
    *out = NULL;
    return S_OK;
  }

  // IRawElementProviderFragment
  HRESULT STDMETHODCALLTYPE Navigate(NavigateDirection d, IRawElementProviderFragment **out) override;
  HRESULT STDMETHODCALLTYPE GetRuntimeId(SAFEARRAY **out) override {
    int rid[] = {UiaAppendRuntimeId, id};
    *out = SafeArrayCreateVector(VT_I4, 0, 2);
    if (!*out) return E_OUTOFMEMORY;
    for (LONG i = 0; i < 2; i++) SafeArrayPutElement(*out, &i, &rid[i]);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE get_BoundingRectangle(UiaRect *r) override {
    const Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    *r = screen_rect(n);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetEmbeddedFragmentRoots(SAFEARRAY **out) override {
    *out = NULL;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE SetFocus() override {
    const Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    if (n->can(L'f')) ask(n, "focus");
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE get_FragmentRoot(IRawElementProviderFragmentRoot **out) override;

  // IInvokeProvider
  HRESULT STDMETHODCALLTYPE Invoke() override {
    const Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    if (n->has(L'd')) return UIA_E_ELEMENTNOTENABLED;
    ask(n, "activate");
    return S_OK;
  }
  // IToggleProvider
  HRESULT STDMETHODCALLTYPE Toggle() override { return Invoke(); }
  HRESULT STDMETHODCALLTYPE get_ToggleState(ToggleState *s) override {
    const Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    *s = n->has(L'C') ? ToggleState_On : n->has(L'M') ? ToggleState_Indeterminate : ToggleState_Off;
    return S_OK;
  }
  // IExpandCollapseProvider
  HRESULT STDMETHODCALLTYPE Expand() override {
    const Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    if (!n->has(L'E')) ask(n, n->can(L'e') ? "expand" : "activate");
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE Collapse() override {
    const Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    if (n->has(L'E')) ask(n, n->can(L'c') ? "collapse" : "activate");
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE get_ExpandCollapseState(ExpandCollapseState *s) override {
    const Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    *s = n->has(L'E') ? ExpandCollapseState_Expanded : ExpandCollapseState_Collapsed;
    return S_OK;
  }
  // ISelectionItemProvider
  HRESULT STDMETHODCALLTYPE Select() override {
    const Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    if (!n->has(L's')) ask(n, "activate");
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE AddToSelection() override { return Select(); }
  HRESULT STDMETHODCALLTYPE RemoveFromSelection() override { return node() ? S_OK : UIA_E_ELEMENTNOTAVAILABLE; }
  HRESULT STDMETHODCALLTYPE get_IsSelected(BOOL *s) override {
    const Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    *s = n->has(L's');
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE get_SelectionContainer(IRawElementProviderSimple **out) override {
    *out = NULL;
    const Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    if (n->parent) {
      IRawElementProviderFragment *p = fragment_of(n->parent);
      if (p) {
        p->QueryInterface(IID_PPV_ARGS(out));
        p->Release();
      }
    }
    return S_OK;
  }
  // IValueProvider (what a field holds, read; the app takes no words from here)
  HRESULT STDMETHODCALLTYPE SetValue(LPCWSTR) override { return UIA_E_NOTSUPPORTED; }
  HRESULT STDMETHODCALLTYPE get_Value(BSTR *out) override {
    const Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    *out = SysAllocStringLen(n->value.data(), (UINT)n->value.size());
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE get_IsReadOnly(BOOL *ro) override {
    const Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    *ro = n->range ? !(n->can(L'i') || n->can(L'd')) : TRUE;
    return S_OK;
  }
  // IRangeValueProvider (a step up or down asked of the app, towards the value asked)
  HRESULT STDMETHODCALLTYPE SetValue(double v) override {
    const Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    if (v > n->at && n->can(L'i')) ask(n, "increment");
    else if (v < n->at && n->can(L'd')) ask(n, "decrement");
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE get_Value(double *v) override {
    const Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    *v = n->at;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE get_Maximum(double *v) override {
    const Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    *v = n->high;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE get_Minimum(double *v) override {
    const Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    *v = n->low;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE get_LargeChange(double *v) override {
    const Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    *v = (n->high - n->low) / 10;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE get_SmallChange(double *v) override {
    const Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    *v = (n->high - n->low) / 100;
    return S_OK;
  }
};

class Root : public IRawElementProviderSimple, public IRawElementProviderFragment, public IRawElementProviderFragmentRoot {
  LONG refs = 1;

 public:
  ULONG STDMETHODCALLTYPE AddRef() override { return (ULONG)InterlockedIncrement(&refs); }
  ULONG STDMETHODCALLTYPE Release() override {
    LONG r = InterlockedDecrement(&refs);
    if (r == 0) delete this;
    return (ULONG)r;
  }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **out) override {
    if (riid == __uuidof(IUnknown) || riid == __uuidof(IRawElementProviderSimple))
      *out = static_cast<IRawElementProviderSimple *>(this);
    else if (riid == __uuidof(IRawElementProviderFragment)) *out = static_cast<IRawElementProviderFragment *>(this);
    else if (riid == __uuidof(IRawElementProviderFragmentRoot))
      *out = static_cast<IRawElementProviderFragmentRoot *>(this);
    else {
      *out = NULL;
      return E_NOINTERFACE;
    }
    AddRef();
    return S_OK;
  }
  // IRawElementProviderSimple: the window's own (what the system says of it: its name, its rectangle)
  HRESULT STDMETHODCALLTYPE get_ProviderOptions(ProviderOptions *o) override {
    *o = (ProviderOptions)(ProviderOptions_ServerSideProvider | ProviderOptions_UseComThreading);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetPatternProvider(PATTERNID, IUnknown **out) override {
    *out = NULL;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetPropertyValue(PROPERTYID p, VARIANT *v) override {
    v->vt = VT_EMPTY;
    if (p == UIA_FrameworkIdPropertyId) put_bstr(v, L"mbui");
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE get_HostRawElementProvider(IRawElementProviderSimple **out) override {
    return UiaHostProviderFromHwnd(win, out);
  }
  // IRawElementProviderFragment
  HRESULT STDMETHODCALLTYPE Navigate(NavigateDirection d, IRawElementProviderFragment **out) override {
    *out = NULL;
    if (tops.empty()) return S_OK;
    if (d == NavigateDirection_FirstChild) *out = fragment_of(tops.front());
    else if (d == NavigateDirection_LastChild) *out = fragment_of(tops.back());
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetRuntimeId(SAFEARRAY **out) override {
    *out = NULL;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE get_BoundingRectangle(UiaRect *r) override {
    *r = {0, 0, 0, 0};
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetEmbeddedFragmentRoots(SAFEARRAY **out) override {
    *out = NULL;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE SetFocus() override { return S_OK; }
  HRESULT STDMETHODCALLTYPE get_FragmentRoot(IRawElementProviderFragmentRoot **out) override {
    *out = this;
    AddRef();
    return S_OK;
  }
  // IRawElementProviderFragmentRoot: the node under a point (the smallest that holds it), the one focused
  HRESULT STDMETHODCALLTYPE ElementProviderFromPoint(double sx, double sy, IRawElementProviderFragment **out) override {
    *out = NULL;
    POINT o = {0, 0};
    ClientToScreen(win, &o);
    double s = scale_now(), x = (sx - o.x) / s, y = (sy - o.y) / s, best = -1;
    int at = 0;
    for (auto &kv : nodes) {
      const Node &n = kv.second;
      if (x < n.x || y < n.y || x >= n.x + n.w || y >= n.y + n.h) continue;
      double area = n.w * n.h;
      if (best < 0 || area < best) best = area, at = n.id;
    }
    if (at) *out = fragment_of(at);
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE GetFocus(IRawElementProviderFragment **out) override {
    *out = focused ? fragment_of(focused) : NULL;
    return S_OK;
  }
};

IRawElementProviderFragment *fragment_of(int id) {
  if (id == 0) {
    if (!root) return NULL;
    root->AddRef();
    return static_cast<IRawElementProviderFragment *>(root);
  }
  if (!node_of(id)) return NULL;
  auto it = items.find(id);
  Item *it2 = it != items.end() ? it->second : (items[id] = new Item(id));
  it2->AddRef();
  return static_cast<IRawElementProviderFragment *>(it2);
}

HRESULT STDMETHODCALLTYPE Item::Navigate(NavigateDirection d, IRawElementProviderFragment **out) {
  *out = NULL;
  const Node *n = node();
  if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
  if (d == NavigateDirection_Parent) {
    *out = fragment_of(n->parent);
    return S_OK;
  }
  if (d == NavigateDirection_FirstChild || d == NavigateDirection_LastChild) {
    if (!n->kids.empty()) *out = fragment_of(d == NavigateDirection_FirstChild ? n->kids.front() : n->kids.back());
    return S_OK;
  }
  const Node *p = n->parent ? node_of(n->parent) : nullptr;
  const std::vector<int> &sibs = p ? p->kids : tops;
  for (size_t i = 0; i < sibs.size(); i++) {
    if (sibs[i] != id) continue;
    if (d == NavigateDirection_NextSibling && i + 1 < sibs.size()) *out = fragment_of(sibs[i + 1]);
    if (d == NavigateDirection_PreviousSibling && i > 0) *out = fragment_of(sibs[i - 1]);
    break;
  }
  return S_OK;
}

HRESULT STDMETHODCALLTYPE Item::get_FragmentRoot(IRawElementProviderFragmentRoot **out) {
  *out = NULL;
  if (!root) return UIA_E_ELEMENTNOTAVAILABLE;
  return root->QueryInterface(IID_PPV_ARGS(out));
}

// a line's fields (split by U+001F)
std::vector<std::wstring> fields_of(const wchar_t *s, size_t n) {
  std::vector<std::wstring> out(1);
  for (size_t i = 0; i < n; i++) {
    if (s[i] == 0x1F) out.emplace_back();
    else out.back().push_back(s[i]);
  }
  return out;
}

double number(const std::wstring &s) { return s.empty() ? 0 : _wtof(s.c_str()); }

// a property of an item told its readers changed (a name, a check, an expansion, a selection, a value)
void said_changed(int id, PROPERTYID p, VARIANT was, VARIANT now) {
  auto it = items.find(id);
  if (it != items.end()) UiaRaiseAutomationPropertyChangedEvent(it->second, p, was, now);
}

}  // namespace

extern "C" {

// Whether something reads the widgets out through UI Automation (@hostapi.a11y_on): a reader that asked for this
// window, while one listens (not merely one listening somewhere: the app makes its tree each frame only then)
int32_t mb_host_a11y_on(void) { return asked && UiaClientsAreListening() ? 1 : 0; }

// What the widgets are now (@hostapi.a11y_tree: a11y.mbt's lines): the nodes made anew, the readers told what changed
void mb_host_a11y_tree(moonbit_string_t s) {
  const wchar_t *t = (const wchar_t *)s;
  size_t n = (size_t)Moonbit_array_length(s);
  std::unordered_map<int, Node> next;
  std::vector<int> order;
  for (size_t i = 0; i < n;) {
    size_t e = i;
    while (e < n && t[e] != L'\n') e++;
    std::vector<std::wstring> f = fields_of(t + i, e - i);
    i = e + 1;
    if (f.size() < 16) continue;
    Node d;
    d.id = (int)number(f[0]), d.parent = (int)number(f[1]), d.widget = (int)number(f[2]);
    d.role = f[3], d.flags = f[4];
    d.x = number(f[5]), d.y = number(f[6]), d.w = number(f[7]), d.h = number(f[8]);
    d.label = f[9], d.value = f[10], d.description = f[11];
    d.range = !f[13].empty();
    d.low = number(f[12]), d.at = number(f[13]), d.high = number(f[14]);
    d.actions = f[15];
    if (!d.id || next.count(d.id)) continue;
    order.push_back(d.id);
    next[d.id] = d;
  }
  std::vector<int> top;
  for (int id : order) {
    Node &d = next[id];
    auto p = next.find(d.parent);
    if (d.parent && p != next.end()) p->second.kids.push_back(id);
    else d.parent = 0, top.push_back(id);
  }
  // what changed, as the readers are to hear it
  bool shape = top != tops || next.size() != nodes.size();
  int focus = 0;
  for (int id : order) {
    const Node &d = next[id];
    if (d.has(L'f')) focus = id;
    const Node *was = node_of(id);
    if (!was || was->parent != d.parent || was->kids != d.kids) shape = true;
  }
  std::unordered_map<int, Node> old;
  old.swap(nodes);
  nodes.swap(next);
  tops.swap(top);
  // providers of nodes gone let go (a reader holding one is told it is no more)
  for (auto it = items.begin(); it != items.end();) {
    if (!nodes.count(it->first)) {
      it->second->Release();
      it = items.erase(it);
    } else {
      ++it;
    }
  }
  if (!UiaClientsAreListening() || !root) {
    focused = focus;
    return;
  }
  for (auto &kv : items) {
    auto w = old.find(kv.first);
    const Node &d = nodes[kv.first];
    if (w == old.end()) continue;
    const Node &o = w->second;
    VARIANT a, b;
    VariantInit(&a), VariantInit(&b);
    if (o.label != d.label) {
      put_bstr(&a, o.label), put_bstr(&b, d.label);
      said_changed(d.id, UIA_NamePropertyId, a, b);
      VariantClear(&a), VariantClear(&b);
    }
    if (o.value != d.value) {
      put_bstr(&a, o.value), put_bstr(&b, d.value);
      said_changed(d.id, UIA_ValueValuePropertyId, a, b);
      VariantClear(&a), VariantClear(&b);
    }
    auto toggle = [](const Node &x) { return x.has(L'C') ? ToggleState_On : x.has(L'M') ? ToggleState_Indeterminate : ToggleState_Off; };
    if (d.has(L'c') && toggle(o) != toggle(d)) {
      put_i4(&a, toggle(o)), put_i4(&b, toggle(d));
      said_changed(d.id, UIA_ToggleToggleStatePropertyId, a, b);
    }
    if (d.has(L'e') && o.has(L'E') != d.has(L'E')) {
      put_i4(&a, o.has(L'E') ? ExpandCollapseState_Expanded : ExpandCollapseState_Collapsed);
      put_i4(&b, d.has(L'E') ? ExpandCollapseState_Expanded : ExpandCollapseState_Collapsed);
      said_changed(d.id, UIA_ExpandCollapseExpandCollapseStatePropertyId, a, b);
    }
    if (o.has(L's') != d.has(L's')) {
      put_bool(&a, o.has(L's')), put_bool(&b, d.has(L's'));
      said_changed(d.id, UIA_SelectionItemIsSelectedPropertyId, a, b);
    }
    if (d.range && o.at != d.at) {
      a.vt = b.vt = VT_R8, a.dblVal = o.at, b.dblVal = d.at;
      said_changed(d.id, UIA_RangeValueValuePropertyId, a, b);
    }
  }
  if (shape) UiaRaiseStructureChangedEvent(root, StructureChangeType_ChildrenInvalidated, NULL, 0);
  if (focus != focused) {
    focused = focus;
    IRawElementProviderFragment *f = focus ? fragment_of(focus) : NULL;
    if (f) {
      IRawElementProviderSimple *simple = NULL;
      f->QueryInterface(IID_PPV_ARGS(&simple));
      if (simple) UiaRaiseAutomationEvent(simple, UIA_AutomationFocusChangedEventId), simple->Release();
      f->Release();
    }
  }
}

// ---- the size of words ----

static double text_scale = 1.0;
static int text_scale_asked;
static Microsoft::WRL::ComPtr<ABI::Windows::UI::ViewManagement::IUISettings2> ui_settings;
static EventRegistrationToken text_scale_told;

static void text_scale_read(void) {
  double f = 1.0;
  if (ui_settings && SUCCEEDED(ui_settings->get_TextScaleFactor(&f)) && f >= 1.0) text_scale = f;
}

// Words as the app sizes them (@hostapi.font_scale): the system's Text size (1 as it is)
double mb_host_font_scale(void) {
  if (!text_scale_asked) {
    text_scale_asked = 1;
    using namespace Microsoft::WRL;
    using namespace Microsoft::WRL::Wrappers;
    using namespace ABI::Windows::UI::ViewManagement;
    using ABI::Windows::Foundation::ITypedEventHandler;
    ComPtr<IInspectable> made;
    if (SUCCEEDED(RoActivateInstance(HStringReference(RuntimeClass_Windows_UI_ViewManagement_UISettings).Get(), &made)) &&
        SUCCEEDED(made.As(&ui_settings))) {
      text_scale_read();
      // (said on a thread of the system's: kept, and a frame asked for, which reads it)
      ui_settings->add_TextScaleFactorChanged(
          Callback<ITypedEventHandler<UISettings *, IInspectable *>>([](IUISettings *, IInspectable *) -> HRESULT {
            text_scale_read();
            mb_app_wake();
            return S_OK;
          }).Get(),
          &text_scale_told);
    }
  }
  return text_scale;
}

// WM_GETOBJECT (win_app.c): the window's fragment root for UI Automation's ask; 1 answered (its answer in *r). The
// first ask a frame's, for the app to tell its widgets now that something reads them.
int mb_a11y_object(void *hwnd, uintptr_t wp, intptr_t lp, intptr_t *r) {
  if ((long)lp != UiaRootObjectId) return 0;
  win = (HWND)hwnd;
  if (!root) root = new Root();
  if (!asked) {
    asked = true;
    mb_app_wake();
  }
  *r = UiaReturnRawElementProvider(win, (WPARAM)wp, (LPARAM)lp, root);
  return 1;
}

}  // extern "C"
