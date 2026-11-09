// How long input takes to show on screen, measured on this Mac (still.fail's scripts/latency.sh; a drive's `latency
// MODE TEXT`, @hostapi.drive 12): from when an event arrives to when the frame showing it reached the display, as its
// drawable's presented handler tells (presentedTime). For people to read, never a check's condition: the window
// server settles in a state that lasts a run and changes from run to run, so a run is one process and runs are
// compared by their medians, two builds taken in turn (as MyGo's internal/inputlatency, whose way this is).
//
// The run's window is shown without the app made active (MBUI_LATENCY=1: mac_app.m mb_host_run), taking neither the
// keyboard nor the front from whoever works on the machine. Events come from a thread of their own at any time within
// a refresh, onto the main queue as the window server's come onto the main thread, and go to the window as AppKit's do:
//   type    a key down and up, through the window (sendEvent:, the text system, the field's insertText:), a key every
//           60 to 140 ms (each frame after a pause), into the field at the point (the run taps it first)
//   scroll  a trackpad's scroll (a continuous wheel, its phases) at the point, an event every 4 to 12 ms, 60 a gesture,
//           each gesture the other way
//   drag    the left button down at the point, moved 3 points up or down an event (30 each way), every 4 to 12 ms
//   anim    no input: what moves by itself, its frames only (how many of the refreshes show a new one)
// An event is taken to arrive as it is posted, so the time the main thread was busy counts. The frame showing it is
// the next one the main thread presents after it was handled. What it took is said as its parts: waiting for the main
// thread (queue), handling it (handle), to the frame's start (tick: the display link's next), building, laying out and
// painting it (build), a buffer of the ring and the instances into it (upload), waiting for a drawable (drawable),
// encoding and presenting (encode), and from the present to the screen (screen: the GPU, the window server's
// composite, the display). Of the frames: how long they waited for a drawable, how many more than 4 ms, what share
// of the refreshes from the first frame shown to the last showed a new one, and of the frames presented, how many
// never showed (another replaced them first). One line, "LATENCY …", then the process ends.
// MBUI_LATENCY_EVENTS (300; refreshes for anim) are measured after MBUI_LATENCY_WARMUP (30) not.

#include <pthread.h>

typedef struct {
  double arrived, handling, handled;
  int frame;  // the frame that showed it (-1: none yet)
  int measured;
} lat_event;

typedef struct {
  double start, p0, p1, p2, p3, presented;
  double shown;  // presentedTime: 0 never shown, -1 not told yet
  double told;   // when the presented handler was called
  int measured;
} lat_frame;

enum { LAT_MAX = 1 << 14 };
static lat_event lat_events[LAT_MAX];
static lat_frame lat_frames[LAT_MAX];
static int lat_nev, lat_nfr, lat_pending0;  // lat_pending0: the first event no frame has taken yet
static int lat_measuring;
static double lat_frame_start = -1;
static pthread_mutex_t lat_mu = PTHREAD_MUTEX_INITIALIZER;
static char lat_mode[16];
static double lat_x, lat_y;
static int lat_running;

// whether the run measures (MBUI_LATENCY=1): its window not made active
static int latency_run(void) {
  const char *v = getenv("MBUI_LATENCY");
  return v && v[0] == '1';
}

// a frame begins (drawFrame): what it starts from
static void lat_frame_begins(void) {
  if (lat_running) lat_frame_start = CACurrentMediaTime();
}

void mb_latency_presenting(id<CAMetalDrawable> d, double p0, double p1, double p2, double p3) {
  if (!lat_running || ![NSThread isMainThread]) return;
  double now = CACurrentMediaTime();
  pthread_mutex_lock(&lat_mu);
  if (lat_nfr >= LAT_MAX) {
    pthread_mutex_unlock(&lat_mu);
    return;
  }
  int k = lat_nfr++;
  lat_frames[k] = (lat_frame){lat_frame_start, p0, p1, p2, p3, now, -1, -1, lat_measuring};
  for (int i = lat_pending0; i < lat_nev; i++) lat_events[i].frame = k;
  lat_pending0 = lat_nev;
  pthread_mutex_unlock(&lat_mu);
  [d addPresentedHandler:^(id<MTLDrawable> shown) {
    double at = shown.presentedTime, told = CACurrentMediaTime();
    // (MBUI_LATENCY_SAY=1: the first frames' said as they are told, for a run whose frames never show)
    if (k < 8 && getenv("MBUI_LATENCY_SAY"))
      fprintf(stderr, "LATENCY frame %d presented at %.4f, told at %.4f, its present %.4f\n", k, at, CACurrentMediaTime(),
              now);
    pthread_mutex_lock(&lat_mu);
    lat_frames[k].shown = at;
    lat_frames[k].told = told;
    pthread_mutex_unlock(&lat_mu);
  }];
}

