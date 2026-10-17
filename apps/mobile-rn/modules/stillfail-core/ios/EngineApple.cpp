// The core's engine on iOS: the Android app's engine (apps/android/core/src/main/cpp/engine.cpp: Hermes running the
// core's bytecode on its own thread, its IO in the Rust shell, client/shell, linked in as a static library) compiled
// into this file, so both apps run one engine; its clocks, randomness and log are the platform's (engine.cpp, outside
// __ANDROID__). Hermes and JSI are React Native's (the hermes-engine and React-jsi pods): a second runtime beside the
// UI's. What the core says and its `secure.*` calls go to CoreEngine.mm through an EngineEdge.
#include "EngineApple.h"

#include "../../../../android/core/src/main/cpp/engine.cpp"

namespace {

class AppleEdge : public Edge {
 public:
  explicit AppleEdge(stillfail::EngineEdge edge) : edge_(std::move(edge)) {}

  void enter() override { pthread_setname_np("stillfail-core"); }
  void leave() override {}
  void say(const std::string& json) override { edge_.say(json, nullptr, 0, false); }
  void sayBytes(const std::string& json, const uint8_t* data, size_t size) override { edge_.say(json, data, size, true); }
  bool secure(uint64_t id, const std::string& op, const std::string& json, const uint8_t* data, size_t size, bool hasBytes) override {
    return edge_.secure(id, op, json, data, size, hasBytes);
  }

 private:
  stillfail::EngineEdge edge_;
};

}  // namespace

namespace stillfail {

void* engineStart(EngineEdge edge, std::string script, std::string url, std::string dataDir, std::string cloudOrigin, bool beta) {
  auto* engine = new Engine(std::make_unique<AppleEdge>(std::move(edge)), std::move(script), std::move(url), std::move(dataDir), std::move(cloudOrigin), beta);
  engine->start();
  return engine;
}

int64_t engineConnect(void* engine) { return static_cast<Engine*>(engine)->connect(); }

void engineReceive(void* engine, int64_t client, std::string json) { static_cast<Engine*>(engine)->receive(client, std::move(json)); }

void engineComplete(void* engine, uint64_t id, std::string json, std::string error, std::string bytes, bool hasBytes) {
  static_cast<Engine*>(engine)->completed(id, std::move(json), std::move(error), std::move(bytes), hasBytes);
}

void engineClose(void* engine) {
  auto* e = static_cast<Engine*>(engine);
  e->stop();
  delete e;
}

}  // namespace stillfail
