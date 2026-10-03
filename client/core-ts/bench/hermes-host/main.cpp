// The Android engine (apps/android/core/src/main/cpp/engine.cpp) on a Mac, to measure the core in Hermes as the app
// runs it (docs/core-db.md, Measurements): the same Hermes (0.81.4, React Native's macOS build), the same bundle
// (scripts/hermes-bundle.ts), the same Rust shell (client/shell, built for macOS) behind the same `__native`, the same
// loop. The Hermes CLI cannot: it has no SQLite. What the app's Kotlin side does is a driver script here instead
// (drive.js), with `__bench` to read the clock, the process's memory and Hermes's heap.
//
//   hermes-host <bundle.hbc> <drive.js> <data dir>
#include <mach/mach.h>
#include <sys/random.h>
#include <time.h>

#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <deque>
#include <fstream>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <unordered_map>

#include <hermes/hermes.h>
#include <jsi/jsi.h>

namespace jsi = facebook::jsi;

extern "C" {
typedef void (*sf_complete)(void*, uint64_t, const uint8_t*, size_t, const uint8_t*, size_t, const uint8_t*, size_t, uint8_t);
void* sf_shell_start(const char* data_dir, sf_complete complete, void* ctx);
void sf_shell_call(const void* shell, uint64_t id, const char* op, const uint8_t* json, size_t json_len, const uint8_t* bytes, size_t bytes_len, uint8_t has_bytes);
uint8_t* sf_shell_call_sync(const void* shell, const char* op, const uint8_t* json, size_t json_len, size_t* out_len);
void sf_free(uint8_t* ptr, size_t len);
void sf_shell_stop(void* shell);
int32_t sf_utc_offset_min(double at_ms);
}

namespace {

double clockMs(clockid_t clock) {
  timespec t{};
  clock_gettime(clock, &t);
  return double(t.tv_sec) * 1000.0 + double(t.tv_nsec) / 1e6;
}

double residentBytes() {
  mach_task_basic_info info{};
  mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
  if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO, reinterpret_cast<task_info_t>(&info), &count) != KERN_SUCCESS) return 0;
  return double(info.resident_size);
}

std::string readFile(const char* path) {
  std::ifstream in(path, std::ios::binary);
  std::stringstream s;
  s << in.rdbuf();
  return s.str();
}

class Bytes : public jsi::Buffer {
 public:
  explicit Bytes(std::string data) : data_(std::move(data)) {}
  size_t size() const override { return data_.size(); }
  const uint8_t* data() const override { return reinterpret_cast<const uint8_t*>(data_.data()); }

 private:
  std::string data_;
};

class Engine {
 public:
  using Task = std::function<void(jsi::Runtime&)>;

  void completed(uint64_t id, std::string json, std::string error, std::string bytes, bool hasBytes) {
    post([id, json = std::move(json), error = std::move(error), bytes = std::move(bytes), hasBytes](jsi::Runtime& rt) {
      jsi::Value j = error.empty() ? jsi::Value(jsi::String::createFromUtf8(rt, json)) : jsi::Value::null();
      jsi::Value e = error.empty() ? jsi::Value::null() : jsi::Value(jsi::String::createFromUtf8(rt, error));
      jsi::Value b = hasBytes ? jsi::Value(arrayBuffer(rt, bytes.data(), bytes.size())) : jsi::Value::undefined();
      rt.global().getPropertyAsObject(rt, "__stillfail").getPropertyAsFunction(rt, "complete").call(rt, jsi::Value(double(id)), j, e, b);
    });
  }

  static void onComplete(void* ctx, uint64_t id, const uint8_t* json, size_t jl, const uint8_t* error, size_t el, const uint8_t* bytes, size_t bl, uint8_t has) {
    static_cast<Engine*>(ctx)->completed(id, std::string(reinterpret_cast<const char*>(json), jl), std::string(reinterpret_cast<const char*>(error), el),
                                         has ? std::string(reinterpret_cast<const char*>(bytes), bl) : std::string(), has != 0);
  }

