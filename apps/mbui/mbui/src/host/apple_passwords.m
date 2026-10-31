// This device's password manager for the macOS host (host_native.mbt `pw_*`, hostapi/passwords.mbt): 1Password's
// command-line tool `op`, run without a window with the arguments the app gives (never through a shell), its output
// kept until the app takes it. `op` signed in through 1Password's desktop app asks the person itself (Touch ID, in its
// own window). Found where Homebrew and 1Password's installer put it, else on PATH. None on iOS.
#import <Foundation/Foundation.h>
#if !TARGET_OS_IPHONE
#import <AppKit/AppKit.h>
#import <AuthenticationServices/AuthenticationServices.h>
#include <dlfcn.h>
#endif
#import "apple.h"

void mb_host_request_frame(void);

#if TARGET_OS_IPHONE

int32_t mb_host_passwords_able(void) { return 0; }
int32_t mb_host_passwords_run(moonbit_string_t args) { (void)args; return 0; }
moonbit_string_t mb_host_passwords_out(int32_t id) { (void)id; return mb_string_from_ns(@""); }
void mb_host_passwords_end(int32_t id) { (void)id; }

// This device's passkeys (host_native.mbt `wa_*`): none on iOS yet.
int32_t mb_host_passkeys_able(void) { return 0; }
int32_t mb_host_passkeys_get(moonbit_string_t ask) { (void)ask; return 0; }
moonbit_string_t mb_host_passkeys_out(int32_t id) { (void)id; return mb_string_from_ns(@""); }
void mb_host_passkeys_end(int32_t id) { (void)id; }

#else

/// The runs, by id, under their own lock: a run's end is heard on another thread.
static NSMutableDictionary<NSNumber *, NSMutableDictionary *> *runs;
static int run_next;

/// Where `op` is: Homebrew's (Apple silicon, Intel), 1Password's own installer's, else the first on PATH.
static NSString *op_path(void) {
  NSMutableArray<NSString *> *places = [@[ @"/opt/homebrew/bin/op", @"/usr/local/bin/op", @"/usr/bin/op" ] mutableCopy];
  NSString *path = NSProcessInfo.processInfo.environment[@"PATH"] ?: @"";
  for (NSString *dir in [path componentsSeparatedByString:@":"])
    if (dir.length) [places addObject:[dir stringByAppendingPathComponent:@"op"]];
  for (NSString *p in places)
    if ([NSFileManager.defaultManager isExecutableFileAtPath:p]) return p;
  return nil;
}

int32_t mb_host_passwords_able(void) { return 1; }

int32_t mb_host_passwords_run(moonbit_string_t args) {
  // One argument after another, each ended by a unit separator (U+001F).
  NSMutableArray<NSString *> *argv = [[mb_ns_from_string(args) componentsSeparatedByString:@"\x1f"] mutableCopy];
  [argv removeLastObject];
  if (!runs) runs = [NSMutableDictionary dictionary];
  int id;
  NSMutableDictionary *run = [NSMutableDictionary dictionary];
  @synchronized(runs) {
    id = ++run_next;
    runs[@(id)] = run;
  }
  NSString *op = op_path();
  if (!op) {
    @synchronized(runs) {
      run[@"done"] = @{@"code" : @(-1), @"out" : @"", @"err" : @"op not found"};
    }
    mb_host_request_frame();
    return id;
  }
  NSTask *t = [NSTask new];
  t.executableURL = [NSURL fileURLWithPath:op];
  t.arguments = argv;
  NSPipe *out = [NSPipe pipe], *err = [NSPipe pipe];
  t.standardOutput = out;
  t.standardError = err;
  t.standardInput = [NSFileHandle fileHandleWithNullDevice];
  // Read as it comes (a pipe that fills up holds the process), handed over as it ends.
  NSMutableData *said = [NSMutableData data], *errs = [NSMutableData data];
  out.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
    NSData *d = h.availableData;
    @synchronized(said) {
      [said appendData:d];
    }
  };
  err.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
    NSData *d = h.availableData;
    @synchronized(errs) {
      [errs appendData:d];
    }
  };
  t.terminationHandler = ^(NSTask *task) {
    out.fileHandleForReading.readabilityHandler = nil;
    err.fileHandleForReading.readabilityHandler = nil;
    NSData *rest = [out.fileHandleForReading readDataToEndOfFile], *restErr = [err.fileHandleForReading readDataToEndOfFile];
    NSString *o, *e;
    @synchronized(said) {
      [said appendData:rest];
      o = [[NSString alloc] initWithData:said encoding:NSUTF8StringEncoding] ?: @"";
    }
    @synchronized(errs) {
      [errs appendData:restErr];
      e = [[NSString alloc] initWithData:errs encoding:NSUTF8StringEncoding] ?: @"";
    }
    @synchronized(runs) {
      run[@"done"] = @{@"code" : @(task.terminationStatus), @"out" : o, @"err" : e};
      [run removeObjectForKey:@"task"];
    }
    mb_host_request_frame();
  };
  NSError *why = nil;
  if (![t launchAndReturnError:&why]) {
    @synchronized(runs) {
      run[@"done"] = @{@"code" : @(-1), @"out" : @"", @"err" : why.localizedDescription ?: @"op did not start"};
    }
    mb_host_request_frame();
    return id;
  }
  @synchronized(runs) {
    if (!run[@"done"]) run[@"task"] = t;
  }
  return id;
}

