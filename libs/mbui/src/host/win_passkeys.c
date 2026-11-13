// This device's passkeys for the Windows host (host_native.mbt `wa_*`, hostapi/passkeys.mbt): Windows' WebAuthn API
// (webauthn.dll, Windows 10 1903 and later), asked to sign the client data the app gives for a relying party as a
// browser asks it. Windows asks the person itself (Windows Hello, a phone, a security key, or a passkey provider such as
// 1Password) in its own window over the app's; the ask runs on a thread of its own, its answer kept until the app takes
// it: win_passwords.c's way.
#include <windows.h>
#include <webauthn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "win.h"

void mb_host_request_frame(void);

typedef HRESULT(WINAPI *get_assertion_fn)(HWND, LPCWSTR, PCWEBAUTHN_CLIENT_DATA, PCWEBAUTHN_AUTHENTICATOR_GET_ASSERTION_OPTIONS,
                                          PWEBAUTHN_ASSERTION *);
typedef void(WINAPI *free_assertion_fn)(PWEBAUTHN_ASSERTION);
typedef PCWSTR(WINAPI *error_name_fn)(HRESULT);

static get_assertion_fn get_assertion;
static free_assertion_fn free_assertion;
static error_name_fn error_name;
static INIT_ONCE loaded = INIT_ONCE_STATIC_INIT;

