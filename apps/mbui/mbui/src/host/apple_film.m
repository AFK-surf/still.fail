// mbui's film on Apple's systems (src/film): a frame's instances drawn by the host's renderer offscreen and read back
// (src/host/apple_render.m, mb_render_read), written into an H.264 MP4 by AVFoundation's writer at the frame it is to
// be; and what a program run from the command line needs besides: its arguments, a line said, a file read or
// written, the main queue turned for what the host tells there (a picture decoded).
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "moonbit.h"

void mb_render_init_offscreen(double w, double h, double scale);
uint8_t *mb_render_read(const double *inst, int32_t count, double r, double g, double b, int *w, int *h);
int mb_render_snapshot(const char *path);

static NSString *ns(moonbit_string_t s) {
  return [NSString stringWithCharacters:(const unichar *)s length:(NSUInteger)Moonbit_array_length(s)];
}

static moonbit_string_t mb(NSString *s) {
  NSUInteger n = s.length;
  moonbit_string_t out = moonbit_make_string((int32_t)n, 0);
  [s getCharacters:(unichar *)out range:NSMakeRange(0, n)];
  return out;
}

static AVAssetWriter *writer;
static AVAssetWriterInput *input;
static AVAssetWriterInputPixelBufferAdaptor *adaptor;
// Write beside the destination and replace it only after the whole run succeeds. A failed take must not destroy the
// previous good one or leave a partial video where the caller expects the finished film.
static NSURL *film_destination;
static NSURL *film_temporary;
// the picture drawn last, what the next frames written are
static CVPixelBufferRef shown;
static int32_t film_w, film_h, film_fps;

// How long the writer may take to want the next frame, or to finish (s): what it has not done by then failed.
static const double writer_most = 60;

// A writer that could not be opened must not leave its temporary file or state behind.
static void mbf_discard_open(void) {
  if (writer.status == AVAssetWriterStatusWriting) [writer cancelWriting];
  if (film_temporary) [[NSFileManager defaultManager] removeItemAtURL:film_temporary error:nil];
  writer = nil;
  input = nil;
  adaptor = nil;
  film_temporary = nil;
  film_destination = nil;
}

// A film begun for `path`, `w` × `h` pixels (to even numbers, as H.264's 4:2:0 has them),
// `fps` frames a second: 1, or 0 with what went wrong said.
int32_t mbf_open(moonbit_string_t path, int32_t w, int32_t h, int32_t fps) {
  @autoreleasepool {
    NSURL *url = [NSURL fileURLWithPath:ns(path)];
    film_destination = url;
    NSString *temporary = [NSString stringWithFormat:@".%@.%@.tmp.mp4", url.lastPathComponent, NSUUID.UUID.UUIDString];
    film_temporary = [[url URLByDeletingLastPathComponent] URLByAppendingPathComponent:temporary];
    NSError *err = nil;
    writer = [[AVAssetWriter alloc] initWithURL:film_temporary fileType:AVFileTypeMPEG4 error:&err];
    if (!writer) {
      fprintf(stderr, "film: %s\n", err.localizedDescription.UTF8String);
      mbf_discard_open();
      return 0;
    }
    film_w = w & ~1;
    film_h = h & ~1;
    film_fps = fps;
    // (the renderer's pixels as a screen's: BT.709, as players take a screen's recording)
    NSDictionary *color = @{
      AVVideoColorPrimariesKey : AVVideoColorPrimaries_ITU_R_709_2,
      AVVideoTransferFunctionKey : AVVideoTransferFunction_ITU_R_709_2,
      AVVideoYCbCrMatrixKey : AVVideoYCbCrMatrix_ITU_R_709_2,
    };
    NSDictionary *settings = @{
      AVVideoCodecKey : AVVideoCodecTypeH264,
      AVVideoWidthKey : @(film_w),
      AVVideoHeightKey : @(film_h),
      AVVideoColorPropertiesKey : color,
      AVVideoCompressionPropertiesKey : @{
        AVVideoAverageBitRateKey : @(film_w * film_h * 6),
        AVVideoProfileLevelKey : AVVideoProfileLevelH264HighAutoLevel,
        AVVideoMaxKeyFrameIntervalKey : @(fps),
        AVVideoAllowFrameReorderingKey : @NO,
      },
    };
    input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:settings];
    input.expectsMediaDataInRealTime = NO;
    NSDictionary *px = @{
      (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
      (id)kCVPixelBufferWidthKey : @(film_w),
      (id)kCVPixelBufferHeightKey : @(film_h),
    };
    adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
                                                                               sourcePixelBufferAttributes:px];
    if (![writer canAddInput:input]) {
      fprintf(stderr, "film: the writer takes no H.264 of %d x %d\n", film_w, film_h);
      mbf_discard_open();
      return 0;
    }
    [writer addInput:input];
    if (![writer startWriting]) {
      fprintf(stderr, "film: %s\n", writer.error.localizedDescription.UTF8String);
      mbf_discard_open();
      return 0;
    }
    [writer startSessionAtSourceTime:kCMTimeZero];
    return 1;
  }
}

// Publish a completed take by an atomic rename, or discard an unsuccessful one. The old destination is untouched on
// failure. Both paths are in the same directory, so the rename does not cross filesystems.
int32_t mbf_finish(int32_t publish) {
  @autoreleasepool {
    if (!film_temporary || !film_destination) return 0;
    int ok = 1;
    if (publish && rename(film_temporary.fileSystemRepresentation, film_destination.fileSystemRepresentation) != 0) {
      perror("film: could not publish");
      ok = 0;
    }
    if (!publish || !ok) [[NSFileManager defaultManager] removeItemAtURL:film_temporary error:nil];
    film_temporary = nil;
    film_destination = nil;
    return ok;
  }
}

