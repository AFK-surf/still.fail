// WebM and VP9 in MP4 on macOS: WebKit supports formats where AVPlayer does not. The web view is only the picture and decoder;
// the app still owns the player controls and supplies all file bytes through the same bounded read API as AVPlayer.
// Included by apple_views.m after MBNative, so it shares that host's lifetime and snapshot machinery.

@interface MBWebLoad : NSObject
@property(nonatomic, strong) id<WKURLSchemeTask> task;
@property(nonatomic, copy) NSString *range;
@property(nonatomic) long long next, end;
@property(nonatomic) BOOL gone, probe, headed;
@end
@implementation MBWebLoad
@end

@interface MBWebCache : NSObject
@property(nonatomic) long long off;
@property(nonatomic, strong) NSMutableData *bytes;
@end
@implementation MBWebCache
@end

@interface MBWebRead : NSObject
@property(nonatomic) int32_t rid;
@property(nonatomic) long long off, len, got;
@property(nonatomic, strong) MBWebLoad *load;
@property(nonatomic, strong) MBWebCache *cache;
@end
@implementation MBWebRead
@end

#if TARGET_OS_OSX
// Like MBPlayerView, the picture takes no input: the app handles gestures over it.
@interface MBWebVideoView : WKWebView
@end
@implementation MBWebVideoView
- (NSView *)hitTest:(NSPoint)point { return nil; }
@end
#endif

@interface MBWebVideo : NSObject <WKURLSchemeHandler, WKScriptMessageHandler, WKNavigationDelegate>
@property(nonatomic, weak) MBNative *owner;
@property(nonatomic, strong) NSMutableArray<MBWebLoad *> *loads;
@property(nonatomic, strong) NSMutableArray<MBWebRead *> *pending;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, MBWebRead *> *taken;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *lettingGo;
@property(nonatomic, strong) NSMutableArray<NSString *> *commands;
@property(nonatomic, strong) NSMutableArray<MBWebCache *> *cache;
@property(nonatomic, strong) NSDictionary *state;
@property(nonatomic, copy) NSString *mime;
@property(nonatomic, copy) NSString *html, *softwareDir;
@property(nonatomic) long long total;
@property(nonatomic) int32_t nextRid;
@property(nonatomic) uint32_t firstBytes;
@property(nonatomic) unsigned firstMask;
@property(nonatomic) BOOL pageReady, closed, primed, ready, possibleWebM, usedSoftware, fallbackRequested;
@property(nonatomic) BOOL grabbing, grabPNG;
@property(nonatomic) double grabSide;
- (void)control:(int32_t)op value:(double)value;
- (int32_t)info:(double *)out;
- (int32_t)readNext:(double *)out;
- (void)readAnswer:(int32_t)rid data:(const uint8_t *)bytes length:(long long)n total:(double)total more:(BOOL)more;
- (void)send:(NSString *)command;
- (void)grab;
- (void)finishGrab:(NSData *)data;
- (void)refreshSnap;
- (void)close;
@end

