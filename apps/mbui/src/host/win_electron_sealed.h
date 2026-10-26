// What still.fail's desktop app (Electron's, apps/desktop/src/secure.ts) kept sealed on Windows, opened for the app built
// in its place (scripts/win.sh's stable and beta variants: its id, its data). win_core.c's secure.get takes a key from it
// the first time the core asks for one this app does not have, and seals it again in its own files, as
// electron_sealed.h does on the Mac. A file of that app's userData\sealed: "SFS1", the `user` byte, then Electron's
// safeStorage sealing of "<user>:<the value in base64url>": Chromium's OSCrypt on Windows ("v10", a 12-byte nonce,
// AES-256-GCM's text and its 16-byte tag), under the key its userData\Local State keeps sealed by DPAPI for this Windows
// user (os_crypt.encrypted_key: base64 of "DPAPI" and the sealed key). Included by win_core.c and
// core/sealed_test_win.c.
#pragma once
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <bcrypt.h>
#include <wincrypt.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma comment(lib, "bcrypt.lib")
#pragma comment(lib, "crypt32.lib")

// base64 (`url`: its URL alphabet, - and _), padding or none: the bytes (malloc'd), NULL where it is none
static uint8_t *es_b64(const char *s, size_t n, size_t *out_n, int url) {
  uint8_t *out = (uint8_t *)malloc(n * 3 / 4 + 3);
  if (!out) return NULL;
  uint32_t acc = 0;
  int bits = 0;
  size_t k = 0;
  for (size_t i = 0; i < n; i++) {
    char c = s[i];
    int v;
    if (c >= 'A' && c <= 'Z') v = c - 'A';
    else if (c >= 'a' && c <= 'z') v = c - 'a' + 26;
    else if (c >= '0' && c <= '9') v = c - '0' + 52;
    else if (c == (url ? '-' : '+')) v = 62;
    else if (c == (url ? '_' : '/')) v = 63;
    else if (c == '=') break;
    else {
      free(out);
      return NULL;
    }
    acc = acc << 6 | (uint32_t)v;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out[k++] = (uint8_t)(acc >> bits);
    }
  }
  *out_n = k;
  return out;
}

static uint8_t *es_read(const WCHAR *path, size_t *n) {
  HANDLE f = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
  if (f == INVALID_HANDLE_VALUE) return NULL;
  LARGE_INTEGER size;
  if (!GetFileSizeEx(f, &size) || size.QuadPart > (16 << 20)) {
    CloseHandle(f);
    return NULL;
  }
  uint8_t *b = (uint8_t *)malloc((size_t)size.QuadPart + 1);
  DWORD got = 0;
  BOOL ok = b && ReadFile(f, b, (DWORD)size.QuadPart, &got, NULL) && got == (DWORD)size.QuadPart;
  CloseHandle(f);
  if (!ok) {
    free(b);
    return NULL;
  }
  b[got] = 0;
  *n = got;
  return b;
}

// The key safeStorage seals with (32 bytes), from `userdata`\Local State: 1 when had
static int es_key(const WCHAR *userdata, uint8_t key[32]) {
  WCHAR path[MAX_PATH * 2];
  _snwprintf(path, MAX_PATH * 2, L"%ls\\Local State", userdata);
  path[MAX_PATH * 2 - 1] = 0;
  size_t n = 0;
  char *state = (char *)es_read(path, &n);
  if (!state) return 0;
  const char *at = strstr(state, "\"encrypted_key\"");
  const char *q = at ? strchr(at + 15, ':') : NULL;
  q = q ? strchr(q, '"') : NULL;
  const char *end = q ? strchr(q + 1, '"') : NULL;
  int ok = 0;
  size_t bn = 0;
  uint8_t *b = end ? es_b64(q + 1, (size_t)(end - q - 1), &bn, 0) : NULL;
  if (b && bn > 5 && memcmp(b, "DPAPI", 5) == 0) {
    DATA_BLOB in = {(DWORD)(bn - 5), b + 5}, plain = {0};
    if (CryptUnprotectData(&in, NULL, NULL, NULL, NULL, CRYPTPROTECT_UI_FORBIDDEN, &plain)) {
      if (plain.cbData == 32) memcpy(key, plain.pbData, 32), ok = 1;
      SecureZeroMemory(plain.pbData, plain.cbData);
      LocalFree(plain.pbData);
    }
  }
  free(b);
  free(state);
  return ok;
}