// How it ended, once it has: its exit code, its output and its error output, each ended by a unit separator; "" before.
moonbit_string_t mb_host_passwords_out(int32_t id) {
  NSDictionary *done = nil;
  @synchronized(runs) {
    done = runs[@(id)][@"done"];
  }
  if (!done) return mb_string_from_ns(@"");
  return mb_string_from_ns([NSString stringWithFormat:@"%@\x1f%@\x1f%@\x1f", done[@"code"], done[@"out"], done[@"err"]]);
}

void mb_host_passwords_end(int32_t id) {
  NSTask *t = nil;
  @synchronized(runs) {
    t = runs[@(id)][@"task"];
    [runs removeObjectForKey:@(id)];
  }
  if (t.running) [t terminate];
}


// This device's passkeys for the macOS host (host_native.mbt `wa_*`, hostapi/passkeys.mbt): AuthenticationServices as a
// browser asks it (ASAuthorizationWebBrowserPublicKeyCredentialManager, a platform passkey's or a security key's
// assertion for any relying party with the client data given), which macOS lets only an app entitled
// com.apple.developer.web-browser.public-key-credential do: without it there are none here. macOS asks the person
// itself (Touch ID, a phone, a key, a provider such as 1Password) in its own sheet over the app's window, and makes
// the client data JSON itself of the challenge and the origin given: it comes back with the signature. The framework
// is found as the app runs (an app of mbui's own may link none of it).

/// Whether this app may ask for any site's passkeys (its entitlement), once.
static BOOL passkeys_entitled(void) {
  static int known = -1;
  if (known >= 0) return known;
  known = 0;
  void *sec = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY);
  void *(*create)(CFAllocatorRef) = sec ? dlsym(sec, "SecTaskCreateFromSelf") : NULL;
  CFTypeRef (*value)(void *, CFStringRef, CFErrorRef *) = sec ? dlsym(sec, "SecTaskCopyValueForEntitlement") : NULL;
  if (!create || !value) return known;
  void *task = create(NULL);
  if (!task) return known;
  CFTypeRef v = value(task, CFSTR("com.apple.developer.web-browser.public-key-credential"), NULL);
  if (v) {
    known = CFGetTypeID(v) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)v);
    CFRelease(v);
  }
  CFRelease(task);
  if (known && ![[NSBundle bundleWithPath:@"/System/Library/Frameworks/AuthenticationServices.framework"] load]) known = 0;
  if (known && !NSClassFromString(@"ASAuthorizationWebBrowserPublicKeyCredentialManager")) known = 0;
  return known;
}

static NSMutableDictionary<NSNumber *, NSMutableDictionary *> *asks;
static int ask_next;

static NSString *hex_of(NSData *d) {
  NSMutableString *s = [NSMutableString stringWithCapacity:d.length * 2];
  const unsigned char *b = d.bytes;
  for (NSUInteger i = 0; i < d.length; i++) [s appendFormat:@"%02x", b[i]];
  return s;
}

static NSData *data_of_hex(NSString *h) {
  NSMutableData *d = [NSMutableData dataWithCapacity:h.length / 2];
  for (NSUInteger i = 0; i + 1 < h.length; i += 2) {
    unsigned v = 0;
    if (sscanf([h substringWithRange:NSMakeRange(i, 2)].UTF8String, "%2x", &v) != 1) return nil;
    unsigned char c = (unsigned char)v;
    [d appendBytes:&c length:1];
  }
  return d;
}