// This page contains no user content. The file never gets a network URL or any script from the file. WebKit takes a
// native snapshot when the app asks for a frame; a canvas cannot read media served from a custom scheme.
static NSString *const kWebVideoHTML =
    @"<!doctype html><meta name='viewport' content='width=device-width,initial-scale=1'>\n"
     "<style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#000}#v{width:100%;height:100%;object-fit:fill;display:block}</style>\n"
     "<video id='v' playsinline preload='none' src='mbvideo://local/file.media'></video>\n"
     "<script>\n"
     "let v = document.getElementById('v');\n"
     "let soft = false, switching = false, frameReady = false, drawn = false, softwareError = 0;\n"
     "let waiting = false, ticking = false, changes = 0, grabRestore = null, pendingGrab = null;\n"
     "let grabPosition = null, restoringGrab = false;\n"
     "let wantPlay = false, wantRate = 1, wantVolume = 1, wantSeek = null;\n"
     "const mediaURL = 'mbvideo://local/file.media';\n"
     "const post = o => window.webkit.messageHandlers.mbvideo.postMessage(o);\n"
     "function ready() { return !switching && v.readyState >= 2; }\n"
     "function status() {\n"
     "  let b = 0;\n"
     "  try { for (let i = 0; i < v.buffered.length; i++) if (v.buffered.start(i) <= v.currentTime + .001) b = Math.max(b, v.buffered.end(i)); } catch (_) {}\n"
     "  const error = softwareError || (!switching && v.error ? (v.error.code || 4) : 0);\n"
     "  post({type:'state', duration:Number.isFinite(v.duration) ? v.duration * 1000 : -1,\n"
     "    position:grabPosition !== null ? grabPosition * 1000 : Number.isFinite(v.currentTime) ? v.currentTime * 1000 : 0,\n"
     "    playing:!switching && !v.paused && !v.ended, rate:v.playbackRate || wantRate,\n"
     "    width:v.videoWidth || 0, height:v.videoHeight || 0, shown:ready(), ready:ready(),\n"
     "    waiting:waiting || switching, buffered:b * 1000, ended:!!v.ended, error});\n"
     "}\n"
     "function tick() { if (switching || v.paused || v.ended) { ticking = false; return; } status(); requestAnimationFrame(tick); }\n"
     "function startTick() { if (!ticking) { ticking = true; requestAnimationFrame(tick); } }\n"
     "function playNow() {\n"
     "  if (switching) return;\n"
     "  try { const promise = v.play(); if (promise && promise.catch) promise.catch(() => status()); }\n"
     "  catch (_) { softwareError = 4; status(); }\n"
     "}\n"
     "function wire(el) {\n"
     "  for (const event of ['loadedmetadata','durationchange','progress','timeupdate','pause','seeked','ended','ratechange','volumechange']) {\n"
     "    el.addEventListener(event, () => {\n"
     "      if (el !== v) return;\n"
     "      if (soft && (event === 'timeupdate' || event === 'seeked')) drawn = true;\n"
     "      if (event === 'seeked') {\n"
     "        wantSeek = null;\n"
     "        if (restoringGrab) { restoringGrab = false; if (wantPlay) grabPosition = null; }\n"
     "      }\n"
     "      if (soft && event === 'loadedmetadata') {\n"
     "        try {\n"
     "          v.playbackRate = wantRate; v.volume = wantVolume;\n"
     "          if (wantSeek !== null) v.currentTime = wantSeek;\n"
     "          if (wantPlay) playNow();\n"
     "        } catch (_) { softwareError = 4; }\n"
     "      }\n"
     "      status();\n"
     "    });\n"
     "  }\n"
     "  el.addEventListener('loadeddata', () => {\n"
     "    if (el !== v) return;\n"
     "    frameReady = true; status();\n"
     "    if (pendingGrab !== null) { const ms = pendingGrab; pendingGrab = null; grab(ms); }\n"
     "  });\n"
     "  el.addEventListener('waiting', () => { if (el === v) { waiting = true; status(); } });\n"
     "  el.addEventListener('playing', () => { if (el === v) { waiting = false; status(); startTick(); } });\n"
     "  el.addEventListener('canplay', () => { if (el === v) { waiting = false; status(); } });\n"
     "  el.addEventListener('error', () => { if (el === v) status(); });\n"
     "}\n"
     "function fallback() {\n"
     "  if (soft || switching) return;\n"
     "  if (!window.mbCanSoft) { softwareError = 4; status(); return; }\n"
     "  const old = v;\n"
     "  if (Number.isFinite(old.currentTime) && wantSeek === null) wantSeek = old.currentTime;\n"
     "  switching = true; frameReady = false; drawn = false; post({type:'soft'});\n"
     "  old.pause(); status();\n"
     "  const script = document.createElement('script');\n"
     "  script.src = 'mbvideo://local/ogv/ogv.js';\n"
     "  script.onerror = () => { switching = false; softwareError = 4; status(); };\n"
     "  script.onload = () => {\n"
     "    try {\n"
     "      OGVLoader.base = 'mbvideo://local/ogv';\n"
     "      const player = new OGVPlayer({worker:false, threading:false, simd:false});\n"
     "      player.id = 'v'; player.style.width = '100%'; player.style.height = '100%';\n"
     "      old.replaceWith(player); v = player; soft = true; switching = false; waiting = true;\n"
     "      wire(player); player.src = mediaURL; player.load(); status();\n"
     "    } catch (_) { switching = false; softwareError = 4; status(); }\n"
     "  };\n"
     "  document.head.appendChild(script);\n"
     "}\n"
     "window.addEventListener('error', () => { if (soft || switching) { switching = false; softwareError = 4; status(); } });\n"
     "window.addEventListener('unhandledrejection', () => { if (soft || switching) { switching = false; softwareError = 4; status(); } });\n"
     "function grab(ms) {\n"
     "  if (switching) { pendingGrab = ms; return; }\n"
     "  if (v.error) { if (!soft && window.mbCanSoft) pendingGrab = ms; else post({type:'grabFailed'}); return; }\n"
     "  if (!ready()) {\n"
     "    const target = v;\n"
     "    const clear = () => { for (const e of ['loadedmetadata','loadeddata','canplay','seeked']) target.removeEventListener(e, loaded); target.removeEventListener('error', failed); };\n"
     "    const loaded = () => { clear(); grab(ms); };\n"
     "    const failed = () => { clear(); if (!soft && window.mbCanSoft) pendingGrab = ms; else post({type:'grabFailed'}); };\n"
     "    for (const e of ['loadedmetadata','loadeddata','canplay','seeked']) target.addEventListener(e, loaded, {once:true});\n"
     "    target.addEventListener('error', failed, {once:true}); return;\n"
     "  }\n"
     "  if (v.seeking) { v.addEventListener('seeked', () => grab(ms), {once:true}); return; }\n"
     "  const target = ms >= 0 ? ms : v.currentTime * 1000;\n"
     "  const readyGrab = () => { drawn = true; post({type:'grabReady'}); };\n"
     "  if ((soft && !drawn) || Math.abs(v.currentTime * 1000 - target) >= 1) {\n"
     "    if (Math.abs(v.currentTime * 1000 - target) >= 1) {\n"
     "      if (soft && grabPosition === null) grabPosition = v.currentTime;\n"
     "      grabRestore = {time:soft ? grabPosition : v.currentTime, changes};\n"
     "    }\n"
     "    v.addEventListener('seeked', readyGrab, {once:true});\n"
     "    try { v.currentTime = target / 1000; } catch (_) { post({type:'grabFailed'}); }\n"
     "  } else if (v.seeking) v.addEventListener('seeked', readyGrab, {once:true}); else readyGrab();\n"
     "}\n"
     "function endGrab() {\n"
     "  if (grabRestore) {\n"
     "    if (grabRestore.changes === changes && !v.error) {\n"
     "      restoringGrab = soft; v.currentTime = grabRestore.time;\n"
     "    } else { grabPosition = null; restoringGrab = false; }\n"
     "  }\n"
     "  grabRestore = null;\n"
     "}\n"
     "window.mbPlayer = {\n"
     "  play() { changes++; grabPosition = null; restoringGrab = false; wantPlay = true; if (v.ended) v.currentTime = 0; playNow(); },\n"
     "  pause() { changes++; grabPosition = null; restoringGrab = false; wantPlay = false; if (!switching) v.pause(); status(); },\n"
     "  seek(ms) { changes++; grabPosition = null; restoringGrab = false; wantSeek = Math.max(0, Math.min(Number.isFinite(v.duration) ? v.duration : Infinity, ms / 1000)); if (!switching) v.currentTime = wantSeek; status(); },\n"
     "  rate(r) { wantRate = r; if (!switching) v.playbackRate = r; status(); },\n"
     "  volume(n) { wantVolume = n; if (!switching) v.volume = n; status(); },\n"
     "  grab, endGrab, fallback,\n"
     "  fallbackIfNeeded() { if (!ready() || v.error) fallback(); else { post({type:'nativeReady'}); status(); } }\n"
     "};\n"
     "wire(v);\n"
     "if (window.mbStartSoft) fallback(); else { v.preload = 'auto'; status(); }\n"
     "</script>\n";