// OSCrypt's "v10" sealing opened with `key`: the plain bytes (malloc'd, a NUL after them), NULL where it does not open
static uint8_t *es_unseal(const uint8_t key[32], const uint8_t *s, size_t n, size_t *out_n) {
  if (n < 3 + 12 + 16 || memcmp(s, "v10", 3) != 0) return NULL;
  const uint8_t *nonce = s + 3, *text = s + 15;
  size_t tn = n - 15 - 16;
  const uint8_t *tag = s + n - 16;
  BCRYPT_ALG_HANDLE alg = NULL;
  BCRYPT_KEY_HANDLE k = NULL;
  uint8_t *out = (uint8_t *)malloc(tn + 1);
  ULONG got = 0;
  int ok = out && BCRYPT_SUCCESS(BCryptOpenAlgorithmProvider(&alg, BCRYPT_AES_ALGORITHM, NULL, 0)) &&
           BCRYPT_SUCCESS(BCryptSetProperty(alg, BCRYPT_CHAINING_MODE, (PUCHAR)BCRYPT_CHAIN_MODE_GCM,
                                            (ULONG)sizeof BCRYPT_CHAIN_MODE_GCM, 0)) &&
           BCRYPT_SUCCESS(BCryptGenerateSymmetricKey(alg, &k, NULL, 0, (PUCHAR)key, 32, 0));
  if (ok) {
    BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO info;
    BCRYPT_INIT_AUTH_MODE_INFO(info);
    info.pbNonce = (PUCHAR)nonce;
    info.cbNonce = 12;
    info.pbTag = (PUCHAR)tag;
    info.cbTag = 16;
    ok = BCRYPT_SUCCESS(BCryptDecrypt(k, (PUCHAR)text, (ULONG)tn, &info, NULL, 0, out, (ULONG)tn, &got, 0));
  }
  if (k) BCryptDestroyKey(k);
  if (alg) BCryptCloseAlgorithmProvider(alg, 0);
  if (!ok) {
    if (out) SecureZeroMemory(out, tn), free(out);
    return NULL;
  }
  out[got] = 0;
  *out_n = got;
  return out;
}

// A key as that app's file is named (secure.ts fileName): letters, digits, `-` and `_` as they are, the rest %XX.
static void es_name(const char *key, WCHAR *out, size_t cap) {
  size_t k = 0;
  for (const unsigned char *p = (const unsigned char *)key; *p && k + 4 < cap; p++) {
    unsigned char c = *p;
    if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-') out[k++] = c;
    else k += (size_t)_snwprintf(out + k, cap - k, L"%%%02X", c);
  }
  out[k] = 0;
}

// What that app kept under `key` (`user` as it was kept: a file kept with the other is none), from its userData
// `userdata`: 1 and the value (malloc'd), 0 none (no such file, or it does not open: another user's, cut short)
static int electron_sealed_get(const WCHAR *userdata, const char *key, int user, uint8_t **value, size_t *len) {
  WCHAR name[1024], path[MAX_PATH * 4];
  es_name(key, name, 1024);
  _snwprintf(path, MAX_PATH * 4, L"%ls\\sealed\\%ls", userdata, name);
  path[MAX_PATH * 4 - 1] = 0;
  size_t n = 0;
  uint8_t *blob = es_read(path, &n);
  if (!blob) return 0;
  int got = 0;
  uint8_t k[32];
  if (n > 5 && memcmp(blob, "SFS1", 4) == 0 && blob[4] == (user ? 1 : 0) && es_key(userdata, k)) {
    size_t tn = 0;
    uint8_t *text = es_unseal(k, blob + 5, n - 5, &tn);
    SecureZeroMemory(k, sizeof k);
    // "<user>:<the value in base64url>", its user the same as the file's
    if (text && tn > 2 && text[0] == (user ? '1' : '0') && text[1] == ':') {
      *value = es_b64((const char *)text + 2, tn - 2, len, 1);
      got = *value != NULL;
    }
    if (text) SecureZeroMemory(text, tn), free(text);
  }
  free(blob);
  return got;
}
