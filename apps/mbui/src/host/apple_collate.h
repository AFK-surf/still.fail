// The order people read names in, for the core (its Host.collate: client/core-ts's text.collate, a sync op through
// apple_core.mm's callSync): the system's, as the Finder sorts them (localizedStandardCompare's: case, accents and
// widths aside, digits by their value, in the person's first language: 中文 by pinyin), each name's place in it, equal
// names one place. The web's is Intl.Collator's in the browser's language; with none here the core orders by hand.
// Included by apple_core.mm and core/collate_test.m.
#pragma once
#import <Foundation/Foundation.h>

// Each of `names`' place in their order in `locale` (equal ones the first of their place's), nil when one is no string.
static NSArray<NSNumber *> *apple_collate(NSArray *names, NSLocale *locale) {
  for (id n in names)
    if (![n isKindOfClass:NSString.class]) return nil;
  NSStringCompareOptions how =
      NSCaseInsensitiveSearch | NSNumericSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch;
  NSComparisonResult (^cmp)(NSString *, NSString *) = ^NSComparisonResult(NSString *x, NSString *y) {
    return [x compare:y options:how range:NSMakeRange(0, x.length) locale:locale];
  };
  NSMutableArray<NSNumber *> *order = [NSMutableArray arrayWithCapacity:names.count];
  for (NSUInteger i = 0; i < names.count; i++) [order addObject:@(i)];
  [order sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSNumber *x, NSNumber *y) {
    return cmp(names[x.unsignedIntegerValue], names[y.unsignedIntegerValue]);
  }];
  NSMutableArray<NSNumber *> *place = [NSMutableArray arrayWithCapacity:names.count];
  for (NSUInteger i = 0; i < names.count; i++) [place addObject:@0];
  NSUInteger at = 0;
  for (NSUInteger k = 0; k < order.count; k++) {
    NSUInteger i = order[k].unsignedIntegerValue;
    if (k > 0 && cmp(names[order[k - 1].unsignedIntegerValue], names[i]) != NSOrderedSame) at = k;
    place[i] = @(at);
  }
  return place;
}

// The core's ask (`{"names": [...]}`) answered: `{"value": [place, …]}` in the person's first language, or why not.
static NSData *apple_collate_answer(NSData *ask) {
  NSDictionary *a = [NSJSONSerialization JSONObjectWithData:ask options:0 error:nil];
  NSArray *names = [a isKindOfClass:NSDictionary.class] ? a[@"names"] : nil;
  NSString *lang = NSLocale.preferredLanguages.firstObject;
  NSArray *place = [names isKindOfClass:NSArray.class]
                       ? apple_collate(names, lang ? [NSLocale localeWithLocaleIdentifier:lang] : NSLocale.currentLocale)
                       : nil;
  NSDictionary *out = place ? @{@"value" : place} : @{@"error" : @"text.collate: names are strings"};
  return [NSJSONSerialization dataWithJSONObject:out options:0 error:nil];
}