// One byte range, with an exclusive end. Only single ranges are used by a media element; malformed or unsatisfiable
// requests get 416 rather than accidentally returning another user's bytes or reading past the file.
static BOOL webm_range(NSString *header, long long size, long long *start, long long *end) {
  *start = 0; *end = size;
  if (!header.length) return YES;
  if (![header hasPrefix:@"bytes="] || size <= 0) return NO;
  NSString *s = [header substringFromIndex:6];
  NSArray<NSString *> *p = [s componentsSeparatedByString:@"-"];
  if (p.count != 2 || (!p[0].length && !p[1].length)) return NO;
  long long a = 0, b = 0;
  if (p[0].length) {
    NSScanner *scan = [NSScanner scannerWithString:p[0]];
    scan.charactersToBeSkipped = nil;
    if (![scan scanLongLong:&a] || !scan.isAtEnd || a < 0 || a >= size) return NO;
    *start = a;
    if (p[1].length) {
      scan = [NSScanner scannerWithString:p[1]];
      scan.charactersToBeSkipped = nil;
      if (![scan scanLongLong:&b] || !scan.isAtEnd || b < a) return NO;
      *end = b >= size - 1 ? size : b + 1;
    }
  } else {
    NSScanner *scan = [NSScanner scannerWithString:p[1]];
    scan.charactersToBeSkipped = nil;
    if (![scan scanLongLong:&b] || !scan.isAtEnd || b <= 0) return NO;
    *start = b >= size ? 0 : size - b;
  }
  return YES;
}

