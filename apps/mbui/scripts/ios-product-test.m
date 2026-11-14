#import <Foundation/Foundation.h>
#include "../src/sfcore/apple_product.h"

int main(int argc, const char **argv) {
  @autoreleasepool {
    if (argc != 2) return 1;
    unsetenv("MBUI_PRODUCT");
    unsetenv("MBUI_CLOUD");
    unsetenv("MBUI_CORE_ACCOUNT");
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:@(argv[1])];
    sf_product_environment(info[@"MBUIEnvironment"]);
    if (!getenv("MBUI_PRODUCT") || strcmp(getenv("MBUI_PRODUCT"), "monoid")) return 2;
    if (!getenv("MBUI_CLOUD") || strcmp(getenv("MBUI_CLOUD"), "https://app.monoid.build")) return 3;
    // A simulator's explicit cloud takes precedence; unrecognized or malformed settings do nothing.
    setenv("MBUI_CLOUD", "http://127.0.0.1:18900", 1);
    sf_product_environment(@{@"MBUI_CLOUD": @"https://other.example", @"MBUI_CORE_ACCOUNT": @"no", @"MBUI_PRODUCT": @7});
    sf_product_environment(NSNull.null);
    if (strcmp(getenv("MBUI_CLOUD"), "http://127.0.0.1:18900")) return 4;
    if (strcmp(getenv("MBUI_PRODUCT"), "monoid") || getenv("MBUI_CORE_ACCOUNT")) return 5;
  }
  puts("iOS bundle product environment: passed");
  return 0;
}
