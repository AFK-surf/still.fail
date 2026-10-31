// A sign-in in the browser that comes back to this machine, for the macOS and iOS hosts (host_native.mbt
// `browser_login`), on the loopback listener of apple_listen.m.
//
// The way command-line tools sign in (OAuth's loopback redirect, RFC 8252 §7.3): listen on 127.0.0.1 at a port the
// system picks, let the app make its login page with http://127.0.0.1:<port><path> as where to come back, open it in
// the browser, take the one GET that comes back to <path> under that host name, answer it, stop listening. Nothing here
// knows whose sign-in it is: the app checks what came back (its state) and exchanges it. Opening is $BROWSER, else
// `open` on macOS (a station's remote login sets the one and stands in for the other: ember docs/remote-login.md),
// the system on iOS. The app polls it each frame (a frame is asked for when the browser comes back).
#import <Foundation/Foundation.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#include <spawn.h>
extern char **environ;
#endif
#import "apple.h"
#include "listen_api.h"

void mb_host_request_frame(void);

@interface MBBrowserLogin : NSObject
@property(nonatomic) int lid, port;
@property(nonatomic, copy) NSString *path;
/// Where the browser is sent on to once it has come back (the app's page saying it is done): none, this host's page.
@property(nonatomic, copy) NSString *done;
/// Where the browser came back to (http://127.0.0.1:<port><path>?<query>), once it has.
@property(nonatomic, copy) NSString *back;
@end

@implementation MBBrowserLogin
@end

// By id, under its own lock: the listener's queue reads it too. `back` is the main thread's.
static NSMutableDictionary<NSNumber *, MBBrowserLogin *> *browser_logins;
static int browser_login_next;

static NSData *browser_page(NSString *title, NSString *text) {
  NSString *html = [NSString stringWithFormat:@"<!doctype html><meta charset=utf-8><meta name=viewport content=\"width=device-width\">"
                                              @"<title>%@</title><body style=\"font:16px -apple-system,system-ui,sans-serif;margin:3em 2em;color:#1c1c1e\"><p>%@</p></body>",
                                              title, text];
  return [html dataUsingEncoding:NSUTF8StringEncoding];
}

// On the listener's queue: the request that came, answered at once (only the one this sign-in waits for is taken).
static void browser_login_took(void *ctx, const char *json, size_t len, const uint8_t *body, size_t blen) {
  if (!json) return;
  int bid = (int)(intptr_t)ctx;
  NSDictionary *r = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:json length:len] options:0 error:nil];
  MBBrowserLogin *login = nil;
  @synchronized(browser_logins) {
    login = browser_logins[@(bid)];
  }
  if (!login || ![r isKindOfClass:NSDictionary.class]) return;
  NSString *path = [r[@"path"] isKindOfClass:NSString.class] ? r[@"path"] : @"";
  NSRange q = [path rangeOfString:@"?"];
  NSString *bare = q.location == NSNotFound ? path : [path substringToIndex:q.location];
  NSString *host = @"";
  for (NSArray *h in r[@"headers"])
    if ([h[0] caseInsensitiveCompare:@"host"] == NSOrderedSame) host = h[1];
  // Only the browser coming back to this sign-in: its address (a page elsewhere naming 127.0.0.1 by another name,
  // DNS rebinding, is not), its path, a GET.
  BOOL ours = ([host isEqualToString:[NSString stringWithFormat:@"127.0.0.1:%d", login.port]] ||
               [host isEqualToString:[NSString stringWithFormat:@"localhost:%d", login.port]]) &&
              [r[@"method"] isEqual:@"GET"] && [bare isEqualToString:login.path];
  long request = [r[@"request"] longValue];
  if (ours && login.done.length) {
    // on to the app's page saying it is done (in its look, the browser's language)
    const char *headers[] = {"Location", login.done.UTF8String, "Cache-Control", "no-store"};
    mb_listen_respond(login.lid, request, 302, headers, 2, NULL, 0);
  } else {
    const char *headers[] = {"Content-Type", "text/html; charset=utf-8", "Cache-Control", "no-store"};
    NSData *page = ours ? browser_page(@"Signed in", @"已回到 app，可以关掉这个页面 · Back in the app: you can close this page")
                        : browser_page(@"Not found", @"这不是这次登录的地址 · Not this sign-in");
    mb_listen_respond(login.lid, request, ours ? 200 : 404, headers, 2, page.bytes, page.length);
  }
  if (!ours) return;
  // After the answer (the same queue): nothing else is taken.
  mb_listen_close(login.lid);
  NSString *back = [NSString stringWithFormat:@"http://127.0.0.1:%d%@", login.port, path];
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!login.back) login.back = back;
#if !TARGET_OS_IPHONE
    // the app in front again, over the browser (as the desktop app comes back from its sign-in)
    [NSApp activateIgnoringOtherApps:YES];
#endif
    mb_host_request_frame();
  });
}

int32_t mb_host_browser_login_start(moonbit_string_t path, moonbit_string_t done) {
  if (!browser_logins) browser_logins = [NSMutableDictionary dictionary];
  MBBrowserLogin *login = [MBBrowserLogin new];
  login.path = mb_ns_from_string(path);
  login.done = mb_ns_from_string(done);
  int bid = ++browser_login_next;
  @synchronized(browser_logins) {
    browser_logins[@(bid)] = login;
  }
  char why[160];
  int port = 0;
  int lid = mb_listen_open("127.0.0.1", 0, browser_login_took, (void *)(intptr_t)bid, &port, why, sizeof why);
  if (!lid) {
    @synchronized(browser_logins) {
      [browser_logins removeObjectForKey:@(bid)];
    }
    return 0;
  }
  // Set before any request can come: one comes only once the browser has the page, which the port is needed for.
  login.lid = lid;
  login.port = port;
  return bid;
}

int32_t mb_host_browser_login_port(int32_t bid) {
  @synchronized(browser_logins) {
    return browser_logins[@(bid)].port;
  }
}

int32_t mb_host_browser_login_open(int32_t bid, moonbit_string_t url) {
  NSString *u = mb_ns_from_string(url);
#if TARGET_OS_IPHONE
  NSURL *link = [NSURL URLWithString:u];
  if (!link) return 0;
  [UIApplication.sharedApplication openURL:link options:@{} completionHandler:nil];
  return 1;
#else
  const char *browser = getenv("BROWSER");
  NSString *program = browser && *browser ? [@(browser) componentsSeparatedByString:@":"].firstObject : @"open";
  if (program.length == 0) program = @"open";
  char *argv[] = {(char *)program.UTF8String, (char *)u.UTF8String, NULL};
  pid_t pid;
  // Not waited for: `open` returns at once; a browser started directly keeps running after us.
  return posix_spawnp(&pid, argv[0], NULL, NULL, argv, environ) == 0;
#endif
}

moonbit_string_t mb_host_browser_login_back(int32_t bid) {
  MBBrowserLogin *login;
  @synchronized(browser_logins) {
    login = browser_logins[@(bid)];
  }
  return mb_string_from_ns(login.back ?: @"");
}

void mb_host_browser_login_end(int32_t bid) {
  MBBrowserLogin *login;
  @synchronized(browser_logins) {
    login = browser_logins[@(bid)];
    [browser_logins removeObjectForKey:@(bid)];
  }
  if (login) mb_listen_close(login.lid);
}