@implementation MBWebVideo

- (void)notify {
  MBNative *v = self.owner;
  if (!v || self.closed) return;
  [v stood];
  mb_host_request_frame();
}

- (void)ask:(MBWebLoad *)l off:(long long)off len:(long long)len {
  if (self.closed || l.gone) return;
  MBWebRead *r = [MBWebRead new];
  r.rid = ++self.nextRid; r.off = off; r.len = len; r.load = l;
  // WebKit's MP4 demuxer often asks for a few bytes at a time. Keep a few bounded parts so those requests do not
  // each make another round trip to a remote station.
  if (!l.probe && [self.mime isEqualToString:@"video/mp4"] && len <= (128 << 10)) {
    MBWebCache *cached = [MBWebCache new];
    cached.off = off; cached.bytes = [NSMutableData new]; r.cache = cached;
    [self.cache addObject:cached];
    if (self.cache.count > 4) [self.cache removeObjectAtIndex:0];
  }
  [self.pending addObject:r];
  mb_host_outside(MB_OUTSIDE_VIEW, self.owner.vid, 0);
  [self notify];
}

// Cancelled WebKit requests cancel the app's outstanding reads too, including one whose answer is still streaming.
- (void)drop:(MBWebLoad *)l {
  if (l.gone) return;
  l.gone = YES;
  [self.loads removeObject:l];
  NSMutableArray *keep = [NSMutableArray new];
  for (MBWebRead *r in self.pending) if (r.load != l) [keep addObject:r];
  self.pending = keep;
  for (NSNumber *rid in self.taken.allKeys) {
    if (self.taken[rid].load != l) continue;
    [self.taken removeObjectForKey:rid];
    [self.lettingGo addObject:rid];
  }
  if (self.lettingGo.count) mb_host_request_frame();
}

- (void)end:(MBWebLoad *)l error:(BOOL)error {
  if (l.gone) return;
  if (error) {
    [l.task didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotOpenFile userInfo:nil]];
  } else {
    [l.task didFinish];
  }
  [self drop:l];
}

- (void)failWithCode:(int32_t)code {
  MBNative *v = self.owner;
  if (!v || self.closed || v.failed) return;
  v.failed = YES; v.playerFailure = code;
  for (MBWebLoad *l in [self.loads copy]) [self end:l error:YES];
  if (self.grabbing) [self finishGrab:nil];
  [v tell:-1];
  [self notify];
}

- (void)fail { [self failWithCode:-1]; }

// Some WebKit versions fully buffer an unsupported VP9 profile but never report a decoder error or a first frame.
// Once the finite video has arrived, ask the page to switch if WebKit is still unable to show a frame. The page checks
// again when it receives the request, so a native decoder that became ready meanwhile keeps playing normally.
- (BOOL)fullyBuffered {
  double duration = [self.state[@"duration"] doubleValue], buffered = [self.state[@"buffered"] doubleValue];
  return duration > 0 && buffered > 0 && buffered + fmin(50, duration * 0.01) >= duration;
}

- (void)watchDecode {
  if (self.closed || self.ready || self.owner.failed || self.usedSoftware || self.fallbackRequested ||
      !self.softwareDir || !self.possibleWebM || ![self fullyBuffered]) return;
  self.fallbackRequested = YES;
  [self send:@"mbPlayer.fallbackIfNeeded()"];
}

- (void)advance:(MBWebLoad *)l {
  if (l.gone || self.closed) return;
  for (MBWebCache *cached in [self.cache reverseObjectEnumerator]) {
    long long end = cached.off + (long long)cached.bytes.length;
    if (l.next < cached.off || l.next >= end) continue;
    long long n = MIN(l.end - l.next, end - l.next);
    NSData *data = [cached.bytes subdataWithRange:NSMakeRange((NSUInteger)(l.next - cached.off), (NSUInteger)n)];
    l.next += n;
    [l.task didReceiveData:data];
    if (l.gone) return;
    break;
  }
  if (l.next >= l.end) { [self end:l error:NO]; return; }
  long long len = MIN(l.end - l.next, kMaxRead);
  if ([self.mime isEqualToString:@"video/mp4"] && len < (128 << 10))
    len = MIN((long long)(128 << 10), self.total - l.next);
  [self ask:l off:l.next len:len];
}

