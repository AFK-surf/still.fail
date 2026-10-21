// A loopback HTTP listener for the macOS and iOS hosts (listen_api.h): BSD sockets, a dispatch source for accepting,
// each request read whole on a worker (blocking, 15 s at most) and handed on from the listener's queue, as Android's
// Loopback.kt does for the core there. One serial queue keeps every listener's state and writes the answers.
#import <Foundation/Foundation.h>
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#include "listen_api.h"

/// Most of a request's head and body taken (a login's callback: a query, or a small form).
enum { LISTEN_HEAD_MOST = 64 * 1024, LISTEN_BODY_MOST = 1000000, LISTEN_READ_S = 15 };

@interface MBListener : NSObject
@property(nonatomic) int fd;
@property(nonatomic, strong) dispatch_source_t source;
@property(nonatomic) mb_listen_fn fn;
@property(nonatomic) void *ctx;
@property(nonatomic) long next;
@property(nonatomic) BOOL closed;
/// The connections whose request was handed on, by its number, until answered.
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *asked;
@end

@implementation MBListener
@end

static dispatch_queue_t listen_queue(void) {
  static dispatch_queue_t q;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    q = dispatch_queue_create("mbui.listen", DISPATCH_QUEUE_SERIAL);
  });
  return q;
}

// The listeners by id; only on listen_queue.
static NSMutableDictionary<NSNumber *, MBListener *> *listeners;
static int listen_next_id;

static void say_why(char *why, size_t len, const char *text) {
  if (why && len) snprintf(why, len, "%s", text);
}

// ── a request off a connection ──

static int read_some(int c, uint8_t *buf, size_t n) {
  for (;;) {
    ssize_t got = read(c, buf, n);
    if (got >= 0) return (int)got;
    if (errno != EINTR) return -1;
  }
}

// An HTTP/1.x request, whole: nil for what is not one, or one too slow or too big.
static NSDictionary *read_request(int c, NSData **body_out) {
  NSMutableData *buf = [NSMutableData data];
  uint8_t chunk[8192];
  NSRange end = {NSNotFound, 0};
  NSData *crlf2 = [NSData dataWithBytes:"\r\n\r\n" length:4];
  while (end.location == NSNotFound) {
    if (buf.length >= LISTEN_HEAD_MOST) return nil;
    int got = read_some(c, chunk, sizeof chunk);
    if (got <= 0) return nil;
    [buf appendBytes:chunk length:(NSUInteger)got];
    end = [buf rangeOfData:crlf2 options:0 range:NSMakeRange(0, buf.length)];
  }
  NSString *head = [[NSString alloc] initWithData:[buf subdataWithRange:NSMakeRange(0, end.location)] encoding:NSISOLatin1StringEncoding];
  NSArray<NSString *> *lines = [head componentsSeparatedByString:@"\r\n"];
  NSArray<NSString *> *first = [lines.firstObject componentsSeparatedByString:@" "];
  if (first.count != 3 || ![first[2] hasPrefix:@"HTTP/1."]) return nil;
  NSMutableArray *headers = [NSMutableArray array];
  long long length = 0;
  for (NSUInteger i = 1; i < lines.count; i++) {
    NSRange colon = [lines[i] rangeOfString:@":"];
    if (colon.location == NSNotFound || colon.location == 0) continue;
    NSCharacterSet *ws = NSCharacterSet.whitespaceCharacterSet;
    NSString *name = [[lines[i] substringToIndex:colon.location] stringByTrimmingCharactersInSet:ws];
    NSString *value = [[lines[i] substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:ws];
    if ([name caseInsensitiveCompare:@"content-length"] == NSOrderedSame) length = value.longLongValue;
    [headers addObject:@[ name, value ]];
  }
  if (length < 0) return nil;
  NSUInteger start = end.location + 4;
  NSMutableData *body = [[buf subdataWithRange:NSMakeRange(start, buf.length - start)] mutableCopy];
  long long left = length - (long long)body.length;
  while (left > 0) {
    int got = read_some(c, chunk, (size_t)MIN((long long)sizeof chunk, left));
    if (got <= 0) return nil;
    if (body.length < LISTEN_BODY_MOST) [body appendBytes:chunk length:MIN((NSUInteger)got, LISTEN_BODY_MOST - body.length)];
    left -= got;
  }
  if (body.length > (NSUInteger)length) body.length = (NSUInteger)length;
  *body_out = body;
  return @{@"method" : first[0], @"path" : first[1], @"headers" : headers};
}

// A connection taken: its request read on a worker, then handed on (or the connection closed).
static void take(MBListener *l, int c) {
  int on = 1;
  setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof on);
  struct timeval t = {LISTEN_READ_S, 0};
  setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &t, sizeof t);
  setsockopt(c, SOL_SOCKET, SO_SNDTIMEO, &t, sizeof t);
  // An accepted socket keeps the listening one's O_NONBLOCK on Apple's systems: reads here block.
  fcntl(c, F_SETFL, fcntl(c, F_GETFL) & ~O_NONBLOCK);
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSData *body = nil;
    NSDictionary *r = read_request(c, &body);
    if (!r) {
      close(c);
      return;
    }
    dispatch_async(listen_queue(), ^{
      if (l.closed) {
        close(c);
        return;
      }
      long n = ++l.next;
      l.asked[@(n)] = @(c);
      NSMutableDictionary *m = [r mutableCopy];
      m[@"request"] = @(n);
      NSData *json = [NSJSONSerialization dataWithJSONObject:m options:NSJSONWritingWithoutEscapingSlashes error:nil];
      l.fn(l.ctx, json.bytes, json.length, body.bytes, body.length);
    });
  });
}

