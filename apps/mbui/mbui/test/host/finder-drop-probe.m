// Scratch experiment: drive Finder and the retained-node probe through the actual macOS desktop.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

static id attribute(AXUIElementRef element, CFStringRef name) {
  CFTypeRef value = NULL;
  return AXUIElementCopyAttributeValue(element, name, &value) == kAXErrorSuccess ? CFBridgingRelease(value) : nil;
}

static BOOL rectangle(AXUIElementRef element, CGRect *rect) {
  id pos = attribute(element, kAXPositionAttribute), size = attribute(element, kAXSizeAttribute);
  CGPoint p; CGSize s;
  if (!pos || !size || !AXValueGetValue((__bridge AXValueRef)pos, kAXValueCGPointType, &p) ||
      !AXValueGetValue((__bridge AXValueRef)size, kAXValueCGSizeType, &s)) return NO;
  *rect = (CGRect){p, s};
  return s.width > 0 && s.height > 0;
}

static void place(AXUIElementRef element, CGPoint p, CGSize s) {
  AXValueRef position = AXValueCreate(kAXValueCGPointType, &p);
  AXValueRef size = AXValueCreate(kAXValueCGSizeType, &s);
  AXError a = AXUIElementSetAttributeValue(element, kAXPositionAttribute, position);
  AXError b = AXUIElementSetAttributeValue(element, kAXSizeAttribute, size);
  CFRelease(position); CFRelease(size);
  fprintf(stdout, "FINDER place position=%d size=%d\n", a, b);
}

static void onAX(AXObserverRef observer, AXUIElementRef element, CFStringRef name, void *data) {
  (void)observer; (void)element; (void)name; (void)data;
}

static AXObserverRef observe(AXUIElementRef app, pid_t pid) {
  AXObserverRef observer = NULL;
  if (AXObserverCreate(pid, onAX, &observer) != kAXErrorSuccess) return NULL;
  AXError result = AXObserverAddNotification(observer, app, kAXWindowCreatedNotification, NULL);
  fprintf(stdout, "FINDER observing process=%d window-created=%d\n", pid, result);
  CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), kCFRunLoopDefaultMode);
  return observer;
}

static AXUIElementRef firstWindow(AXUIElementRef app, CFAbsoluteTime deadline) {
  while (CFAbsoluteTimeGetCurrent() < deadline) {
    NSArray *windows = attribute(app, kAXWindowsAttribute);
    if (windows.count) return CFRetain((__bridge AXUIElementRef)windows[0]);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, deadline - CFAbsoluteTimeGetCurrent(), true);
  }
  return NULL;
}

static AXUIElementRef fileElement(AXUIElementRef element, NSString *name, int depth, int *count) {
  if (depth > 16 || ++*count > 2500) return NULL;
  for (NSString *key in @[(__bridge NSString *)kAXTitleAttribute, (__bridge NSString *)kAXDescriptionAttribute,
                           (__bridge NSString *)kAXValueAttribute, @"AXFilename"]) {
    id value = attribute(element, (__bridge CFStringRef)key);
    CGRect box;
    if ([value isKindOfClass:NSString.class] && [value containsString:name] && rectangle(element, &box)) {
      fprintf(stdout, "FINDER matched %s role=%s rect=%.1f,%.1f %.1fx%.1f\n", [key UTF8String],
              [[attribute(element, kAXRoleAttribute) description] UTF8String], box.origin.x, box.origin.y,
              box.size.width, box.size.height);
      return CFRetain(element);
    }
  }
  NSArray *children = attribute(element, kAXChildrenAttribute);
  for (id child in children) {
    AXUIElementRef found = fileElement((__bridge AXUIElementRef)child, name, depth + 1, count);
    if (found) return found;
  }
  return NULL;
}

static void dumpTree(AXUIElementRef element, int depth, int *count) {
  if (depth > 8 || ++*count > 250) return;
  id role = attribute(element, kAXRoleAttribute), title = attribute(element, kAXTitleAttribute);
  id desc = attribute(element, kAXDescriptionAttribute), value = attribute(element, kAXValueAttribute);
  fprintf(stdout, "FINDER AX %d role=%s title=%s desc=%s value=%s\n", depth, [[role description] UTF8String],
          [[title description] UTF8String], [[desc description] UTF8String], [[value description] UTF8String]);
  for (id child in (NSArray *)attribute(element, kAXChildrenAttribute))
    dumpTree((__bridge AXUIElementRef)child, depth + 1, count);
}

static void mouse(CGEventType kind, CGPoint point) {
  CGEventRef event = CGEventCreateMouseEvent(NULL, kind, point, kCGMouseButtonLeft);
  CGEventPost(kCGHIDEventTap, event);
  CFRelease(event);
}

static void screenshot(NSString *path) {
  NSTask *task = [NSTask new];
  task.executableURL = [NSURL fileURLWithPath:@"/usr/sbin/screencapture"];
  task.arguments = @[@"-x", path];
  [task launchAndReturnError:nil];
  [task waitUntilExit];
}