- (void)head:(MBWebLoad *)l {
  if (l.gone || self.closed) return;
  long long start, end;
  BOOL valid = webm_range(l.range, self.total, &start, &end);
  NSMutableDictionary *h = [@{@"Content-Type": self.mime, @"Accept-Ranges": @"bytes", @"Access-Control-Allow-Origin": @"*"} mutableCopy];
  int status = valid ? (l.range.length ? 206 : 200) : 416;
  if (valid) {
    h[@"Content-Length"] = [NSString stringWithFormat:@"%lld", end - start];
    if (l.range.length) h[@"Content-Range"] = [NSString stringWithFormat:@"bytes %lld-%lld/%lld", start, end - 1, self.total];
  } else {
    h[@"Content-Length"] = @"0";
    h[@"Content-Range"] = [NSString stringWithFormat:@"bytes */%lld", self.total];
  }
  NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:l.task.request.URL statusCode:status
                                                        HTTPVersion:@"HTTP/1.1" headerFields:h];
  [l.task didReceiveResponse:response];
  l.headed = YES; l.next = start; l.end = end;
  if (!valid || [l.task.request.HTTPMethod isEqualToString:@"HEAD"]) [self end:l error:NO];
  else [self advance:l];
}

- (void)webView:(WKWebView *)web startURLSchemeTask:(id<WKURLSchemeTask>)task {
  NSString *path = task.request.URL.path;
  if (!self.closed && [path isEqualToString:@"/"]) {
    NSData *data = [self.html dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *headers = @{@"Content-Type": @"text/html; charset=utf-8", @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)data.length], @"Access-Control-Allow-Origin": @"*"};
    [task didReceiveResponse:[[NSHTTPURLResponse alloc] initWithURL:task.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:headers]];
    [task didReceiveData:data]; [task didFinish];
    return;
  }
  if (!self.closed && [path hasPrefix:@"/ogv/"] && self.softwareDir) {
    NSString *name = path.lastPathComponent;
    // Only the bundled decoder files may be read through this scheme; a video cannot name another app file.
    static NSSet<NSString *> *allowed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      NSMutableSet *files = [NSMutableSet setWithObject:@"ogv.js"];
      for (NSString *base in @[@"ogv-demuxer-ogg", @"ogv-demuxer-webm", @"ogv-decoder-audio-opus",
                               @"ogv-decoder-audio-vorbis", @"ogv-decoder-video-theora", @"ogv-decoder-video-vp8",
                               @"ogv-decoder-video-vp9", @"ogv-decoder-video-av1"]) {
        [files addObject:[base stringByAppendingString:@"-wasm.js"]];
        [files addObject:[base stringByAppendingString:@"-wasm.wasm"]];
      }
      allowed = [files copy];
    });
    NSData *data = [allowed containsObject:name] ? [NSData dataWithContentsOfFile:[self.softwareDir stringByAppendingPathComponent:name]] : nil;
    if (data) {
      NSString *type = [name hasSuffix:@".wasm"] ? @"application/wasm" : @"text/javascript";
      NSDictionary *headers = @{@"Content-Type": type, @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)data.length], @"Access-Control-Allow-Origin": @"*"};
      [task didReceiveResponse:[[NSHTTPURLResponse alloc] initWithURL:task.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:headers]];
      [task didReceiveData:data]; [task didFinish];
      return;
    }
  }
  if (self.closed || ![task.request.URL.path isEqualToString:@"/file.media"]) {
    [task didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorFileDoesNotExist userInfo:nil]];
    return;
  }
  MBWebLoad *l = [MBWebLoad new];
  l.task = task; l.range = [task.request valueForHTTPHeaderField:@"Range"];
  [self.loads addObject:l];
  if (self.total >= 0) [self head:l];
  else { l.probe = YES; [self ask:l off:0 len:1]; }
}

- (void)webView:(WKWebView *)web stopURLSchemeTask:(id<WKURLSchemeTask>)task {
  for (MBWebLoad *l in [self.loads copy]) if (l.task == task) [self drop:l];
  [self notify];
}