static NSData *data_of_b64url(NSString *s) {
  NSMutableString *t = [[[s stringByReplacingOccurrencesOfString:@"-" withString:@"+"] stringByReplacingOccurrencesOfString:@"_" withString:@"/"] mutableCopy];
  while (t.length % 4) [t appendString:@"="];
  return [[NSData alloc] initWithBase64EncodedString:t options:0];
}

static void ask_done(int id, NSString *done) {
  @synchronized(asks) {
    NSMutableDictionary *a = asks[@(id)];
    if (a && !a[@"done"]) a[@"done"] = done;
  }
  mb_host_request_frame();
}

/// One ask's delegate and window: the controller holds it weakly, so the ask's own entry keeps it.
API_AVAILABLE(macos(14.0))
@interface MBPasskeyAsk : NSObject <ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding>
@property int ident;
@property(strong) id controller;
@end

@implementation MBPasskeyAsk
- (void)authorizationController:(ASAuthorizationController *)controller didCompleteWithAuthorization:(ASAuthorization *)authorization {
  id c = authorization.credential;
  if (![c respondsToSelector:@selector(rawAuthenticatorData)] || ![c respondsToSelector:@selector(signature)]) {
    ask_done(self.ident, @"-1\x1f\x1f\x1f\x1f\x1fno assertion\x1f\x1f");
    return;
  }
  NSData *user = [c respondsToSelector:@selector(userID)] ? [c userID] : nil;
  NSData *client = [c respondsToSelector:@selector(rawClientDataJSON)] ? [c rawClientDataJSON] : nil;
  ask_done(self.ident, [NSString stringWithFormat:@"0\x1f%@\x1f%@\x1f%@\x1f%@\x1f\x1f%@\x1f", hex_of([c credentialID]), hex_of([c rawAuthenticatorData]),
                                                  hex_of([c signature]), user ? hex_of(user) : @"", client ? hex_of(client) : @""]);
}

- (void)authorizationController:(ASAuthorizationController *)controller didCompleteWithError:(NSError *)error {
  // canceled (1001) or none of the site's here: as a browser says it; else why
  BOOL no = [error.domain isEqualToString:@"com.apple.AuthenticationServices.AuthorizationError"] && (error.code == 1001 || error.code == 1004 || error.code == 1006);
  NSString *why = [error.localizedDescription stringByReplacingOccurrencesOfString:@"\x1f" withString:@" "] ?: @"";
  ask_done(self.ident, [NSString stringWithFormat:@"%d\x1f\x1f\x1f\x1f\x1f%@\x1f\x1f", no ? 1 : -1, why]);
}

- (ASPresentationAnchor)presentationAnchorForAuthorizationController:(ASAuthorizationController *)controller {
  return NSApp.keyWindow ?: NSApp.mainWindow ?: NSApp.windows.firstObject;
}
@end

int32_t mb_host_passkeys_able(void) {
  if (@available(macOS 14.0, *)) return passkeys_entitled() ? 1 : 0;
  return 0;
}