// ── the API ──

int mb_listen_open(const char *host, int port, mb_listen_fn fn, void *ctx, int *bound, char *why, size_t why_len) {
  int v6 = strcmp(host, "::1") == 0;
  if (!v6 && strcmp(host, "127.0.0.1") != 0) {
    say_why(why, why_len, "not a loopback address");
    return 0;
  }
  if (port < 0 || port > 65535) {
    say_why(why, why_len, "no such port");
    return 0;
  }
  int fd = socket(v6 ? AF_INET6 : AF_INET, SOCK_STREAM, 0);
  if (fd < 0) {
    say_why(why, why_len, strerror(errno));
    return 0;
  }
  int on = 1;
  // Over a connection of an earlier run still in TIME_WAIT; a port another program listens on is still refused.
  setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, sizeof on);
  struct sockaddr_storage at = {0};
  socklen_t at_len;
  if (v6) {
    setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &on, sizeof on);
    struct sockaddr_in6 *a = (struct sockaddr_in6 *)&at;
    a->sin6_len = sizeof *a;
    a->sin6_family = AF_INET6;
    a->sin6_port = htons((uint16_t)port);
    a->sin6_addr = in6addr_loopback;
    at_len = sizeof *a;
  } else {
    struct sockaddr_in *a = (struct sockaddr_in *)&at;
    a->sin_len = sizeof *a;
    a->sin_family = AF_INET;
    a->sin_port = htons((uint16_t)port);
    a->sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    at_len = sizeof *a;
  }
  if (bind(fd, (struct sockaddr *)&at, at_len) != 0 || listen(fd, 16) != 0) {
    say_why(why, why_len, strerror(errno));
    close(fd);
    return 0;
  }
  socklen_t got_len = at_len;
  getsockname(fd, (struct sockaddr *)&at, &got_len);
  if (bound) *bound = ntohs(v6 ? ((struct sockaddr_in6 *)&at)->sin6_port : ((struct sockaddr_in *)&at)->sin_port);
  fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);

  MBListener *l = [MBListener new];
  l.fd = fd;
  l.fn = fn;
  l.ctx = ctx;
  l.asked = [NSMutableDictionary dictionary];
  __block int id = 0;
  dispatch_sync(listen_queue(), ^{
    if (!listeners) listeners = [NSMutableDictionary dictionary];
    id = ++listen_next_id;
    listeners[@(id)] = l;
    dispatch_source_t s = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, listen_queue());
    __weak MBListener *weak = l;
    dispatch_source_set_event_handler(s, ^{
      MBListener *me = weak;
      for (;;) {
        int c = accept(fd, NULL, NULL);
        if (c < 0) break;
        if (!me || me.closed) close(c);
        else take(me, c);
      }
    });
    dispatch_source_set_cancel_handler(s, ^{
      close(fd);
    });
    l.source = s;
    dispatch_resume(s);
  });
  return id;
}

static const char *reason(int status) {
  switch (status) {
    case 200: return "OK";
    case 302: return "Found";
    case 303: return "See Other";
    case 400: return "Bad Request";
    case 404: return "Not Found";
    case 502: return "Bad Gateway";
    default: return "Status";
  }
}

static int write_all(int c, const void *p, size_t n) {
  const uint8_t *b = p;
  while (n > 0) {
    ssize_t w = write(c, b, n);
    if (w < 0 && errno == EINTR) continue;
    if (w <= 0) return -1;
    b += w;
    n -= (size_t)w;
  }
  return 0;
}

void mb_listen_respond(int id, long request, int status, const char *const *headers, int n, const uint8_t *body, size_t blen) {
  // The answer's head, made now (the pointers are the caller's): the connection's own headers are ours.
  NSMutableString *head = [NSMutableString stringWithFormat:@"HTTP/1.1 %d %s\r\n", status, reason(status)];
  NSSet *hop = [NSSet setWithArray:@[ @"connection", @"transfer-encoding", @"content-length", @"keep-alive" ]];
  for (int i = 0; i + 1 < 2 * n; i += 2) {
    NSString *k = @(headers[i]), *v = @(headers[i + 1]);
    if (!k || !v || [hop containsObject:k.lowercaseString]) continue;
    v = [[v stringByReplacingOccurrencesOfString:@"\r" withString:@""] stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    [head appendFormat:@"%@: %@\r\n", k, v];
  }
  [head appendFormat:@"Connection: close\r\nContent-Length: %zu\r\n\r\n", blen];
  NSData *h = [head dataUsingEncoding:NSUTF8StringEncoding];
  NSData *b = [NSData dataWithBytes:body length:blen];
  // Written on the listener's queue (a small page to a loopback peer; SO_SNDTIMEO bounds it), so a close asked after
  // it ends the listener only once the answer is out: an app may exit as its sign-in's listener ends.
  dispatch_async(listen_queue(), ^{
    MBListener *l = listeners[@(id)];
    NSNumber *c = l.asked[@(request)];
    if (!c) return;
    [l.asked removeObjectForKey:@(request)];
    int fd = c.intValue;
    if (write_all(fd, h.bytes, h.length) == 0) write_all(fd, b.bytes, b.length);
    close(fd);
  });
}

void mb_listen_close(int id) {
  dispatch_async(listen_queue(), ^{
    MBListener *l = listeners[@(id)];
    if (!l) return;
    [listeners removeObjectForKey:@(id)];
    l.closed = YES;
    dispatch_source_cancel(l.source);
    for (NSNumber *c in l.asked.allValues) close(c.intValue);
    [l.asked removeAllObjects];
    l.fn(l.ctx, NULL, 0, NULL, 0);
  });
}