- (int32_t)readNext:(double *)out {
  if (self.lettingGo.count) {
    int32_t rid = self.lettingGo.firstObject.intValue;
    [self.lettingGo removeObjectAtIndex:0];
    return -rid;
  }
  while (self.pending.count) {
    MBWebRead *r = self.pending.firstObject;
    [self.pending removeObjectAtIndex:0];
    if (r.load.gone) continue;
    self.taken[@(r.rid)] = r;
    out[0] = (double)r.off; out[1] = (double)r.len;
    return r.rid;
  }
  return 0;
}

- (void)readAnswer:(int32_t)rid data:(const uint8_t *)bytes length:(long long)n total:(double)total more:(BOOL)more {
  MBWebRead *r = self.taken[@(rid)];
  if (!r || self.closed) return;
  if (!more || total == -2) [self.taken removeObjectForKey:@(rid)];
  MBWebLoad *l = r.load;
  if (total == -2 || n < 0 || n > r.len - r.got ||
      (total >= 0 && self.total >= 0 && (long long)total != self.total)) { [self fail]; return; }
  if (total >= 0) self.total = (long long)total;
  long long at = r.off + r.got;
  r.got += n;
  self.owner.answered += n;
  if (l.gone) return;
  for (long long i = 0; i < n && at + i < 4; i++) {
    unsigned shift = (unsigned)(3 - at - i) * 8;
    self.firstBytes = (self.firstBytes & ~(0xffU << shift)) | ((uint32_t)bytes[i] << shift);
    self.firstMask |= 1U << (unsigned)(at + i);
  }
  if (self.firstMask == 15 && self.firstBytes == 0x1a45dfa3) self.possibleWebM = YES;
  if (r.cache && n) [r.cache.bytes appendBytes:bytes length:(NSUInteger)n];
  if (!l.probe && n) {
    long long start = MAX(l.next, at), end = MIN(l.end, at + n);
    if (end > start) {
      l.next = end;
      [l.task didReceiveData:[NSData dataWithBytes:bytes + (start - at) length:(NSUInteger)(end - start)]];
    }
  }
  if (!more) {
    if (l.probe) {
      l.probe = NO;
      if (self.total < 0) { [self fail]; return; }
      [self head:l];
    } else if (!r.got && l.next < l.end) {
      [self fail];
      return;
    } else {
      [self advance:l];
    }
  }
  [self watchDecode];
  [self notify];
}

- (void)send:(NSString *)command {
  if (self.closed) return;
  if (!self.pageReady) { [self.commands addObject:command]; return; }
  [self.owner.web evaluateJavaScript:command completionHandler:nil];
}

- (void)webView:(WKWebView *)web didFinishNavigation:(WKNavigation *)navigation {
  if (self.closed) return;
  self.pageReady = YES;
  for (NSString *s in self.commands) [web evaluateJavaScript:s completionHandler:nil];
  [self.commands removeAllObjects];
}

- (void)webView:(WKWebView *)web didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error { [self fail]; }
- (void)webView:(WKWebView *)web didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error { [self fail]; }
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)web { [self fail]; }

- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
  MBNative *v = self.owner;
  if (!v || self.closed || ![message.body isKindOfClass:NSDictionary.class]) return;
  NSDictionary *s = message.body;
  if ([s[@"type"] isEqual:@"grabReady"]) {
    [self grab];
  } else if ([s[@"type"] isEqual:@"grabFailed"]) {
    [self finishGrab:nil];
  } else if ([s[@"type"] isEqual:@"soft"]) {
    self.usedSoftware = YES; self.ready = NO; self.fallbackRequested = NO;
    [self notify];
  } else if ([s[@"type"] isEqual:@"nativeReady"]) {
    self.fallbackRequested = NO;
    [self notify];
  } else if ([s[@"type"] isEqual:@"state"]) {
    self.state = s;
    if (!v.placed && [s[@"width"] doubleValue] > 0 && [s[@"height"] doubleValue] > 0)
      v.web.frame = CGRectMake(0, 0, [s[@"width"] doubleValue], [s[@"height"] doubleValue]);
    int error = [s[@"error"] intValue];
    if (error && !v.failed) {
      if (!self.usedSoftware && self.softwareDir && self.possibleWebM && [self.mime isEqualToString:@"video/webm"]) {
        if (!self.fallbackRequested) {
          self.fallbackRequested = YES;
          [self send:@"mbPlayer.fallback()"];
        }
      } else {
        [self failWithCode:error == 4 ? -4 : error == 3 ? -3 : -1];
      }
    } else if ([s[@"ready"] boolValue] && !v.failed) {
      self.ready = YES;
      [v tell:1];
    } else {
      [self watchDecode];
    }
    [self notify];
  }
}