/// `ask`: the relying party, the client data (JSON: its challenge and origin are what macOS makes its own of), the
/// verification and the credential ids (hex, joined by commas), each ended by a unit separator, as
/// hostapi/passkeys.mbt gives them.
API_AVAILABLE(macos(14.0)) static int32_t passkeys_get(NSString *ask) {
  if (!passkeys_entitled()) return 0;
  NSArray<NSString *> *parts = [ask componentsSeparatedByString:@"\x1f"];
  if (parts.count < 4) return 0;
  NSString *rp = parts[0], *uv = parts[2];
  NSDictionary *client = [NSJSONSerialization JSONObjectWithData:[parts[1] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
  NSData *challenge = [client isKindOfClass:NSDictionary.class] && [client[@"challenge"] isKindOfClass:NSString.class] ? data_of_b64url(client[@"challenge"]) : nil;
  NSString *origin = [client isKindOfClass:NSDictionary.class] && [client[@"origin"] isKindOfClass:NSString.class] ? client[@"origin"] : nil;
  if (!challenge || !origin) return 0;
  NSMutableArray<NSData *> *ids = [NSMutableArray array];
  for (NSString *h in [parts[3] componentsSeparatedByString:@","]) {
    NSData *d = h.length ? data_of_hex(h) : nil;
    if (d.length) [ids addObject:d];
  }
  if (!asks) asks = [NSMutableDictionary dictionary];
  int ident;
  MBPasskeyAsk *who = [MBPasskeyAsk new];
  @synchronized(asks) {
    ident = ++ask_next;
    asks[@(ident)] = [@{@"who" : who} mutableCopy];
  }
  who.ident = ident;
  dispatch_async(dispatch_get_main_queue(), ^{
    id manager = [NSClassFromString(@"ASAuthorizationWebBrowserPublicKeyCredentialManager") new];
    if (!manager) return ask_done(ident, @"-1\x1f\x1f\x1f\x1f\x1fno AuthenticationServices\x1f\x1f");
    void (^go)(void) = ^{
      ASPublicKeyCredentialClientData *data = [(ASPublicKeyCredentialClientData *)[NSClassFromString(@"ASPublicKeyCredentialClientData") alloc] initWithChallenge:challenge origin:origin];
      NSString *pref = [uv isEqualToString:@"required"] ? @"required" : [uv isEqualToString:@"discouraged"] ? @"discouraged" : @"preferred";
      ASAuthorizationPlatformPublicKeyCredentialProvider *platform = [(ASAuthorizationPlatformPublicKeyCredentialProvider *)[NSClassFromString(@"ASAuthorizationPlatformPublicKeyCredentialProvider") alloc] initWithRelyingPartyIdentifier:rp];
      ASAuthorizationPlatformPublicKeyCredentialAssertionRequest *p = [platform createCredentialAssertionRequestWithClientData:data];
      ASAuthorizationSecurityKeyPublicKeyCredentialProvider *keys = [(ASAuthorizationSecurityKeyPublicKeyCredentialProvider *)[NSClassFromString(@"ASAuthorizationSecurityKeyPublicKeyCredentialProvider") alloc] initWithRelyingPartyIdentifier:rp];
      ASAuthorizationSecurityKeyPublicKeyCredentialAssertionRequest *k = [keys createCredentialAssertionRequestWithClientData:data];
      NSMutableArray *pa = [NSMutableArray array], *ka = [NSMutableArray array];
      for (NSData *d in ids) {
        [pa addObject:[(ASAuthorizationPlatformPublicKeyCredentialDescriptor *)[NSClassFromString(@"ASAuthorizationPlatformPublicKeyCredentialDescriptor") alloc] initWithCredentialID:d]];
        [ka addObject:[(ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor *)[NSClassFromString(@"ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor") alloc] initWithCredentialID:d transports:@[ @"usb", @"nfc", @"ble", @"hybrid" ]]];
      }
      [p setAllowedCredentials:pa];
      [k setAllowedCredentials:ka];
      [p setUserVerificationPreference:pref];
      [k setUserVerificationPreference:pref];
      ASAuthorizationController *c = [(ASAuthorizationController *)[NSClassFromString(@"ASAuthorizationController") alloc] initWithAuthorizationRequests:@[ p, k ]];
      c.delegate = who;
      c.presentationContextProvider = who;
      who.controller = c;
      [c performRequests];
    };
    // (the person's leave to use their passkeys in this app, asked once)
    if ([(ASAuthorizationWebBrowserPublicKeyCredentialManager *)manager authorizationStateForPlatformCredentials] == ASAuthorizationWebBrowserPublicKeyCredentialManagerAuthorizationStateAuthorized) {
      go();
    } else {
      [(ASAuthorizationWebBrowserPublicKeyCredentialManager *)manager requestAuthorizationForPublicKeyCredentials:^(ASAuthorizationWebBrowserPublicKeyCredentialManagerAuthorizationState state) {
        dispatch_async(dispatch_get_main_queue(), ^{
          if (state == ASAuthorizationWebBrowserPublicKeyCredentialManagerAuthorizationStateAuthorized) go();
          else ask_done(ident, @"1\x1f\x1f\x1f\x1f\x1fnot allowed\x1f\x1f");
        });
      }];
    }
  });
  return ident;
}

int32_t mb_host_passkeys_get(moonbit_string_t ask) {
  if (@available(macOS 14.0, *)) return passkeys_get(mb_ns_from_string(ask));
  return 0;
}

/// How it ended, once it has: its code, the credential, the authenticator data, the signature, the user handle, why,
/// and the client data macOS signed (hex), each ended by a unit separator; "" before.
moonbit_string_t mb_host_passkeys_out(int32_t id) {
  NSString *done = nil;
  @synchronized(asks) {
    done = asks[@(id)][@"done"];
  }
  return mb_string_from_ns(done ?: @"");
}

void mb_host_passkeys_end(int32_t id) {
  @synchronized(asks) {
    [asks removeObjectForKey:@(id)];
  }
}

#endif
