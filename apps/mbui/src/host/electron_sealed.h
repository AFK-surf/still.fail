// What still.fail's desktop app (Electron's, apps/desktop/src/secure.ts) kept sealed, opened for the app built in its
// place (scripts/mac-app.sh's stable and beta: its id, its data). apple_core.mm's secure.get takes a key from it the
// first time the core asks for one the Keychain does not have, and seals it there again, as Android's CoreHost does
// the Kotlin app's. A file of that app's userData/sealed: "SFS1", the `user` byte (1: Touch ID's, not opened here),
// then Electron's safeStorage sealing of "<user>:<the value in base64url>": Chromium's OSCrypt on macOS ("v10", then
// AES-128-CBC with PKCS #7 under PBKDF2-HMAC-SHA1 of the password safeStorage keeps in the Keychain, salt
// "saltysalt", 1003 rounds, 16 bytes; an IV of 16 spaces). Included by apple_core.mm and core/sealed_test.m.
#pragma once
#import <Foundation/Foundation.h>
#include <CommonCrypto/CommonCrypto.h>

// A key as Electron's file is named (secure.ts fileName): letters, digits, `-` and `_` as they are, the rest %XX.
static NSString *electron_sealed_name(NSString *key) {
  NSData *k = [key dataUsingEncoding:NSUTF8StringEncoding];
  const uint8_t *b = (const uint8_t *)k.bytes;
  NSMutableString *name = [NSMutableString string];
  for (NSUInteger i = 0; i < k.length; i++) {
    uint8_t c = b[i];
    BOOL plain = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-';
    if (plain) [name appendFormat:@"%c", c];
    else [name appendFormat:@"%%%02X", c];
  }
  return name;
}

// A file's value, opened with safeStorage's password: nil when it is no such file, one kept with `user`, or it does not
// open (another password, a file cut short).
static NSData *electron_sealed_open(NSData *blob, NSData *password) {
  const uint8_t *b = (const uint8_t *)blob.bytes;
  if (blob.length < 5 + 3 + kCCBlockSizeAES128 || memcmp(b, "SFS1", 4) != 0 || b[4] != 0) return nil;
  const uint8_t *sealed = b + 5;
  size_t n = blob.length - 5;
  if (memcmp(sealed, "v10", 3) != 0) return nil;
  uint8_t key[kCCKeySizeAES128];
  if (CCKeyDerivationPBKDF(kCCPBKDF2, (const char *)password.bytes, password.length, (const uint8_t *)"saltysalt", 9,
                           kCCPRFHmacAlgSHA1, 1003, key, sizeof key) != kCCSuccess)
    return nil;
  uint8_t iv[kCCBlockSizeAES128];
  memset(iv, ' ', sizeof iv);
  NSMutableData *plain = [NSMutableData dataWithLength:n];
  size_t got = 0;
  if (CCCrypt(kCCDecrypt, kCCAlgorithmAES128, kCCOptionPKCS7Padding, key, sizeof key, iv, sealed + 3, n - 3,
              plain.mutableBytes, plain.length, &got) != kCCSuccess)
    return nil;
  plain.length = got;
  NSString *s = [[NSString alloc] initWithData:plain encoding:NSUTF8StringEncoding];
  if (![s hasPrefix:@"0:"]) return nil;
  // base64url, unpadded: as base64
  NSMutableString *b64 = [[[s substringFromIndex:2] stringByReplacingOccurrencesOfString:@"-" withString:@"+"]
      mutableCopy];
  [b64 replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, b64.length)];
  while (b64.length % 4) [b64 appendString:@"="];
  return [[NSData alloc] initWithBase64EncodedString:b64 options:0];
}