// the main thread handles an event arriving now (from the run's thread)
static void lat_inject(void (^handle)(void)) {
  double arrived = CACurrentMediaTime();
  int measured = lat_measuring;
  dispatch_async(dispatch_get_main_queue(), ^{
    double h0 = CACurrentMediaTime();
    handle();
    double h1 = CACurrentMediaTime();
    pthread_mutex_lock(&lat_mu);
    if (lat_nev < LAT_MAX) lat_events[lat_nev++] = (lat_event){arrived, h0, h1, -1, measured};
    pthread_mutex_unlock(&lat_mu);
  });
}

// on the main thread, and waited for (what is not measured: a gesture's start and end)
static void lat_on_main(void (^f)(void)) { dispatch_sync(dispatch_get_main_queue(), f); }

static void lat_sleep_ms(double ms) { usleep((useconds_t)(ms * 1000.0)); }

static double lat_between(double lo, double hi) { return lo + (hi - lo) * (arc4random_uniform(1u << 20) / (double)(1u << 20)); }

// the point (the view's, y down) in the window's
static NSPoint lat_window_point(double x, double y) { return [the_view convertPoint:NSMakePoint(x, y) toView:nil]; }

static void lat_key(NSString *c) {
  NSWindow *w = the_view.window;
  for (int k = 0; k < 2; k++) {
    NSEvent *e = [NSEvent keyEventWithType:k == 0 ? NSEventTypeKeyDown : NSEventTypeKeyUp location:NSZeroPoint
                             modifierFlags:0 timestamp:CACurrentMediaTime() windowNumber:w.windowNumber context:nil
                                characters:c charactersIgnoringModifiers:c isARepeat:NO keyCode:0];
    [w sendEvent:e];
  }
}

// a trackpad's scroll by dy points, in a phase of its gesture (kCGScrollPhase: 1 began, 2 changed, 4 ended)
static void lat_scroll(int64_t phase, int32_t dy) {
  CGEventRef ev = CGEventCreateScrollWheelEvent2(NULL, kCGScrollEventUnitPixel, 1, dy, 0, 0);
  CGEventSetIntegerValueField(ev, kCGScrollWheelEventIsContinuous, 1);
  CGEventSetIntegerValueField(ev, kCGScrollWheelEventScrollPhase, phase);
  CGEventSetIntegerValueField(ev, kCGScrollWheelEventPointDeltaAxis1, dy);
  // (a window-less event's location is the screen's, flipped by Core Graphics: its locationInWindow is this point)
  NSPoint p = lat_window_point(lat_x, lat_y);
  CGEventSetLocation(ev, CGPointMake(p.x, NSScreen.screens[0].frame.size.height - p.y));
  [the_view scrollWheel:[NSEvent eventWithCGEvent:ev]];
  CFRelease(ev);
}

static void lat_mouse(NSEventType type, double x, double y) {
  NSEvent *e = [NSEvent mouseEventWithType:type location:lat_window_point(x, y) modifierFlags:0
                                 timestamp:CACurrentMediaTime() windowNumber:the_view.window.windowNumber context:nil
                               eventNumber:0 clickCount:1 pressure:1];
  if (type == NSEventTypeLeftMouseDown) [the_view mouseDown:e];
  else if (type == NSEventTypeLeftMouseDragged) [the_view mouseDragged:e];
  else if (type == NSEventTypeLeftMouseUp) [the_view mouseUp:e];
  else [the_view mouseMoved:e];
}