  int run(const std::string& bundle, const std::string& drive, const std::string& dataDir) {
    shell_ = sf_shell_start(dataDir.c_str(), &Engine::onComplete, this);
    if (!shell_) {
      fprintf(stderr, "no shell for %s\n", dataDir.c_str());
      return 1;
    }
    auto config = ::hermes::vm::RuntimeConfig::Builder().withMicrotaskQueue(true).withEnableBlockScoping(true).withIntl(true).withEnableHermesInternal(true).build();
    rt_ = facebook::hermes::makeHermesRuntime(config);
    jsi::Runtime& rt = *rt_;
    try {
      install(rt);
      rt_->evaluateJavaScript(std::make_shared<Bytes>(bundle), "core.hbc");
      rt_->evaluateJavaScript(std::make_shared<Bytes>(drive), "drive.js");
      rt_->drainMicrotasks();
    } catch (const std::exception& e) {
      fprintf(stderr, "the core did not start: %s\n", e.what());
      return 1;
    }
    for (;;) {
      Task task;
      uint64_t timer = 0;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        for (;;) {
          if (done_) break;
          if (!tasks_.empty()) {
            task = std::move(tasks_.front());
            tasks_.pop_front();
            break;
          }
          while (!dues_.empty()) {
            auto first = dues_.begin();
            auto it = timers_.find(first->second);
            if (it == timers_.end() || it->second != first->first) {
              dues_.erase(first);
              continue;
            }
            break;
          }
          if (!dues_.empty()) {
            double left = dues_.begin()->first - clockMs(CLOCK_MONOTONIC);
            if (left <= 0) {
              timer = dues_.begin()->second;
              timers_.erase(timer);
              dues_.erase(dues_.begin());
              break;
            }
            wake_.wait_for(lock, std::chrono::microseconds(int64_t(left * 1000)));
          } else {
            wake_.wait(lock);
          }
        }
        if (done_) break;
      }
      try {
        if (task) task(rt);
        else rt.global().getPropertyAsFunction(rt, "__stillfail_timer").call(rt, jsi::Value(double(timer)));
        rt_->drainMicrotasks();
      } catch (const std::exception& e) {
        fprintf(stderr, "fatal: %s\n", e.what());
        return 1;
      }
    }
    // The shell's threads may still answer: let go without tearing the runtime down under them.
    fflush(stdout);
    _exit(0);
  }

 private:
  static jsi::Object arrayBuffer(jsi::Runtime& rt, const void* data, size_t size) {
    jsi::Object buffer = rt.global().getPropertyAsFunction(rt, "ArrayBuffer").callAsConstructor(rt, double(size)).asObject(rt);
    if (size > 0) std::memcpy(buffer.getArrayBuffer(rt).data(rt), data, size);
    return buffer;
  }

  void post(Task task) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      tasks_.push_back(std::move(task));
    }
    wake_.notify_one();
  }

  void install(jsi::Runtime& rt) {
    jsi::Object native(rt);
    auto fn = [&](jsi::Object& on, const char* name, unsigned args, jsi::HostFunctionType f) {
      on.setProperty(rt, name, jsi::Function::createFromHostFunction(rt, jsi::PropNameID::forAscii(rt, name), args, std::move(f)));
    };
    fn(native, "call", 4, [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* a, size_t n) -> jsi::Value {
      uint64_t id = uint64_t(a[0].asNumber());
      std::string op = a[1].asString(rt).utf8(rt);
      std::string json = a[2].asString(rt).utf8(rt);
      if (n > 3 && a[3].isObject() && a[3].asObject(rt).isArrayBuffer(rt)) {
        jsi::ArrayBuffer b = a[3].asObject(rt).getArrayBuffer(rt);
        sf_shell_call(shell_, id, op.c_str(), reinterpret_cast<const uint8_t*>(json.data()), json.size(), b.data(rt), b.size(rt), 1);
      } else {
        sf_shell_call(shell_, id, op.c_str(), reinterpret_cast<const uint8_t*>(json.data()), json.size(), nullptr, 0, 0);
      }
      return jsi::Value::undefined();
    });
    fn(native, "callSync", 2, [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* a, size_t) -> jsi::Value {
      std::string op = a[0].asString(rt).utf8(rt);
      std::string json = a[1].asString(rt).utf8(rt);
      size_t len = 0;
      uint8_t* out = sf_shell_call_sync(shell_, op.c_str(), reinterpret_cast<const uint8_t*>(json.data()), json.size(), &len);
      jsi::String s = jsi::String::createFromUtf8(rt, out, len);
      sf_free(out, len);
      return s;
    });
    // What the core says goes to the driver (drive.js replaces it to watch).
    fn(native, "emit", 2, [](jsi::Runtime&, const jsi::Value&, const jsi::Value*, size_t) -> jsi::Value { return jsi::Value::undefined(); });
    fn(native, "fatal", 1, [](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* a, size_t) -> jsi::Value {
      fprintf(stderr, "fatal: %s\n", a[0].isString() ? a[0].asString(rt).utf8(rt).c_str() : "?");
      return jsi::Value::undefined();
    });
    fn(native, "now", 0, [](jsi::Runtime&, const jsi::Value&, const jsi::Value*, size_t) -> jsi::Value { return jsi::Value(clockMs(CLOCK_REALTIME)); });
    fn(native, "monotonic", 0, [](jsi::Runtime&, const jsi::Value&, const jsi::Value*, size_t) -> jsi::Value { return jsi::Value(clockMs(CLOCK_MONOTONIC)); });
    fn(native, "utcOffset", 1, [](jsi::Runtime&, const jsi::Value&, const jsi::Value* a, size_t) -> jsi::Value { return jsi::Value(double(sf_utc_offset_min(a[0].asNumber()))); });
    fn(native, "random", 1, [](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* a, size_t) -> jsi::Value {
      size_t n = size_t(a[0].asNumber());
      std::string bytes(n, '\0');
      arc4random_buf(bytes.data(), n);
      return arrayBuffer(rt, bytes.data(), n);
    });
    fn(native, "setTimer", 2, [this](jsi::Runtime&, const jsi::Value&, const jsi::Value* a, size_t) -> jsi::Value {
      uint64_t id = uint64_t(a[0].asNumber());
      double due = clockMs(CLOCK_MONOTONIC) + a[1].asNumber();
      std::lock_guard<std::mutex> lock(mutex_);
      timers_[id] = due;
      dues_.emplace(due, id);
      return jsi::Value::undefined();
    });
    fn(native, "clearTimer", 1, [this](jsi::Runtime&, const jsi::Value&, const jsi::Value* a, size_t) -> jsi::Value {
      std::lock_guard<std::mutex> lock(mutex_);
      timers_.erase(uint64_t(a[0].asNumber()));
      return jsi::Value::undefined();
    });
    fn(native, "log", 2, [](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* a, size_t) -> jsi::Value {
      if (a[0].asNumber() >= 2) fprintf(stderr, "%s\n", a[1].asString(rt).utf8(rt).c_str());
      return jsi::Value::undefined();
    });
    rt.global().setProperty(rt, "__native", native);

    jsi::Object bench(rt);
    fn(bench, "now", 0, [](jsi::Runtime&, const jsi::Value&, const jsi::Value*, size_t) -> jsi::Value { return jsi::Value(clockMs(CLOCK_MONOTONIC)); });
    fn(bench, "rss", 0, [](jsi::Runtime&, const jsi::Value&, const jsi::Value*, size_t) -> jsi::Value { return jsi::Value(residentBytes()); });
    fn(bench, "gc", 0, [](jsi::Runtime& rt, const jsi::Value&, const jsi::Value*, size_t) -> jsi::Value {
      rt.instrumentation().collectGarbage("bench");
      return jsi::Value::undefined();
    });
    fn(bench, "heap", 0, [](jsi::Runtime& rt, const jsi::Value&, const jsi::Value*, size_t) -> jsi::Value {
      auto info = rt.instrumentation().getHeapInfo(false);
      auto it = info.find("hermes_allocatedBytes");
      return jsi::Value(it == info.end() ? 0.0 : double(it->second));
    });
    fn(bench, "print", 1, [](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* a, size_t) -> jsi::Value {
      printf("%s\n", a[0].asString(rt).utf8(rt).c_str());
      fflush(stdout);
      return jsi::Value::undefined();
    });
    fn(bench, "exit", 0, [this](jsi::Runtime&, const jsi::Value&, const jsi::Value*, size_t) -> jsi::Value {
      std::lock_guard<std::mutex> lock(mutex_);
      done_ = true;
      return jsi::Value::undefined();
    });
    rt.global().setProperty(rt, "__bench", bench);
  }

  std::unique_ptr<facebook::hermes::HermesRuntime> rt_;
  void* shell_ = nullptr;
  std::mutex mutex_;
  std::condition_variable wake_;
  std::deque<Task> tasks_;
  std::unordered_map<uint64_t, double> timers_;
  std::multimap<double, uint64_t> dues_;
  bool done_ = false;
};

}  // namespace

int main(int argc, char** argv) {
  if (argc < 4) {
    fprintf(stderr, "usage: hermes-host <bundle.hbc> <drive.js> <data dir>\n");
    return 2;
  }
  Engine engine;
  return engine.run(readFile(argv[1]), readFile(argv[2]), argv[3]);
}
