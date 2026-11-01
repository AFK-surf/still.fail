// A chart made by the core in the app's engine (src/host/apple_core.mm), as the app asks for one: the core given
// mermaid's bytecode (`mermaid.load`, the bytes beside it: what sfbase's mermaid_hbc.mbt carries), then a chart of each
// of a few kinds (`mermaid.chart`), timed. Built and run by `scripts/core.sh mermaid-smoke`.
//   mermaid_smoke <data dir> <mermaid.hbc>        (MB_CORE_BUNDLE: the core's script)
// Exit 0 when every chart came as SVG.
#import <Foundation/Foundation.h>
#include <time.h>
#include "core_api.h"

static double t0, asked;
static dispatch_semaphore_t answered;
static NSDictionary *answer;

static double now_ms(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (double)t.tv_sec * 1000.0 + (double)t.tv_nsec / 1e6;
}

static void on_message(const char *json, size_t len, const uint8_t *bytes, size_t blen, void *ctx) {
  NSDictionary *m = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:json length:len] options:0 error:nil];
  if (![m isKindOfClass:NSDictionary.class]) return;
  if (m[@"fatal"]) {
    printf("fatal: %s\n", [m[@"fatal"] description].UTF8String);
    answer = @{@"error" : @"fatal"};
    dispatch_semaphore_signal(answered);
  } else if ([m[@"id"] intValue] >= 10) {
    answer = m;
    dispatch_semaphore_signal(answered);
  }
}

/// Call `name` with `params` (and `bytes` beside it), its answer waited for (at most a minute).
static NSDictionary *call(int id_, NSString *name, NSDictionary *params, NSData *bytes) {
  NSData *d = [NSJSONSerialization dataWithJSONObject:@{@"id" : @(id_), @"call" : name, @"params" : params} options:0 error:nil];
  asked = now_ms();
  answer = nil;
  mb_core_send(d.bytes, d.length, bytes.bytes, bytes.length);
  if (dispatch_semaphore_wait(answered, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)) != 0) return @{@"error" : @"no answer in a minute"};
  return answer;
}

int main(int argc, char **argv) {
  @autoreleasepool {
    if (argc < 3) {
      fprintf(stderr, "usage: mermaid_smoke <data dir> <mermaid.hbc>\n");
      return 2;
    }
    NSData *hbc = [NSData dataWithContentsOfFile:@(argv[2])];
    if (!hbc.length) {
      fprintf(stderr, "no mermaid bytecode at %s\n", argv[2]);
      return 2;
    }
    answered = dispatch_semaphore_create(0);
    t0 = now_ms();
    mb_core_start(argv[1], "http://127.0.0.1:1", 0, on_message, NULL);
    NSDictionary *loaded = call(10, @"mermaid.load", @{}, hbc);
    printf("mermaid.load (%lu bytes): %.0f ms %s\n", (unsigned long)hbc.length, now_ms() - asked, loaded[@"error"] ? [loaded[@"error"] description].UTF8String : "ok");
    NSDictionary *colours = @{@"background" : @"#ffffff", @"card" : @"#ffffff", @"border" : @"#c8c8c8", @"text" : @"#171717",
                              @"line" : @"#737373", @"accent" : @"#f5f5f5", @"muted" : @"#f5f5f5", @"brand" : @"#ea580c"};
    NSArray *charts = @[
      @[ @"flowchart", @"flowchart TD\n  A[用户发消息] --> B{有附件吗?}\n  B -->|有| C[上传到 station]\n  B -->|没有| D[直接发送]" ],
      @[ @"sequence", @"sequenceDiagram\n  App->>Core: mermaid.chart\n  Core-->>App: SVG" ],
      @[ @"mindmap", @"mindmap\n  root((still.fail))\n    App\n    Core" ],
    ];
    int bad = loaded[@"error"] != nil, id_ = 11;
    for (NSArray *c in charts) {
      NSDictionary *a = call(id_++, @"mermaid.chart", @{@"code" : c[1], @"dark" : @NO, @"colours" : colours, @"width" : @720}, nil);
      NSString *svg = [a[@"ok"] isKindOfClass:NSDictionary.class] ? a[@"ok"][@"svg"] : nil;
      printf("%s: %.0f ms, %s\n", [c[0] UTF8String], now_ms() - asked,
             svg ? [NSString stringWithFormat:@"%lu chars of SVG", (unsigned long)svg.length].UTF8String : [a description].UTF8String);
      if (!svg) bad = 1;
    }
    mb_core_stop();
    return bad;
  }
}
