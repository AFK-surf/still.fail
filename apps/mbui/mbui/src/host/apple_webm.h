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
@property(nonatomic, copy) NSString *html;
@property(nonatomic, strong) NSMutableIndexSet *delivered;
@property(nonatomic) long long total;
@property(nonatomic) int32_t nextRid;
@property(nonatomic) BOOL pageReady, closed, primed, ready;
@property(nonatomic) BOOL grabbing, grabPNG;
@property(nonatomic) double grabSide;
- (void)control:(int32_t)op value:(double)value;
- (int32_t)info:(double *)out;
- (int32_t)readNext:(double *)out;
- (void)readAnswer:(int32_t)rid data:(const uint8_t *)bytes length:(long long)n total:(double)total more:(BOOL)more;
- (void)failWithCode:(int32_t)code;
- (void)send:(NSString *)command;
- (void)grab;
- (void)grabWhenPresented;
- (void)finishGrab:(NSData *)data;
- (void)refreshSnap;
- (void)close;
@end

// This page contains no user content. The file never gets a network URL or any script from the file. WebKit takes a
// native snapshot when the app asks for a frame; a canvas cannot read media served from a custom scheme.
// A seek can deliver a callback for a frame queued before it. Compare its media time to the target using the recent
// frame interval (one second until that interval is known), so that an old frame is not used for a capture.
// WebKit often never finishes a seek made while VP9 in MP4 is paused (#3993). There a paused seek plays muted until the
// target frame is shown and pauses on it; the app is told the target position and a paused player throughout. Until the
// seek lands it plays at a tenth of the speed, so that no frame after the old position is due and shown before it.
// WebKit sometimes presents no frame at all after such a seek while the time runs on: a second past the target, or at
// the end, it stops there rather than play the file through unseen; a grab waiting for that frame is given up by the app.
static NSString *const kWebVideoHTML =
    @"<!doctype html><meta name='viewport' content='width=device-width,initial-scale=1'>"
     "<style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#000}"
     "video{width:100%;height:100%;object-fit:fill;display:block}</style>"
     "<video id='v' playsinline preload='none'></video>"
     "<script>"
     "const playToSeek=false,quietRate=.1;"
     "const v=document.getElementById('v');let waiting=false,ticking=false,changes=0,grabRestore=null,pendingGrab=null,grabWait=null;"
     "const post=o=>window.webkit.messageHandlers.mbvideo.postMessage(o);"
     "const videoFrames=typeof v.requestVideoFrameCallback==='function'&&typeof v.cancelVideoFrameCallback==='function';"
     "let frameReady=!videoFrames,frameGeneration=0,frameRequest=null,seekTarget=null,lastFrame=null,frameStep=1;"
     "let quiet=null,held=null;"
     "const at=()=>held!==null?held:v.currentTime;"
     "function endQuiet(){if(quiet===null)return;const q=quiet;quiet=null;v.pause();v.muted=q.muted;v.playbackRate=q.rate}"
     "function loudAgain(){if(quiet===null)return;v.muted=quiet.muted;v.playbackRate=quiet.rate;quiet=null}"
     "function tryGrab(){if(pendingGrab!==null){const ms=pendingGrab;pendingGrab=null;grab(ms)}}"
     "function watchFrame(){if(!videoFrames)return;const generation=frameGeneration;"
     "frameRequest=v.requestVideoFrameCallback((_,m)=>{if(generation!==frameGeneration)return;"
     "if(seekTarget!==null&&Math.abs(m.mediaTime-seekTarget)>frameStep*1.5){watchFrame();return}"
     "if(seekTarget===null&&lastFrame!==null){const step=m.mediaTime-lastFrame;if(step>0&&step<=1)frameStep=step}"
     "lastFrame=m.mediaTime;seekTarget=null;frameReady=true;endQuiet();watchFrame();status();tryGrab()})}"
     "function seekTo(t,still){if(Math.abs(at()-t)<.001&&!v.seeking&&quiet===null)return false;"
     "if(videoFrames){frameReady=false;seekTarget=t;frameGeneration++;if(frameRequest!==null)v.cancelVideoFrameCallback(frameRequest);watchFrame()}"
     "held=null;const playing=quiet===null&&!v.paused;"
     "if(playToSeek&&still&&!playing&&!(Number.isFinite(v.duration)&&t>=v.duration-.05)){"
     "if(quiet===null){quiet={muted:v.muted,rate:v.playbackRate};v.muted=true}v.playbackRate=quietRate;held=t;v.currentTime=t;"
     "v.play().catch(()=>{endQuiet();status()});return true}"
     "endQuiet();v.currentTime=t;return true}"
     "function status(){let b=0;for(let i=0;i<v.buffered.length;i++){"
     "if(v.buffered.start(i)<=v.currentTime+.001)b=Math.max(b,v.buffered.end(i));}"
     "post({type:'state',duration:Number.isFinite(v.duration)?v.duration*1000:-1,"
     "position:Number.isFinite(at())?at()*1000:0,playing:quiet===null&&!v.paused&&!v.ended,"
     "width:v.videoWidth,height:v.videoHeight,shown:v.readyState>=2&&frameReady,ready:v.readyState>=2&&frameReady,"
     "waiting:waiting,buffered:b*1000,ended:v.ended,rate:quiet!==null?quiet.rate:v.playbackRate,error:v.error?v.error.code:0});}"
     "function tick(){if(v.paused||v.ended){ticking=false;return}status();requestAnimationFrame(tick)}"
     "function startTick(){if(!ticking){ticking=true;requestAnimationFrame(tick)}}"
     "for(const e of ['loadedmetadata','loadeddata','durationchange','progress','timeupdate','pause','seeked','ended','ratechange','volumechange'])"
     "v.addEventListener(e,status);"
     "v.addEventListener('seeked',()=>{if(!videoFrames)endQuiet();else if(quiet!==null)v.playbackRate=quiet.rate;tryGrab()});"
     "v.addEventListener('timeupdate',()=>{if(quiet!==null&&!v.seeking&&held!==null&&v.currentTime>held+1){endQuiet();status()}});"
     "v.addEventListener('ended',()=>{if(quiet!==null){endQuiet();status()}});"
     "v.addEventListener('waiting',()=>{waiting=true;status()});"
     "v.addEventListener('playing',()=>{waiting=false;status();startTick()});"
     "v.addEventListener('canplay',()=>{waiting=false;status()});"
     "v.addEventListener('error',()=>{status();if(pendingGrab!==null){pendingGrab=null;post({type:'grabFailed'})}});"
     "function grab(ms,atOnce){"
     "if(v.error){post({type:'grabFailed'});return}"
     "if(v.readyState<2){"
     "const clear=()=>{grabWait=null;for(const e of ['loadeddata','canplay','seeked'])v.removeEventListener(e,loaded);v.removeEventListener('error',failed)};"
     "const loaded=()=>{clear();grab(ms,atOnce)};"
     "const failed=()=>{clear();post({type:'grabFailed'})};"
     "for(const e of ['loadeddata','canplay','seeked'])v.addEventListener(e,loaded,{once:true});"
     "v.addEventListener('error',failed,{once:true});grabWait=clear;return;}"
     "if(ms>=0&&Math.abs(at()*1000-ms)>=1){"
     "grabRestore={time:at(),changes};"
     "pendingGrab=-1;seekTo(ms/1000,true);return;}"
     "if(!atOnce&&(v.seeking||!frameReady)){pendingGrab=ms;return;}post({type:'grabReady'});}"
     "function endGrab(){pendingGrab=null;if(grabWait)grabWait();if(grabRestore&&grabRestore.changes===changes&&!v.error)seekTo(grabRestore.time,true);grabRestore=null;}"
     "window.mbPlayer={play(){changes++;loudAgain();held=null;"
     "if(v.ended)seekTo(0);v.play().catch(()=>status());status()},"
     "pause(){changes++;endQuiet();v.pause();status()},seek(ms){changes++;seekTo(Math.max(0,Math.min(Number.isFinite(v.duration)?v.duration:Infinity,ms/1000)),true);status()},"
     "rate(r){if(quiet!==null)quiet.rate=r;else v.playbackRate=r;status()},volume(n){v.volume=n;status()},grab,endGrab};"
     "watchFrame();v.preload='auto';v.src='mbvideo://local/file.media';v.load();status();"
     "</script>";

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