static BOOL CALLBACK load(PINIT_ONCE once, PVOID p, PVOID *ctx) {
  (void)once, (void)p, (void)ctx;
  HMODULE m = LoadLibraryExW(L"webauthn.dll", NULL, LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (m) {
    get_assertion = (get_assertion_fn)(void *)GetProcAddress(m, "WebAuthNAuthenticatorGetAssertion");
    free_assertion = (free_assertion_fn)(void *)GetProcAddress(m, "WebAuthNFreeAssertion");
    error_name = (error_name_fn)(void *)GetProcAddress(m, "WebAuthNGetErrorName");
  }
  return TRUE;
}

static BOOL able(void) {
  InitOnceExecuteOnce(&loaded, load, NULL, NULL);
  return get_assertion && free_assertion;
}

typedef struct ask {
  int id;
  // How it ended, once it has: "<code>\x1f<credential>\x1f<authenticator data>\x1f<signature>\x1f<user>\x1f<why>\x1f"
  // (hex, UTF-8).
  char *done;
  struct ask *next;
} ask;

static SRWLOCK lock = SRWLOCK_INIT;
static ask *asks;
static int ask_next;

static ask *find(int id) {
  for (ask *a = asks; a; a = a->next)
    if (a->id == id) return a;
  return NULL;
}

/// What the thread asks with: the window to ask over, the relying party, the client data (UTF-8), the verification,
/// the credentials taken.
typedef struct asking {
  int id;
  HWND window;
  WCHAR *rp;
  char *client;
  DWORD uv;
  WEBAUTHN_CREDENTIAL *creds;
  BYTE *ids;
  DWORD count;
} asking;

static void hex(char *out, const BYTE *b, DWORD n) {
  static const char d[] = "0123456789abcdef";
  for (DWORD i = 0; i < n; i++) {
    out[2 * i] = d[b[i] >> 4];
    out[2 * i + 1] = d[b[i] & 15];
  }
  out[2 * n] = 0;
}

static void keep(int id, char *done) {
  AcquireSRWLockExclusive(&lock);
  ask *a = find(id);
  if (a && !a->done) a->done = done;
  else free(done);
  ReleaseSRWLockExclusive(&lock);
  mb_host_request_frame();
}

static DWORD WINAPI run_ask(LPVOID p) {
  asking *w = p;
  WEBAUTHN_CLIENT_DATA client = {WEBAUTHN_CLIENT_DATA_CURRENT_VERSION, (DWORD)strlen(w->client), (PBYTE)w->client,
                                 WEBAUTHN_HASH_ALGORITHM_SHA_256};
  WEBAUTHN_AUTHENTICATOR_GET_ASSERTION_OPTIONS options = {0};
  options.dwVersion = WEBAUTHN_AUTHENTICATOR_GET_ASSERTION_OPTIONS_VERSION_1;
  options.dwTimeoutMilliseconds = 120000;
  options.CredentialList.cCredentials = w->count;
  options.CredentialList.pCredentials = w->creds;
  options.dwUserVerificationRequirement = w->uv;
  PWEBAUTHN_ASSERTION got = NULL;
  HRESULT hr = get_assertion(w->window, w->rp, &client, &options, &got);
  char *done;
  if (SUCCEEDED(hr) && got) {
    size_t len = 2 * ((size_t)got->Credential.cbId + got->cbAuthenticatorData + got->cbSignature + got->cbUserId) + 32;
    done = malloc(len);
    size_t at = 0;
    done[at++] = '0';
    done[at++] = 0x1f;
    hex(done + at, got->Credential.pbId, got->Credential.cbId);
    at += 2 * (size_t)got->Credential.cbId;
    done[at++] = 0x1f;
    hex(done + at, got->pbAuthenticatorData, got->cbAuthenticatorData);
    at += 2 * (size_t)got->cbAuthenticatorData;
    done[at++] = 0x1f;
    hex(done + at, got->pbSignature, got->cbSignature);
    at += 2 * (size_t)got->cbSignature;
    done[at++] = 0x1f;
    hex(done + at, got->pbUserId, got->cbUserId);
    at += 2 * (size_t)got->cbUserId;
    done[at++] = 0x1f;
    done[at++] = 0x1f;
    done[at] = 0;
    free_assertion(got);
  } else {
    // The person said no, or none of the device's passkeys is the site's: as a browser says it (NotAllowedError).
    BOOL no = hr == NTE_USER_CANCELLED || hr == NTE_NOT_FOUND || hr == HRESULT_FROM_WIN32(ERROR_CANCELLED);
    char why[256] = "";
    PCWSTR name = error_name ? error_name(hr) : NULL;
    if (name) WideCharToMultiByte(CP_UTF8, 0, name, -1, why, sizeof why, NULL, NULL);
    else snprintf(why, sizeof why, "0x%08lx", (unsigned long)hr);
    size_t len = strlen(why) + 16;
    done = malloc(len);
    snprintf(done, len, "%d\x1f\x1f\x1f\x1f\x1f%s\x1f", no ? 1 : -1, why);
  }
  keep(w->id, done);
  free(w->rp);
  free(w->client);
  free(w->creds);
  free(w->ids);
  free(w);
  return 0;
}

int32_t mb_host_passkeys_able(void) { return able() ? 1 : 0; }

static int nibble(WCHAR c) {
  if (c >= L'0' && c <= L'9') return c - L'0';
  if (c >= L'a' && c <= L'f') return c - L'a' + 10;
  if (c >= L'A' && c <= L'F') return c - L'A' + 10;
  return -1;
}

/// `ask`: the relying party, the client data, the verification and the credential ids (hex, joined by commas), each
/// ended by a unit separator (U+001F), as hostapi/passkeys.mbt gives them.
int32_t mb_host_passkeys_get(moonbit_string_t ask_) {
  if (!able()) return 0;
  const WCHAR *s = (const WCHAR *)ask_;
  int n = Moonbit_array_length(ask_);
  int starts[5] = {0}, parts = 0;
  for (int i = 0; i < n && parts < 4; i++)
    if (s[i] == 0x1f) starts[++parts] = i + 1;
  if (parts < 4) return 0;
  asking *w = calloc(1, sizeof *w);
  // the relying party
  int rp_len = starts[1] - 1;
  w->rp = malloc(((size_t)rp_len + 1) * sizeof(WCHAR));
  memcpy(w->rp, s, (size_t)rp_len * sizeof(WCHAR));
  w->rp[rp_len] = 0;
  // the client data, as UTF-8: what is signed is its hash
  int cd_len = starts[2] - 1 - starts[1];
  int bytes = WideCharToMultiByte(CP_UTF8, 0, s + starts[1], cd_len, NULL, 0, NULL, NULL);
  w->client = malloc((size_t)bytes + 1);
  WideCharToMultiByte(CP_UTF8, 0, s + starts[1], cd_len, w->client, bytes, NULL, NULL);
  w->client[bytes] = 0;
  // the verification
  const WCHAR *uv = s + starts[2];
  int uv_len = starts[3] - 1 - starts[2];
  w->uv = uv_len == 8 && !wcsncmp(uv, L"required", 8)      ? WEBAUTHN_USER_VERIFICATION_REQUIREMENT_REQUIRED
          : uv_len == 11 && !wcsncmp(uv, L"discouraged", 11) ? WEBAUTHN_USER_VERIFICATION_REQUIREMENT_DISCOURAGED
                                                             : WEBAUTHN_USER_VERIFICATION_REQUIREMENT_PREFERRED;
  // the credentials taken, their ids in one buffer
  int from = starts[3], to = starts[4] - 1;
  w->ids = malloc((size_t)(to - from) / 2 + 1);
  DWORD count = 0;
  for (int i = from; i < to; i++)
    if (s[i] == L',') count++;
  if (to > from) count++;
  w->creds = calloc(count ? count : 1, sizeof(WEBAUTHN_CREDENTIAL));
  size_t at = 0;
  DWORD k = 0;
  for (int i = from; i < to && k < count;) {
    size_t start = at;
    while (i + 1 < to && s[i] != L',') {
      int hi = nibble(s[i]), lo = nibble(s[i + 1]);
      if (hi < 0 || lo < 0) break;
      w->ids[at++] = (BYTE)(hi * 16 + lo);
      i += 2;
    }
    while (i < to && s[i] != L',') i++;
    i++;
    if (at > start) {
      w->creds[k].dwVersion = WEBAUTHN_CREDENTIAL_CURRENT_VERSION;
      w->creds[k].cbId = (DWORD)(at - start);
      w->creds[k].pbId = w->ids + start;
      w->creds[k].pwszCredentialType = WEBAUTHN_CREDENTIAL_TYPE_PUBLIC_KEY;
      k++;
    }
  }
  w->count = k;
  // asked over the window the person pressed in
  w->window = GetForegroundWindow();
  ask *a = calloc(1, sizeof *a);
  AcquireSRWLockExclusive(&lock);
  a->id = ++ask_next;
  a->next = asks;
  asks = a;
  w->id = a->id;
  ReleaseSRWLockExclusive(&lock);
  int id = w->id;
  HANDLE t = CreateThread(NULL, 0, run_ask, w, 0, NULL);
  if (t) {
    CloseHandle(t);
  } else {
    char *done = _strdup("-1\x1f\x1f\x1f\x1f\x1fno thread\x1f");
    keep(id, done);
    free(w->rp);
    free(w->client);
    free(w->creds);
    free(w->ids);
    free(w);
  }
  return id;
}

moonbit_string_t mb_host_passkeys_out(int32_t id) {
  AcquireSRWLockShared(&lock);
  ask *a = find(id);
  WCHAR *w = NULL;
  int n = 0;
  if (a && a->done) {
    n = MultiByteToWideChar(CP_UTF8, 0, a->done, -1, NULL, 0) - 1;
    w = malloc(((size_t)n + 1) * sizeof(WCHAR));
    MultiByteToWideChar(CP_UTF8, 0, a->done, -1, w, n + 1);
  }
  ReleaseSRWLockShared(&lock);
  moonbit_string_t out = moonbit_make_string_raw(n > 0 ? n : 0);
  if (n > 0) memcpy(out, w, (size_t)n * sizeof(WCHAR));
  free(w);
  return out;
}

/// Forgets it: an ask still open with Windows ends by itself (its window closed by the person, or its time out), its
/// answer then dropped.
void mb_host_passkeys_end(int32_t id) {
  AcquireSRWLockExclusive(&lock);
  for (ask **p = &asks; *p; p = &(*p)->next) {
    if ((*p)->id != id) continue;
    ask *a = *p;
    *p = a->next;
    free(a->done);
    free(a);
    break;
  }
  ReleaseSRWLockExclusive(&lock);
}