- (int32_t)info:(double *)out {
  NSDictionary *s = self.state;
  out[0] = s ? [s[@"duration"] doubleValue] : -1;
  out[1] = [s[@"position"] doubleValue];
  out[2] = [s[@"playing"] boolValue] ? 1 : 0;
  out[3] = [s[@"width"] doubleValue]; out[4] = [s[@"height"] doubleValue];
  out[5] = self.owner.answered;
  // Once the first frame is available it remains the picture during a seek or buffering, like AVPlayerLayer.
  out[6] = self.ready ? 1 : 0;
  out[7] = [s[@"waiting"] boolValue] && (self.pending.count || self.taken.count) ? 1 : 0;
  out[8] = [s[@"buffered"] doubleValue];
  out[9] = [s[@"ended"] boolValue] ? 1 : 0;
  return self.owner.failed ? (self.owner.playerFailure ?: -1) : self.ready ? 1 : 0;
}

- (void)control:(int32_t)op value:(double)value {
  if (self.closed) return;
  if (!isfinite(value)) value = 0;
  switch (op) {
    case 1: [self send:@"mbPlayer.play()"]; break;
    case 2: [self send:@"mbPlayer.pause()"]; break;
    case 3: case 11: [self send:[NSString stringWithFormat:@"mbPlayer.seek(%.6f)", MAX(0, value)]]; break;
    case 4: if (value > 0) [self send:[NSString stringWithFormat:@"mbPlayer.rate(%.6f)", value]]; break;
    case 10: [self send:[NSString stringWithFormat:@"mbPlayer.volume(%.6f)", fmax(0, fmin(1, value))]]; break;
    case 20: self.owner.frames = @""; mb_host_request_frame(); break;
    case 21: case 22:
      self.owner.still = nil; self.owner.stillState = 1;
      self.grabbing = YES; self.grabPNG = op == 21; self.grabSide = op == 22 ? MAX(1, value) : 0;
      [self send:[NSString stringWithFormat:@"mbPlayer.grab(%.6f)", op == 21 ? MAX(0, value) : -1.0]];
      break;
  }
}

- (void)finishGrab:(NSData *)data {
  MBNative *v = self.owner;
  if (!v || !self.grabbing) return;
  self.grabbing = NO;
  [self send:@"mbPlayer.endGrab()"];
  v.still = data.length ? data : nil;
  v.stillState = data.length ? 2 : -1;
  mb_host_outside(MB_OUTSIDE_GRAB, v.vid, data.length ? 1 : -1);
  mb_host_request_frame();
}

// WKWebView's native snapshot includes its composited video even for an app-supplied scheme. Fit it to the video's
// own size (or the requested thumbnail bound), so a Retina window does not change the saved image's pixel dimensions.
- (void)grab {
  MBNative *v = self.owner;
  if (!v || self.closed || !self.grabbing) return;
  double w = [self.state[@"width"] doubleValue], h = [self.state[@"height"] doubleValue];
  if (w <= 0 || h <= 0 || v.web.frame.size.width <= 0 || v.web.frame.size.height <= 0) {
    [self finishGrab:nil]; return;
  }
  double k = self.grabSide > 0 ? fmin(1, self.grabSide / fmax(w, h)) : 1;
  size_t tw = MAX((size_t)1, (size_t)llround(w * k)), th = MAX((size_t)1, (size_t)llround(h * k));
  WKSnapshotConfiguration *config = [WKSnapshotConfiguration new];
  config.snapshotWidth = @(tw);
  __weak MBWebVideo *weak = self;
  [v.web takeSnapshotWithConfiguration:config completionHandler:^(PImage *picture, NSError *error) {
    MBWebVideo *me = weak;
    if (!me || me.closed || !me.grabbing) return;
#if TARGET_OS_OSX
    CGImageRef source = [picture CGImageForProposedRect:NULL context:nil hints:nil];
#else
    CGImageRef source = picture.CGImage;
#endif
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = source ? CGBitmapContextCreate(NULL, tw, th, 8, 0, cs,
        kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little) : NULL;
    CGColorSpaceRelease(cs);
    CGImageRef image = NULL;
    if (context) {
      CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
      CGContextDrawImage(context, CGRectMake(0, 0, tw, th), source);
      image = CGBitmapContextCreateImage(context);
      CGContextRelease(context);
    }
    NSMutableData *data = image ? [NSMutableData new] : nil;
    CGImageDestinationRef dst = image ? CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,
        me.grabPNG ? CFSTR("public.png") : CFSTR("public.jpeg"), 1, NULL) : NULL;
    if (dst) {
      CGImageDestinationAddImage(dst, image, NULL);
      if (!CGImageDestinationFinalize(dst)) data = nil;
      CFRelease(dst);
    } else data = nil;
    if (image) CGImageRelease(image);
    [me finishGrab:data];
  }];
}