static int lat_cmp(const void *a, const void *b) {
  double x = *(const double *)a, y = *(const double *)b;
  return x < y ? -1 : x > y;
}

static double lat_pct(const double *sorted, int n, double p) { return n ? sorted[(int)(p * (n - 1))] : 0; }

// what the run measured, said
static void lat_report(double refresh) {
  pthread_mutex_lock(&lat_mu);
  // A display that gives no presentedTime for most frames (a virtual one: a remote desktop's, a headless Mac's dummy
  // screen) has each frame's when its presented handler was called instead: the window server's word that it was
  // presented, a refresh or so before a real panel would show it. Said as clock=told; else clock=presented.
  int timed = 0;
  for (int i = 0; i < lat_nfr; i++) timed += lat_frames[i].shown > 0;
  int by_told = timed * 2 < lat_nfr;
  for (int i = 0; by_told && i < lat_nfr; i++)
    if (lat_frames[i].told > 0) lat_frames[i].shown = lat_frames[i].told;
  int nfr = 0, not_shown = 0, blocked = 0;
  double wait = 0;
  static double shown[LAT_MAX], total[LAT_MAX];
  int nshown = 0;
  for (int i = 0; i < lat_nfr; i++) {
    lat_frame *f = &lat_frames[i];
    if (!f->measured) continue;
    nfr++;
    double w = f->p3 - f->p2;
    wait += w * 1000;
    if (w > 0.004) blocked++;
    if (f->shown == 0) not_shown++;
    else if (f->shown > 0) shown[nshown++] = f->shown;
  }
  double parts[8] = {0};  // queue, handle, tick, build, upload, drawable, encode, screen
  int n = 0;
  for (int i = 0; i < lat_nev; i++) {
    lat_event *e = &lat_events[i];
    if (!e->measured || e->frame < 0 || lat_frames[e->frame].shown <= 0) continue;
    lat_frame *f = &lat_frames[e->frame];
    double start = fmax(f->start, e->handled);
    double at[9] = {e->arrived, e->handling, e->handled, start, f->p0, f->p2, f->p3, f->presented, f->shown};
    for (int k = 0; k < 8; k++) parts[k] += (at[k + 1] - at[k]) * 1000;
    total[n++] = (f->shown - e->arrived) * 1000;
  }
  int events = lat_nev;
  pthread_mutex_unlock(&lat_mu);
  double mean = 0;
  for (int i = 0; i < n; i++) mean += total[i];
  qsort(total, n, sizeof(double), lat_cmp);
  double new_share = 0;
  if (nshown > 1 && refresh > 0) {
    qsort(shown, nshown, sizeof(double), lat_cmp);
    int distinct = 0;
    long last = LONG_MIN;
    for (int i = 0; i < nshown; i++) {
      long r = lround(shown[i] * refresh);
      if (r != last) distinct++;
      last = r;
    }
    new_share = 100.0 * distinct / (lround((shown[nshown - 1] - shown[0]) * refresh) + 1);
  }
  double k = n ? n : 1;
  printf("LATENCY mode=%s refresh=%.0f events=%d mean=%.3f p50=%.3f p90=%.3f p99=%.3f queue=%.3f handle=%.3f "
         "tick=%.3f build=%.3f upload=%.3f drawable=%.3f encode=%.3f screen=%.3f frames=%d wait=%.3f blocked=%.2f "
         "new=%.2f notshown=%.2f posted=%d clock=%s\n",
         lat_mode, refresh, n, mean / k, lat_pct(total, n, .5), lat_pct(total, n, .9), lat_pct(total, n, .99),
         parts[0] / k, parts[1] / k, parts[2] / k, parts[3] / k, parts[4] / k, parts[5] / k, parts[6] / k, parts[7] / k,
         nfr, nfr ? wait / nfr : 0, nfr ? 100.0 * blocked / nfr : 0, new_share, nfr ? 100.0 * not_shown / nfr : 0,
         events, by_told ? "told" : "presented");
  fflush(stdout);
}

static int lat_env(const char *name, int dflt) {
  const char *v = getenv(name);
  return v && *v ? atoi(v) : dflt;
}

