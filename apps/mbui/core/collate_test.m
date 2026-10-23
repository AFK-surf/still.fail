// src/host/apple_collate.h: the order people read names in, as the core asks it (text.collate). Built and run by
// `scripts/core.sh collate`. Exit 0 when Chinese names come in pinyin's order in Chinese, case aside, numbers by their
// value, equal names one place, and an ask with a name that is no string is said to be wrong.
#import <Foundation/Foundation.h>
#include "apple_collate.h"

static int check(NSString *what, NSArray *got, NSArray *want) {
  if ([got isEqualToArray:want]) return 0;
  printf("collate: %s: %s, not %s\n", what.UTF8String, got.description.UTF8String, want.description.UTF8String);
  return 1;
}

int main(void) {
  @autoreleasepool {
    NSLocale *zh = [NSLocale localeWithLocaleIdentifier:@"zh-Hans"];
    NSLocale *en = [NSLocale localeWithLocaleIdentifier:@"en"];
    int bad = 0;
    // 张 zhāng, 李 lǐ, 阿 ā: by pinyin, not by their codes (张 U+5F20 < 李 U+674E < 阿 U+963F)
    bad |= check(@"pinyin", apple_collate(@[ @"张三", @"李四", @"阿" ], zh), @[ @2, @1, @0 ]);
    // A and a one place; a2 before a10
    bad |= check(@"case and numbers", apple_collate(@[ @"a10", @"A", @"a2", @"a", @"b" ], en), @[ @3, @0, @2, @0, @4 ]);
    bad |= check(@"none", apple_collate(@[], en), @[]);
    if (apple_collate(@[ @"a", @1 ], en) != nil) {
      printf("collate: a name that is no string was taken\n");
      bad = 1;
    }
    NSData *said = apple_collate_answer([@"{\"names\":[\"b\",\"a\"]}" dataUsingEncoding:NSUTF8StringEncoding]);
    bad |= check(@"the ask answered", [NSJSONSerialization JSONObjectWithData:said options:0 error:nil][@"value"], @[ @1, @0 ]);
    if (!bad) printf("collate: names in the order people read them\n");
    return bad;
  }
}
