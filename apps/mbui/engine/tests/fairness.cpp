// Exercise the real native task/timer loop with a timer due while host inputs continue to arrive.
#ifdef TEST_APPLE_HOST
#include "core_api.h"
#else
#include "engine.h"
#endif
#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <iterator>
#include <mutex>
#include <string>

#ifndef TEST_APPLE_HOST
extern "C" {
using complete_fn = void (*)(void*, uint64_t, const uint8_t*, size_t, const uint8_t*, size_t, const uint8_t*, size_t, uint8_t);
void* sf_shell_start(const char*, complete_fn, void*) { return reinterpret_cast<void*>(1); }
void sf_shell_call(const void*, uint64_t, const char*, const uint8_t*, size_t, const uint8_t*, size_t, uint8_t) {}
uint8_t* sf_shell_call_sync(const void*, const char*, const uint8_t*, size_t, size_t*) { return nullptr; }
void sf_free(uint8_t*, size_t) {}
void sf_shell_stop(void*) {}
void sf_shell_set_say(const void*, void (*)(void*, const uint8_t*, size_t, const uint8_t*, size_t), void*) {}
void sf_shell_set_media(const void*, uint8_t (*)(void*, uint64_t, uint8_t, uint8_t, uint64_t, uint64_t, const uint8_t*, size_t), void*) {}
uint8_t sf_shell_screen_ack(const void*, uint64_t, double) { return 0; }
int32_t sf_utc_offset_min(double) { return 0; }
}
#endif

constexpr int maxInputs = 100;
struct State {
#ifndef TEST_APPLE_HOST
  sf_engine* engine = nullptr;
#endif
  std::mutex mutex;
  std::condition_variable wake;
  int received = 0;
  int beforeTimer = -1;
  bool earlier = false;
  bool inOrder = false;
  bool done = false;
};

static void send(State& state, const char* message) {
#ifdef TEST_APPLE_HOST
  (void)state;
  mb_core_send(message, std::strlen(message), nullptr, 0);
#else
  sf_engine_receive(state.engine, message, std::strlen(message), nullptr, 0);
#endif
}

static void say(void* ctx, const char* json, size_t len, const uint8_t*, size_t) {
  auto& state = *static_cast<State*>(ctx);
  const std::string event(json, len);
  if (event == "ready") send(state, "begin");
  else if (event == "armed") send(state, "input");
  else if (event == "queue-earlier") send(state, "earlier");
  else {
    bool more = false;
    bool checkOrder = false;
    {
      std::lock_guard<std::mutex> lock(state.mutex);
      if (event == "input") {
        ++state.received;
        if (state.beforeTimer >= 0) checkOrder = true;
        else more = state.received < maxInputs;
      } else if (event == "timer") {
        state.beforeTimer = state.received;
        if (state.received == maxInputs) checkOrder = true;
      } else if (event == "earlier") {
        state.earlier = true;
      } else if (event == "later") {
        state.inOrder = state.earlier;
        state.done = true;
      }
    }
    if (more) send(state, "input");
    if (checkOrder) send(state, "order");
  }
  state.wake.notify_one();
}

#ifdef TEST_APPLE_HOST
static void appleSay(const char* json, size_t len, const uint8_t* bytes, size_t size, void* ctx) {
  say(ctx, json, len, bytes, size);
}
#endif

int main(int argc, char** argv) {
#ifdef TEST_APPLE_HOST
  if (argc != 3) return 2;
  setenv("MB_CORE_BUNDLE", argv[1], 1);
  State state;
  mb_core_start(argv[2], "http://localhost", 0, appleSay, &state);
#else
  if (argc != 2) return 2;
  std::ifstream stream(argv[1], std::ios::binary);
  std::string bytecode((std::istreambuf_iterator<char>(stream)), std::istreambuf_iterator<char>());
  if (bytecode.empty()) return 2;
  State state;
  sf_engine_host host{};
  host.ctx = &state;
  host.say = say;
  state.engine = sf_engine_start(reinterpret_cast<const uint8_t*>(bytecode.data()), bytecode.size(), "fairness-probe.hbc", ".", "http://localhost", 0, "android", &host);
  if (!state.engine) return 2;
#endif
  send(state, "start");
  int before = -1;
  int received = 0;
  bool inOrder = false;
  {
    std::unique_lock<std::mutex> lock(state.mutex);
    if (state.wake.wait_for(lock, std::chrono::seconds(15), [&] { return state.done; })) {
      before = state.beforeTimer;
      received = state.received;
      inOrder = state.inOrder;
    }
  }
#ifdef TEST_APPLE_HOST
  mb_core_stop();
#else
  sf_engine_stop(state.engine);
#endif
  std::cout << "timer_after_inputs=" << before << " total_inputs=" << received
            << " queued_input_first=" << inOrder << std::endl;
  return before >= 0 && before < maxInputs && inOrder ? 0 : 1;
}
