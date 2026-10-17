// The core's engine for Swift (StillfailCoreModule.swift): EngineApple.cpp behind an Objective-C class.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SFCoreEngine;

/// What the core says, on the engine's thread: its JSON, and the bytes a message carries beside it (nil: none).
typedef void (^SFCoreSaid)(NSString *json, NSData *_Nullable bytes);
/// A `secure.*` call (client/core-ts hosts/bridge.ts), on the engine's thread: answer it later, from any thread, with
/// -[SFCoreEngine complete:json:error:bytes:]. `bytes`: what it carries (nil: none).
typedef void (^SFCoreSecure)(SFCoreEngine *engine, uint64_t callId, NSString *op, NSString *json, NSData *_Nullable bytes);

@interface SFCoreEngine : NSObject

/// Starts the core: `script` its bytecode (named `url`), its files in `dataDir`, against `cloudOrigin`.
- (instancetype)initWithScript:(NSData *)script
                           url:(NSString *)url
                       dataDir:(NSString *)dataDir
                   cloudOrigin:(NSString *)cloudOrigin
                          beta:(BOOL)beta
                          said:(SFCoreSaid)said
                        secure:(SFCoreSecure)secure NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// A new client of the core (a UI): the id its messages are sent with and come back to.
- (int64_t)connect;
/// A message from client `client` to the core (JSON, as client.ts posts it).
- (void)receive:(int64_t)client json:(NSString *)json;
/// The answer to a `secure.*` call: `error` nil when it succeeded. Dropped once the engine is closed.
- (void)complete:(uint64_t)callId json:(nullable NSString *)json error:(nullable NSString *)error bytes:(nullable NSData *)bytes;
/// Stops the core (its thread ends).
- (void)close;

@end

NS_ASSUME_NONNULL_END