// Some WebKit versions consume the whole file without an error or a first frame. Report this fact to the app; only the
// app's clock decides how long to wait. Track byte ranges actually delivered to WebKit, including out-of-order reads.
- (BOOL)fullyBuffered {
  return self.total > 0 && (unsigned long long)self.total <= NSUIntegerMax &&
         [self.delivered containsIndexesInRange:NSMakeRange(0, (NSUInteger)self.total)];
}

- (void)advance:(MBWebLoad *)l {
  if (l.gone || self.closed) return;
  for (MBWebCache *cached in [self.cache reverseObjectEnumerator]) {
    long long end = cached.off + (long long)cached.bytes.length;
    if (l.next < cached.off || l.next >= end) continue;
    long long n = MIN(l.end - l.next, end - l.next);
    NSData *data = [cached.bytes subdataWithRange:NSMakeRange((NSUInteger)(l.next - cached.off), (NSUInteger)n)];
    [self.delivered addIndexesInRange:NSMakeRange((NSUInteger)l.next, (NSUInteger)n)];
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
  if (r.cache && n) [r.cache.bytes appendBytes:bytes length:(NSUInteger)n];
  if (!l.probe && n) {
    long long start = MAX(l.next, at), end = MIN(l.end, at + n);
    if (end > start) {
      [self.delivered addIndexesInRange:NSMakeRange((NSUInteger)start, (NSUInteger)(end - start))];
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
    [self grabWhenPresented];
  } else if ([s[@"type"] isEqual:@"grabFailed"]) {
    [self finishGrab:nil];
  } else if ([s[@"type"] isEqual:@"state"]) {
    self.state = s;
    if (!v.placed && [s[@"width"] doubleValue] > 0 && [s[@"height"] doubleValue] > 0)
      v.web.frame = CGRectMake(0, 0, [s[@"width"] doubleValue], [s[@"height"] doubleValue]);
    int error = [s[@"error"] intValue];
    if (error && !v.failed) {
      [self failWithCode:error == 4 ? -4 : error == 3 ? -3 : -1];
    } else if ([s[@"ready"] boolValue] && !v.failed) {
      self.ready = YES;
      [v tell:1];
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
  return self.owner.failed ? (self.owner.playerFailure ?: -1) : self.ready ? 1 : [self fullyBuffered] ? 2 : 0;
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
      // What shows now is taken as it is: a seek that does not end must not hold a viewer closing.
      [self send:op == 21 ? [NSString stringWithFormat:@"mbPlayer.grab(%.6f)", MAX(0, value)] : @"mbPlayer.grab(-1,true)"];
      break;
    case 23:
      if (self.grabbing) {
        self.grabbing = NO; self.owner.stillState = 0;
        [self send:@"mbPlayer.endGrab()"];
      }
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

// A seek can report its new time before WebKit has composited the corresponding frame. As for a page's first
// picture (MBNative::tellDrawn), wait for WebKit's presentation event before taking the snapshot.
- (void)grabWhenPresented {
  MBNative *v = self.owner;
  if (!v || self.closed || !self.grabbing) return;
  SEL after = NSSelectorFromString(@"_doAfterNextPresentationUpdate:");
  if (![v.web respondsToSelector:after]) { [self grab]; return; }
  __weak MBWebVideo *weak = self;
  void (^presented)(void) = ^{ [weak grab]; };
  ((void (*)(id, SEL, id))objc_msgSend)(v.web, after, presented);
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
  video.html = [mime isEqualToString:@"video/mp4"]
      ? [kWebVideoHTML stringByReplacingOccurrencesOfString:@"const playToSeek=false," withString:@"const playToSeek=true,"]
      : kWebVideoHTML;
  video.delivered = [NSMutableIndexSet new];
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
