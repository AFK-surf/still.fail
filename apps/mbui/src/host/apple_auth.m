// A sign-in's browser page, for the iOS host (macOS's signs in on @hostapi.browser_login, in the default browser:
// ASWebAuthenticationSession is Safari's there whatever the browser chosen): ASWebAuthenticationSession opens still.fail cloud's login
// page (auth.begin's url) and gives back the URL the cloud sends the browser to on the app's scheme
// (stillfail://auth/callback?…), with no CFBundleURLTypes registration: another installed still.fail app owning the
// scheme does not take the callback from us (core/README.md, Login). The session shares the browser's cookies, so a
// person signed in to Google there is not asked again.
//
//   void mb_web_auth(const char *url, const char *scheme, void (*done)(const char *callback, const char *error, void *),
//                    void *ctx);        `done` once, on the main thread
//
// MBUI_AUTH_DRY=1: the session is made but not started, and `done` says so (what tests and scripted runs use: nobody
// signs in from them).
#import <AuthenticationServices/AuthenticationServices.h>
#import <Foundation/Foundation.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif

@interface MBAuthAnchor : NSObject <ASWebAuthenticationPresentationContextProviding>
@end

@implementation MBAuthAnchor
- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session {
#if TARGET_OS_IPHONE
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if (![scene isKindOfClass:UIWindowScene.class]) continue;
    for (UIWindow *w in ((UIWindowScene *)scene).windows) {
      if (w.isKeyWindow) return w;
    }
  }
  return UIApplication.sharedApplication.windows.firstObject;
#else
  return NSApp.keyWindow ?: NSApp.mainWindow ?: NSApp.windows.firstObject;
#endif
}
@end

// The session in flight (ASWebAuthenticationSession does not keep itself) and its anchor (a weak reference there).
static ASWebAuthenticationSession *auth_session;
static MBAuthAnchor *auth_anchor;

void mb_web_auth(const char *url, const char *scheme, void (*done)(const char *, const char *, void *), void *ctx) {
  NSURL *u = [NSURL URLWithString:@(url)];
  NSString *s = @(scheme);
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!u) {
      done(NULL, "not a URL", ctx);
      return;
    }
    if (auth_session) [auth_session cancel];
    __block int ended = 0;
    ASWebAuthenticationSession *session = [[ASWebAuthenticationSession alloc]
              initWithURL:u
        callbackURLScheme:s
        completionHandler:^(NSURL *callback, NSError *error) {
          dispatch_async(dispatch_get_main_queue(), ^{
            if (ended) return;
            ended = 1;
            auth_session = nil;
            if (callback) done(callback.absoluteString.UTF8String, NULL, ctx);
            else
              done(NULL,
                   error.code == ASWebAuthenticationSessionErrorCodeCanceledLogin ? "cancelled"
                                                                                  : (error.localizedDescription.UTF8String ?: "failed"),
                   ctx);
          });
        }];
    if (!auth_anchor) auth_anchor = [MBAuthAnchor new];
    session.presentationContextProvider = auth_anchor;
    const char *dry = getenv("MBUI_AUTH_DRY");
    if (dry && *dry && strcmp(dry, "0") != 0) {
      // The URL's state and PKCE challenge are not printed: where it goes is enough to see it would open.
      NSString *line = [NSString stringWithFormat:@"dry run: would open %@://%@%@ (callback scheme %@, can start: %@)", u.scheme, u.host, u.path,
                                                  s, session.canStart ? @"yes" : @"no"];
      fprintf(stdout, "[auth] %s\n", line.UTF8String);
      fflush(stdout);
      done(NULL, line.UTF8String, ctx);
      return;
    }
    auth_session = session;
    if (![session start]) {
      auth_session = nil;
      ended = 1;
      done(NULL, "the browser session did not start", ctx);
    }
  });
}