int main(int argc, const char **argv) {
  @autoreleasepool {
    if (argc != 5) { fprintf(stderr, "usage: finder-drop-probe exe file log screenshot\n"); return 2; }
    NSString *exe = [NSString stringWithUTF8String:argv[1]], *file = [NSString stringWithUTF8String:argv[2]];
    NSString *logPath = [NSString stringWithUTF8String:argv[3]], *shot = [NSString stringWithUTF8String:argv[4]];
    fprintf(stdout, "FINDER AX trusted=%d input trusted=%d\n", AXIsProcessTrusted(), CGPreflightPostEventAccess());
    NSRunningApplication *finder = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.finder"].firstObject;
    if (!finder) { fprintf(stderr, "FINDER is not running\n"); return 1; }
    AXUIElementRef finderAX = AXUIElementCreateApplication(finder.processIdentifier);
    AXObserverRef finderObserver = observe(finderAX, finder.processIdentifier);
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:file]]];

    NSPipe *pipe = [NSPipe pipe];
    NSTask *probe = [NSTask new];
    probe.executableURL = [NSURL fileURLWithPath:exe];
    NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
    env[@"MBUI_BENCH"] = @"-1"; env[@"MBUI_WIN"] = @"560x400";
    probe.environment = env; probe.standardOutput = pipe; probe.standardError = pipe;
    __block NSMutableString *lines = [NSMutableString new];
    NSLock *lock = [NSLock new];
    dispatch_semaphore_t changed = dispatch_semaphore_create(0);
    pipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
      NSData *data = handle.availableData;
      if (!data.length) return;
      NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
      [lock lock]; [lines appendString:text]; [lock unlock];
      dispatch_semaphore_signal(changed);
    };
    NSError *error = nil;
    if (![probe launchAndReturnError:&error]) { fprintf(stderr, "FINDER cannot launch probe: %s\n", error.description.UTF8String); return 1; }
    AXUIElementRef appAX = AXUIElementCreateApplication(probe.processIdentifier);
    AXObserverRef appObserver = observe(appAX, probe.processIdentifier);
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + 45.0;
    AXUIElementRef appWindow = firstWindow(appAX, deadline), finderWindow = firstWindow(finderAX, deadline);
    BOOL held = NO, ok = NO;
    CGPoint target = CGPointZero;
    do {
      if (!appWindow || !finderWindow) { fprintf(stderr, "FINDER window unavailable app=%p finder=%p\n", appWindow, finderWindow); break; }
      place(finderWindow, CGPointMake(5, 30), CGSizeMake(455, 620));
      place(appWindow, CGPointMake(470, 30), CGSizeMake(540, 500));
      CGRect appRect;
      if (!rectangle(appWindow, &appRect)) { fprintf(stderr, "FINDER cannot locate app window\n"); break; }
      int count = 0;
      AXUIElementRef item = fileElement(finderWindow, file.lastPathComponent, 0, &count);
      if (!item) {
        fprintf(stderr, "FINDER file not in AX tree; inspected %d elements\n", count);
        count = 0; dumpTree(finderWindow, 0, &count); screenshot(shot); break;
      }
      CGRect itemRect;
      if (!rectangle(item, &itemRect)) { CFRelease(item); break; }
      CGPoint source = CGPointMake(CGRectGetMidX(itemRect), CGRectGetMidY(itemRect));
      target = CGPointMake(appRect.origin.x + 250, appRect.origin.y + 170);
      fprintf(stdout, "FINDER source=%.1f,%.1f target=%.1f,%.1f app=%.1f,%.1f %.1fx%.1f\n",
              source.x, source.y, target.x, target.y, appRect.origin.x, appRect.origin.y,
              appRect.size.width, appRect.size.height);
      [finder activateWithOptions:NSApplicationActivateIgnoringOtherApps];
      mouse(kCGEventMouseMoved, source);
      mouse(kCGEventLeftMouseDown, source); held = YES;
      (void)attribute(finderWindow, kAXPositionAttribute); // Finder's UI thread has heard the press.
      mouse(kCGEventLeftMouseDragged, CGPointMake(source.x + 30, source.y));
      (void)attribute(finderWindow, kAXPositionAttribute);
      mouse(kCGEventLeftMouseDragged, target);
      NSString *hover = @"HOVER folder";
      while (YES) {
        [lock lock]; BOOL found = [lines containsString:hover]; [lock unlock];
        if (found) break;
        if (dispatch_semaphore_wait(changed, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC))) {
          fprintf(stderr, "FINDER no hover\n"); screenshot(shot); goto finished;
        }
      }
      screenshot(shot);
      mouse(kCGEventLeftMouseUp, target); held = NO;
      NSString *read = [@"READ folder " stringByAppendingString:file.lastPathComponent];
      while (YES) {
        [lock lock]; BOOL found = [lines containsString:read]; [lock unlock];
        if (found) break;
        if (dispatch_semaphore_wait(changed, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC))) {
          fprintf(stderr, "FINDER no asynchronous file read\n"); goto finished;
        }
      }
      [lock lock]; NSString *got = [lines copy]; [lock unlock];
      NSUInteger drops = [got componentsSeparatedByString:@"DROP folder"].count - 1;
      NSUInteger reads = [got componentsSeparatedByString:read].count - 1;
      if (drops == 1 && reads == 1) { fprintf(stdout, "FINDER real drag: hover, one drop, one file read\n"); ok = YES; }
      else fprintf(stderr, "FINDER wrong counts drop=%lu read=%lu\n", (unsigned long)drops, (unsigned long)reads);
      CFRelease(item);
    } while (0);
  finished:
    if (held) mouse(kCGEventLeftMouseUp, target);
    if (probe.isRunning) [probe terminate];
    [probe waitUntilExit];
    pipe.fileHandleForReading.readabilityHandler = nil;
    [lock lock]; [lines writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    fprintf(stdout, "%s\n", lines.UTF8String); [lock unlock];
    if (appWindow) CFRelease(appWindow);
    if (finderWindow) CFRelease(finderWindow);
    if (appObserver) CFRelease(appObserver);
    if (finderObserver) CFRelease(finderObserver);
    CFRelease(appAX); CFRelease(finderAX);
    return ok ? 0 : 1;
  }
}
