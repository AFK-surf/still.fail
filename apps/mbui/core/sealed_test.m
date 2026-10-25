// src/host/electron_sealed.h against files made as still.fail's desktop app makes them (apps/desktop/src/secure.ts
// sealBlob over Electron's safeStorage, which is Chromium's OSCrypt: made here once with Node's crypto, PBKDF2-SHA1,
// "saltysalt", 1003 rounds, AES-128-CBC, an IV of spaces). Built and run by `scripts/core.sh sealed`. Exit 0 when each
// file opens to its value asked with its own `user`, and to nothing asked with the other one, with its outer `user`
// byte changed, or with a wrong password.
#import <Foundation/Foundation.h>
#include "electron_sealed.h"

static NSData *hex(const char *s) {
  NSMutableData *d = [NSMutableData data];
  for (size_t i = 0; s[i] && s[i + 1]; i += 2) {
    unsigned v;
    sscanf(s + i, "%2x", &v);
    uint8_t c = (uint8_t)v;
    [d appendBytes:&c length:1];
  }
  return d;
}

int main(void) {
  @autoreleasepool {
    NSData *password = [@"cGFzc3dvcmQtZm9yLXRlc3Q=" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *file = hex("534653310076313095f3ab3ac370a692be22e6b09c1fcd9cb1ace3de2db8781f85792464a7c8a7ed");
    NSData *user = hex("53465331017631308549c374708465f7360f9796aa69c4de7277796a3beabdd4fbfc8940cab9f6ec");
    NSData *value = hex("61206b6579206f662074686520636f7265c3a9");
    int bad = 0;
    if (![electron_sealed_open(file, password, NO) isEqualToData:value]) {
      printf("sealed: the file did not open to its value\n");
      bad = 1;
    }
    if (![electron_sealed_open(user, password, YES) isEqualToData:value]) {
      printf("sealed: the `user` file did not open to its value\n");
      bad = 1;
    }
    if (electron_sealed_open(user, password, NO) || electron_sealed_open(file, password, YES)) {
      printf("sealed: a file was opened asked with the other `user`\n");
      bad = 1;
    }
    NSMutableData *changed = [file mutableCopy];
    ((uint8_t *)changed.mutableBytes)[4] = 1;
    if (electron_sealed_open(changed, password, YES)) {
      printf("sealed: a file whose outer `user` byte was changed was opened\n");
      bad = 1;
    }
    if (electron_sealed_open(file, [@"another" dataUsingEncoding:NSUTF8StringEncoding], NO)) {
      printf("sealed: opened with another password\n");
      bad = 1;
    }
    if (![electron_sealed_name(@"vault-box") isEqualToString:@"vault-box"] ||
        ![electron_sealed_name(@"a b/é") isEqualToString:@"a%20b%2F%C3%A9"]) {
      printf("sealed: a key's file name is not secure.ts's\n");
      bad = 1;
    }
    if (!bad) printf("sealed: opened as Electron's safeStorage sealed it\n");
    return bad;
  }
}
