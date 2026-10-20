// listen.* in the core's engine (src/host/apple_core.mm on src/host/apple_listen.m), with core/listen-test.js in the
// core's place: it opens a listener, takes one request and answers it, then closes; this program is the browser.
// Built and run by `scripts/core.sh listen`.
//   listen_test <data dir>        (MB_CORE_BUNDLE: core/listen-test.js)
// Exit 0 when: the listener came up on a port of the system's choosing and a second one on that port was refused, as
// was one off loopback; a POST with a query and a body came to the script whole; the script's answer (its status,
// its headers, its body) came back here; and a listen.next waiting as the listener closed, and one after, said {end}.
#import <Foundation/Foundation.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#include "core_api.h"

static dispatch_semaphore_t done;
static int failures;
static NSString *answer;

static void check(BOOL ok, NSString *what) {
  printf("%s %s\n", ok ? "ok  " : "FAIL", what.UTF8String);
  fflush(stdout);
  if (!ok) failures++;
}

// One request to 127.0.0.1:port, as a browser sends it, and the whole answer (the connection closes after it).
static NSString *ask(int port, NSString *request) {
  int s = socket(AF_INET, SOCK_STREAM, 0);
  struct sockaddr_in a = {.sin_len = sizeof a, .sin_family = AF_INET, .sin_port = htons((uint16_t)port)};
  a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  struct timeval t = {10, 0};
  setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &t, sizeof t);
  if (connect(s, (struct sockaddr *)&a, sizeof a) != 0) {
    close(s);
    return nil;
  }
  NSData *d = [request dataUsingEncoding:NSUTF8StringEncoding];
  write(s, d.bytes, d.length);
  NSMutableData *got = [NSMutableData data];
  uint8_t buf[4096];
  ssize_t n;
  while ((n = read(s, buf, sizeof buf)) > 0) [got appendBytes:buf length:(NSUInteger)n];
  close(s);
  return [[NSString alloc] initWithData:got encoding:NSUTF8StringEncoding];
}

static void on_message(const char *json, size_t len, const uint8_t *bytes, size_t blen, void *ctx) {
  NSData *d = [NSData dataWithBytes:json length:len];
  printf("<- %.*s\n", (int)len, json);
  fflush(stdout);
  NSDictionary *m = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
  if (m[@"fatal"] || m[@"failed"]) {
    check(NO, [NSString stringWithFormat:@"the script ran: %@", m[@"fatal"] ?: m[@"failed"]]);
    dispatch_semaphore_signal(done);
  } else if (m[@"opened"]) {
    int port = [m[@"opened"] intValue];
    check(port > 0, @"listen.open on port 0 gave a port");
    check([m[@"taken"] isKindOfClass:NSString.class] && [m[@"taken"] containsString:@"in use"], [NSString stringWithFormat:@"a second listener on that port refused (%@)", m[@"taken"]]);
    check([m[@"outside"] isKindOfClass:NSString.class], [NSString stringWithFormat:@"a listener off loopback refused (%@)", m[@"outside"]]);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      answer = ask(port, [NSString stringWithFormat:@"POST /oauth/callback?code=c%%20d&state=s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: 11\r\n\r\nstate=s&x=1", port]);
    });
  } else if (m[@"asked"]) {
    NSDictionary *a = m[@"asked"];
    check([a[@"method"] isEqual:@"POST"] && [a[@"path"] isEqual:@"/oauth/callback?code=c%20d&state=s"], @"the request's method and path came whole");
    BOOL host = NO;
    for (NSArray *h in a[@"headers"])
      if ([h[0] isEqual:@"Host"] && [h[1] hasPrefix:@"127.0.0.1:"]) host = YES;
    check(host, @"its headers came, in their case");
    check([m[@"body"] isEqual:@"state=s&x=1"], @"its body came as bytes");
    check([a[@"request"] intValue] == 1, @"it is request 1");
  } else if (m[@"ended"]) {
    check([m[@"ended"][@"end"] isEqual:@YES], @"a listen.next waiting as the listener closed said end");
    check([m[@"after"][@"end"] isEqual:@YES], @"a listen.next after the close said end");
    dispatch_semaphore_signal(done);
  }
}

int main(int argc, char **argv) {
  @autoreleasepool {
    if (argc < 2) {
      fprintf(stderr, "usage: listen_test <data dir>\n");
      return 2;
    }
    done = dispatch_semaphore_create(0);
    mb_core_start(argv[1], "https://example.invalid", 0, on_message, NULL);
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC))) check(NO, @"the script finished in 20 s");
    for (int i = 0; i < 100 && !answer; i++) usleep(50000);
    check([answer hasPrefix:@"HTTP/1.1 200 OK\r\n"], @"the answer's status came back");
    check([answer containsString:@"\r\nX-Test: yes\r\n"] && [answer containsString:@"\r\nContent-Type: text/plain\r\n"], @"its headers came back");
    check([answer containsString:@"\r\nContent-Length: 43\r\n"] && ![answer containsString:@"Content-Length: 1\r\n"], @"its length is the body's own");
    check([answer hasSuffix:@"\r\n\r\nanswered /oauth/callback?code=c%20d&state=s"], @"its body came back");
    mb_core_stop();
    printf("result %s\n", failures ? "FAILED" : "OK");
    return failures ? 1 : 0;
  }
}