static void lat_run(void) {
  int events = lat_env("MBUI_LATENCY_EVENTS", 300), warmup = lat_env("MBUI_LATENCY_WARMUP", 30);
  __block double refresh = 60;
  lat_on_main(^{
    refresh = the_view.window.screen.maximumFramesPerSecond ?: 60;
    if (getenv("MBUI_LATENCY_SAY"))
      fprintf(stderr, "LATENCY window %s, occlusion %lu, screen %s at %.0f Hz\n", NSStringFromRect(the_view.window.frame).UTF8String,
              (unsigned long)the_view.window.occlusionState, the_view.window.screen.localizedName.UTF8String, refresh);
    // (the keys are typed as they are, whatever input method the machine has on: no composing)
    the_view.inputContext.allowedInputSourceLocales = @[ NSAllRomanInputSourcesLocaleIdentifier ];
  });
  // (the frames of what the step set off, at full speed first)
  lat_sleep_ms(1000);
  __block int n = 0;
  int (^next)(void) = ^int {
    if (n == warmup) lat_measuring = 1;
    n++;
    return n <= warmup + events;
  };
  const char *mode = lat_mode;
  if (strcmp(mode, "type") == 0) {
    NSString *words = @"the quick brown fox jumps over the lazy dog ";
    while (next()) {
      NSString *c = [words substringWithRange:NSMakeRange(n % words.length, 1)];
      lat_inject(^{ lat_key(c); });
      lat_sleep_ms(lat_between(60, 140));
    }
  } else if (strcmp(mode, "scroll") == 0) {
    int way = 1;
    while (n < warmup + events) {
      lat_on_main(^{ lat_scroll(1, 2 * way); });
      for (int i = 0; i < 60 && next(); i++) {
        int dy = 3 * way;
        lat_inject(^{ lat_scroll(2, dy); });
        lat_sleep_ms(lat_between(4, 12));
      }
      lat_on_main(^{ lat_scroll(4, 0); });
      way = -way;
      lat_sleep_ms(300);
    }
  } else if (strcmp(mode, "drag") == 0) {
    // (the pointer there first: what shows only under it, out)
    lat_on_main(^{ lat_mouse(NSEventTypeMouseMoved, lat_x, lat_y); });
    lat_sleep_ms(400);
    while (n < warmup + events) {
      __block double y = lat_y;
      lat_on_main(^{ lat_mouse(NSEventTypeLeftMouseDown, lat_x, y); });
      lat_sleep_ms(50);
      for (int i = 0; i < 60 && next(); i++) {
        y += i < 30 ? -3 : 3;
        double py = y;
        lat_inject(^{ lat_mouse(NSEventTypeLeftMouseDragged, lat_x, py); });
        lat_sleep_ms(lat_between(4, 12));
      }
      lat_on_main(^{ lat_mouse(NSEventTypeLeftMouseUp, lat_x, y); });
      lat_sleep_ms(300);
    }
  } else {
    // (anim: refreshes, no input)
    lat_sleep_ms(warmup * 1000.0 / refresh);
    lat_measuring = 1;
    lat_sleep_ms(events * 1000.0 / refresh);
  }
  // (the last frames reach the screen)
  lat_sleep_ms(300);
  lat_measuring = 0;
  lat_on_main(^{});
  lat_report(refresh);
  dispatch_async(dispatch_get_main_queue(), ^{ exit(0); });
}

// The drive's `latency MODE X Y`: the run started, its thread of events (the process ends with it)
static int lat_start(NSString *s) {
  char mode[16];
  double x, y;
  if (lat_running || sscanf(s.UTF8String, "%15s %lf %lf", mode, &x, &y) != 3) return 0;
  if (strcmp(mode, "type") && strcmp(mode, "scroll") && strcmp(mode, "drag") && strcmp(mode, "anim")) return 0;
  snprintf(lat_mode, sizeof lat_mode, "%s", mode);
  // (the app's points, the view's by its zoom)
  lat_x = x * window_content_zoom;
  lat_y = y * window_content_zoom;
  lat_running = 1;
  [NSThread detachNewThreadWithBlock:^{ lat_run(); }];
  return 1;
}
