#import "CoreEngine.h"

#include <mutex>

#include "EngineApple.h"

namespace {

NSString *text(const std::string &utf8) {
  NSString *s = [[NSString alloc] initWithBytes:utf8.data() length:utf8.size() encoding:NSUTF8StringEncoding];
  if (s) return s;
  // Not UTF-8 after all (it always is from the core): what can be read of it.
  return [[NSString alloc] initWithData:[NSData dataWithBytes:utf8.data() length:utf8.size()] encoding:NSISOLatin1StringEncoding] ?: @"";
}

std::string utf8(NSString *_Nullable s) {
  if (!s) return std::string();
  NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
  return std::string(static_cast<const char *>(d.bytes), d.length);
}

}  // namespace

@implementation SFCoreEngine {
  void *_engine;
  /// Answers to `secure.*` go only to an engine not closed yet: -close takes this before it ends the engine.
  std::mutex _answering;
  bool _closed;
}

- (instancetype)initWithScript:(NSData *)script
                           url:(NSString *)url
                       dataDir:(NSString *)dataDir
                   cloudOrigin:(NSString *)cloudOrigin
                          beta:(BOOL)beta
                          said:(SFCoreSaid)said
                        secure:(SFCoreSecure)secure {
  if (!(self = [super init])) return nil;
  _closed = false;
  __weak SFCoreEngine *weakSelf = self;
  stillfail::EngineEdge edge;
  // On the engine's thread, which has no run loop of its own: each call drains what it made.
  edge.say = [said](const std::string &json, const uint8_t *bytes, size_t size, bool hasBytes) {
    @autoreleasepool {
      said(text(json), hasBytes ? [NSData dataWithBytes:bytes length:size] : nil);
    }
  };
  edge.secure = [secure, weakSelf](uint64_t callId, const std::string &op, const std::string &json, const uint8_t *bytes, size_t size, bool hasBytes) {
    @autoreleasepool {
      SFCoreEngine *engine = weakSelf;
      if (!engine) return false;
      secure(engine, callId, text(op), text(json), hasBytes ? [NSData dataWithBytes:bytes length:size] : nil);
      return true;
    }
  };
  std::string bytes(static_cast<const char *>(script.bytes), script.length);
  _engine = stillfail::engineStart(std::move(edge), std::move(bytes), utf8(url), utf8(dataDir), utf8(cloudOrigin), beta);
  return self;
}

- (int64_t)connect {
  return stillfail::engineConnect(_engine);
}

- (void)receive:(int64_t)client json:(NSString *)json {
  stillfail::engineReceive(_engine, client, utf8(json));
}

- (void)complete:(uint64_t)callId json:(NSString *)json error:(NSString *)error bytes:(NSData *)bytes {
  std::lock_guard<std::mutex> lock(_answering);
  if (_closed) return;
  std::string data = bytes ? std::string(static_cast<const char *>(bytes.bytes), bytes.length) : std::string();
  // An error says what went wrong: never empty (an empty one is a success to the engine).
  std::string failed = error ? (error.length ? utf8(error) : std::string("failed")) : std::string();
  stillfail::engineComplete(_engine, callId, error ? std::string() : utf8(json ?: @"{}"), std::move(failed), std::move(data), bytes != nil);
}

- (void)close {
  {
    std::lock_guard<std::mutex> lock(_answering);
    if (_closed) return;
    _closed = true;
  }
  stillfail::engineClose(_engine);
  _engine = nullptr;
}

@end