// The instances drawn offscreen and read back into a picture of the film's (the picture the next frames written
// are): 1, or 0 when nothing could be drawn or kept.
int32_t mbf_draw(const double *inst, int32_t count, double r, double g, double b) {
  @autoreleasepool {
    if (!writer) return 0;
    int w = 0, h = 0;
    uint8_t *px = mb_render_read(inst, count, r, g, b, &w, &h);
    if (!px) return 0;
    CVPixelBufferRef pb = NULL;
    if (adaptor.pixelBufferPool) CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &pb);
    if (!pb) CVPixelBufferCreate(NULL, film_w, film_h, kCVPixelFormatType_32BGRA, NULL, &pb);
    if (!pb) {
      free(px);
      return 0;
    }
    CVPixelBufferLockBaseAddress(pb, 0);
    uint8_t *dst = CVPixelBufferGetBaseAddress(pb);
    size_t bpr = CVPixelBufferGetBytesPerRow(pb);
    int rows = film_h < h ? film_h : h, cols = film_w < w ? film_w : w;
    for (int y = 0; y < rows; y++) memcpy(dst + (size_t)y * bpr, px + (size_t)y * w * 4, (size_t)cols * 4);
    CVPixelBufferUnlockBaseAddress(pb, 0);
    free(px);
    if (shown) CVPixelBufferRelease(shown);
    shown = pb;
    return 1;
  }
}

// The picture drawn last written as frame `k` (k / fps s in): 1, or 0 with what went wrong said.
int32_t mbf_put(int32_t k) {
  @autoreleasepool {
    if (!writer || !shown) return 0;
    // (the writer takes frames as its encoder has room: told on its own queue)
    double waited = 0;
    while (!input.readyForMoreMediaData && writer.status == AVAssetWriterStatusWriting && waited < writer_most) {
      usleep(1000);
      waited += 0.001;
    }
    if (!input.readyForMoreMediaData) {
      fprintf(stderr, "film: frame %d: the writer took no more (%s)\n", k,
              writer.error ? writer.error.localizedDescription.UTF8String : "no word why");
      return 0;
    }
    if (![adaptor appendPixelBuffer:shown withPresentationTime:CMTimeMake(k, film_fps)]) {
      fprintf(stderr, "film: frame %d: %s\n", k, writer.error.localizedDescription.UTF8String);
      return 0;
    }
    return 1;
  }
}

// The film ended after `frames` frames and written out whole: 1, or 0 with what went wrong said.
int32_t mbf_close(int32_t frames) {
  @autoreleasepool {
    if (!writer) return 0;
    [input markAsFinished];
    [writer endSessionAtSourceTime:CMTimeMake(frames, film_fps)];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{
      dispatch_semaphore_signal(done);
    }];
    long late = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(writer_most * NSEC_PER_SEC)));
    int ok = !late && writer.status == AVAssetWriterStatusCompleted;
    if (!ok)
      fprintf(stderr, "film: not written out (%s)\n",
              writer.error ? writer.error.localizedDescription.UTF8String : "the writer took too long");
    if (shown) CVPixelBufferRelease(shown);
    shown = NULL;
    writer = nil;
    input = nil;
    adaptor = nil;
    return ok;
  }
}

// The main run loop turned for `ms` (what the host tells on the main queue, a picture decoded, is handled).
void mbf_spin(double ms) { CFRunLoopRunInMode(kCFRunLoopDefaultMode, ms / 1000.0, false); }

// The process's environment variable `name` ("" when unset).
moonbit_string_t mbf_arg(moonbit_string_t name) {
  @autoreleasepool {
    const char *v = getenv(ns(name).UTF8String);
    return mb(v ? [NSString stringWithUTF8String:v] ?: @"" : @"");
  }
}

void mbf_say(moonbit_string_t s) {
  @autoreleasepool {
    fprintf(stderr, "%s\n", ns(s).UTF8String);
  }
}

// The file at `path` (UTF-8) as text ("" when it cannot be read).
moonbit_string_t mbf_read_text(moonbit_string_t path) {
  @autoreleasepool {
    NSString *s = [NSString stringWithContentsOfFile:ns(path) encoding:NSUTF8StringEncoding error:nil];
    return mb(s ?: @"");
  }
}

// `text` written to the file at `path` (UTF-8): 1, or 0 when it could not be.
int32_t mbf_write_text(moonbit_string_t path, moonbit_string_t text) {
  @autoreleasepool {
    return [ns(text) writeToFile:ns(path) atomically:YES encoding:NSUTF8StringEncoding error:nil] ? 1 : 0;
  }
}

// The frame drawn last as it was drawn (the renderer's own pixels, not the film's encoding of them) written to `path`
// as a PNG: 1, or 0.
int32_t mbf_snapshot(moonbit_string_t path) {
  @autoreleasepool {
    return mb_render_snapshot(ns(path).fileSystemRepresentation);
  }
}

// The machine's clock (ms, monotonic): what a bench over a Tester times the frame's work by (src/film's bench; the
// run's own clock is the Tester's).
double mbf_now_ms(void) { return CACurrentMediaTime() * 1000.0; }

void mbf_exit(int32_t code) {
  fflush(stderr);
  exit(code);
}
