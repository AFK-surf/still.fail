// The core's engine on iOS (EngineApple.cpp: apps/android/core's engine.cpp with an edge of its own), for
// CoreEngine.mm. C++ only: not a public header of the pod (Swift sees CoreEngine.h).
#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <string>

namespace stillfail {

/// The app's side, called on the engine's thread.
struct EngineEdge {
  /// What the core says: its JSON, and the bytes beside it when `hasBytes`.
  std::function<void(const std::string& json, const uint8_t* bytes, size_t size, bool hasBytes)> say;
  /// A `secure.*` call, answered later through engineComplete (from any thread). False: the app did not take it.
  std::function<bool(uint64_t id, const std::string& op, const std::string& json, const uint8_t* bytes, size_t size, bool hasBytes)> secure;
};

/// Starts the engine on its own thread; its handle.
void* engineStart(EngineEdge edge, std::string script, std::string url, std::string dataDir, std::string cloudOrigin, bool beta);
/// A new client of the core: the id its messages go with.
int64_t engineConnect(void* engine);
void engineReceive(void* engine, int64_t client, std::string json);
/// The answer to a `secure.*` call: `error` empty when it succeeded. Never after engineClose.
void engineComplete(void* engine, uint64_t id, std::string json, std::string error, std::string bytes, bool hasBytes);
/// Ends the engine and waits for its thread; the handle is gone after.
void engineClose(void* engine);

}  // namespace stillfail