- (void)refreshSnap {
  MBNative *v = self.owner;
  if (!v || self.closed || !self.pageReady || v.snapping) return;
  v.snapping = YES;
  __weak MBWebVideo *weak = self;
  [v.web takeSnapshotWithConfiguration:nil completionHandler:^(PImage *picture, NSError *error) {
    MBWebVideo *me = weak;
    MBNative *owner = me.owner;
    if (!owner) return;
    owner.snapping = NO;
    if (!me.closed && picture) owner.snap = picture;
    mb_host_request_frame();
  }];
}

- (void)close {
  if (self.closed) return;
  for (MBWebLoad *l in [self.loads copy]) [self end:l error:YES];
  self.closed = YES;
  [self.owner.web stopLoading];
  self.owner.web.navigationDelegate = nil;
  [self.owner.web.configuration.userContentController removeScriptMessageHandlerForName:@"mbvideo"];
}

@end

static void set_up_web_video(MBNative *v, NSString *mime) {
  MBWebVideo *video = [MBWebVideo new];
  video.owner = v; video.total = v.total; video.mime = mime;
  NSString *bundled = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"ogv"];
  NSString *fromEnv = NSProcessInfo.processInfo.environment[@"MBUI_OGV_DIR"];
  NSString *dir = fromEnv.length ? fromEnv : bundled;
  if (dir.length && [[NSFileManager defaultManager] fileExistsAtPath:[dir stringByAppendingPathComponent:@"ogv.js"]]) video.softwareDir = dir;
  BOOL softStart = [mime isEqualToString:@"video/ogg"];
  BOOL softPossible = video.softwareDir && (softStart || [mime isEqualToString:@"video/webm"]);
  video.usedSoftware = softStart;
  NSString *prefix = [NSString stringWithFormat:@"<script>window.mbStartSoft=%@;window.mbCanSoft=%@</script>",
                                                softStart ? @"true" : @"false", softPossible ? @"true" : @"false"];
  video.html = [kWebVideoHTML stringByReplacingOccurrencesOfString:@"<script>\n" withString:[prefix stringByAppendingString:@"<script>\n"]];
  video.loads = [NSMutableArray new]; video.pending = [NSMutableArray new];
  video.taken = [NSMutableDictionary new]; video.lettingGo = [NSMutableArray new]; video.commands = [NSMutableArray new];
  video.cache = [NSMutableArray new];
  v.webVideo = video;
  WKWebViewConfiguration *c = [WKWebViewConfiguration new];
  c.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
  c.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
#if TARGET_OS_IOS
  c.allowsInlineMediaPlayback = YES;
#endif
  [c setURLSchemeHandler:video forURLScheme:@"mbvideo"];
  [c.userContentController addScriptMessageHandler:video name:@"mbvideo"];
#if TARGET_OS_OSX
  WKWebView *web = [[MBWebVideoView alloc] initWithFrame:CGRectZero configuration:c];
#else
  WKWebView *web = [[WKWebView alloc] initWithFrame:CGRectZero configuration:c];
#endif
  web.navigationDelegate = video;
#if TARGET_OS_OSX
  if (@available(macOS 12.0, *)) web.underPageBackgroundColor = NSColor.blackColor;
#else
  web.userInteractionEnabled = NO;
#endif
  v.web = web; v.content = web;
  [web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"mbvideo://local/"]]];
  vlog(@"view %d: open %@ with WebKit", v.vid, mime);
}

static MBNative *open_web_video(int32_t vid, NSString *mime) {
  MBNative *v = [MBNative new];
  v.vid = vid; v.kind = 1; v.total = -1;
  set_up_web_video(v, mime);
  return v;
}
