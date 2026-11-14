// iOS has no LSEnvironment. The app's signed metadata supplies only these two public product settings; an explicit
// simulator environment wins. No sign-in or test credentials may be supplied through the bundle.
static void sf_product_environment(id env) {
  if (![env isKindOfClass:NSDictionary.class]) return;
  for (NSString *name in @[ @"MBUI_CLOUD", @"MBUI_PRODUCT" ]) {
    id value = env[name];
    if ([value isKindOfClass:NSString.class]) setenv(name.UTF8String, [value UTF8String], 0);
  }
}
