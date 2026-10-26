// src/host/win_electron_sealed.h: what still.fail's desktop app kept sealed on Windows, opened by the app built in its
// place. Built and run by `scripts/win.sh sealed` (mbui.yml's windows job). A userData made here as Electron's
// safeStorage leaves one (its key sealed by DPAPI in Local State as os_crypt.encrypted_key, a value sealed by it in
// sealed\<its name>: "SFS1", the user byte, "v10", the nonce, AES-256-GCM's text and tag of "<user>:<base64url>"); exit 0
// when the value comes back, one kept with the other `user` and a key that is not there are none, and a file whose tag
// was changed does not open.
#include "win_electron_sealed.h"

static int seal_v10(const uint8_t key[32], const char *text, uint8_t *out, size_t *n) {
  BCRYPT_ALG_HANDLE alg = NULL;
  BCRYPT_KEY_HANDLE k = NULL;
  uint8_t nonce[12], tag[16];
  BCryptGenRandom(NULL, nonce, 12, BCRYPT_USE_SYSTEM_PREFERRED_RNG);
  size_t tn = strlen(text);
  ULONG got = 0;
  int ok = BCRYPT_SUCCESS(BCryptOpenAlgorithmProvider(&alg, BCRYPT_AES_ALGORITHM, NULL, 0)) &&
           BCRYPT_SUCCESS(BCryptSetProperty(alg, BCRYPT_CHAINING_MODE, (PUCHAR)BCRYPT_CHAIN_MODE_GCM,
                                            (ULONG)sizeof BCRYPT_CHAIN_MODE_GCM, 0)) &&
           BCRYPT_SUCCESS(BCryptGenerateSymmetricKey(alg, &k, NULL, 0, (PUCHAR)key, 32, 0));
  BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO info;
  BCRYPT_INIT_AUTH_MODE_INFO(info);
  info.pbNonce = nonce;
  info.cbNonce = 12;
  info.pbTag = tag;
  info.cbTag = 16;
  memcpy(out, "v10", 3);
  memcpy(out + 3, nonce, 12);
  ok = ok && BCRYPT_SUCCESS(BCryptEncrypt(k, (PUCHAR)text, (ULONG)tn, &info, NULL, 0, out + 15, (ULONG)tn, &got, 0));
  memcpy(out + 15 + got, tag, 16);
  *n = 15 + got + 16;
  if (k) BCryptDestroyKey(k);
  if (alg) BCryptCloseAlgorithmProvider(alg, 0);
  return ok;
}

static int put(const WCHAR *path, const void *b, size_t n) {
  HANDLE f = CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
  if (f == INVALID_HANDLE_VALUE) return 0;
  DWORD w = 0;
  BOOL ok = WriteFile(f, b, (DWORD)n, &w, NULL) && w == n;
  CloseHandle(f);
  return ok;
}

int main(void) {
  WCHAR dir[MAX_PATH], path[MAX_PATH * 2];
  GetTempPathW(MAX_PATH, dir);
  wcscat_s(dir, MAX_PATH, L"sealed-test-userdata");
  CreateDirectoryW(dir, NULL);
  _snwprintf(path, MAX_PATH * 2, L"%ls\\sealed", dir);
  CreateDirectoryW(path, NULL);
  // its key, sealed by DPAPI, in Local State as Chromium keeps it
  uint8_t key[32];
  BCryptGenRandom(NULL, key, 32, BCRYPT_USE_SYSTEM_PREFERRED_RNG);
  DATA_BLOB in = {32, key}, sealed = {0};
  if (!CryptProtectData(&in, NULL, NULL, NULL, NULL, CRYPTPROTECT_UI_FORBIDDEN, &sealed)) {
    printf("sealed: DPAPI sealed nothing\n");
    return 1;
  }
  uint8_t *dp = (uint8_t *)malloc(5 + sealed.cbData);
  memcpy(dp, "DPAPI", 5);
  memcpy(dp + 5, sealed.pbData, sealed.cbData);
  DWORD b64n = 0;
  CryptBinaryToStringA(dp, 5 + sealed.cbData, CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, NULL, &b64n);
  char *b64 = (char *)malloc(b64n);
  CryptBinaryToStringA(dp, 5 + sealed.cbData, CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, b64, &b64n);
  char *state = (char *)malloc(b64n + 200);
  int sn = snprintf(state, b64n + 200, "{\"browser\":{},\"os_crypt\":{\"audit_enabled\":true,\"encrypted_key\":\"%s\"}}", b64);
  _snwprintf(path, MAX_PATH * 2, L"%ls\\Local State", dir);
  put(path, state, (size_t)sn);
  // a value: the vault's key, kept as a person's (user 1), its bytes 0..19 as base64url
  const char *text = "1:AAECAwQFBgcICQoLDA0ODxAREhM";
  uint8_t blob[256];
  size_t n = 0;
  memcpy(blob, "SFS1\x01", 5);
  if (!seal_v10(key, text, blob + 5, &n)) {
    printf("sealed: AES-GCM sealed nothing\n");
    return 1;
  }
  _snwprintf(path, MAX_PATH * 2, L"%ls\\sealed\\vault%%3Aws1", dir);
  put(path, blob, 5 + n);
  int bad = 0;
  uint8_t *value = NULL;
  size_t len = 0;
  int got = electron_sealed_get(dir, "vault:ws1", 1, &value, &len);
  int same = got && len == 20;
  for (size_t i = 0; same && i < len; i++) same = value[i] == i;
  if (!same) printf("sealed: the value did not come back (%d, %zu bytes)\n", got, len), bad = 1;
  free(value);
  value = NULL;
  if (electron_sealed_get(dir, "vault:ws1", 0, &value, &len)) printf("sealed: asked as not the person's, it opened\n"), bad = 1;
  if (electron_sealed_get(dir, "vault:none", 1, &value, &len)) printf("sealed: a key not there came\n"), bad = 1;
  // its tag changed: it does not open
  blob[5 + n - 1] ^= 1;
  _snwprintf(path, MAX_PATH * 2, L"%ls\\sealed\\vault%%3Aws1", dir);
  put(path, blob, 5 + n);
  if (electron_sealed_get(dir, "vault:ws1", 1, &value, &len)) printf("sealed: a changed file opened\n"), bad = 1;
  if (!bad) printf("sealed: the desktop app's sealed value opened, and only as it was kept\n");
  return bad;
}
