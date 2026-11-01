// The still.fail core in Hermes, for the mbui app on Windows and Android (engine.h; once still.fail's Kotlin app's
// engine, with its JNI taken out). One thread per core runs the Hermes runtime and its loop (tasks posted to it, timers
// due, microtasks drained after each); the core's script gets `__native`, whose calls go to the Rust shell
// (client/shell: HTTP, still.fail cloud's socket, files and the accounts' SQLite, TCP, iroh) and whose answers come back
// as tasks; what the core says, and the calls only the app can do (`secure.*`, `listen.*`; on Android `picked.*` too),
// go to the host (sf_engine_host). A JS error that escapes, or a bug the core reports, ends the core: `{"fatal": …}`,
// and the host starts another.
#ifdef _WIN32
#include <windows.h>
#include <bcrypt.h>
#include <process.h>
#else
#include <pthread.h>
#include <stdlib.h>
#include <sys/time.h>
#include <time.h>
#endif

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>

#include <hermes/hermes.h>
#include <jsi/jsi.h>

#include "engine.h"

namespace jsi = facebook::jsi;

extern "C" {
typedef void (*sf_complete)(void*, uint64_t, const uint8_t*, size_t, const uint8_t*, size_t, const uint8_t*, size_t, uint8_t);
void* sf_shell_start(const char* data_dir, sf_complete complete, void* ctx);
void sf_shell_call(const void* shell, uint64_t id, const char* op, const uint8_t* json, size_t json_len, const uint8_t* bytes, size_t bytes_len, uint8_t has_bytes);
uint8_t* sf_shell_call_sync(const void* shell, const char* op, const uint8_t* json, size_t json_len, size_t* out_len);
void sf_free(uint8_t* ptr, size_t len);
void sf_shell_stop(void* shell);
void sf_shell_set_say(const void* shell, void (*say)(void*, const uint8_t*, size_t, const uint8_t*, size_t), void* ctx);
void sf_shell_set_media(const void* shell, uint8_t (*media)(void*, uint64_t, uint8_t, uint8_t, uint64_t, uint64_t, const uint8_t*, size_t), void* ctx);
uint8_t sf_shell_screen_ack(const void* shell, uint64_t call, double ts);
int32_t sf_utc_offset_min(double at_ms);
#ifdef __ANDROID__
uint8_t* sf_shell_stats(size_t* out_len);
#endif
}

namespace {

/// Milliseconds since 1970 (the wall clock).
double wallMs() {
#ifdef _WIN32
  FILETIME ft;
  GetSystemTimePreciseAsFileTime(&ft);
  uint64_t t = (uint64_t(ft.dwHighDateTime) << 32) | ft.dwLowDateTime;  // 100 ns since 1601
  return double(t - 116444736000000000ULL) / 10000.0;
#else
  timeval tv{};
  gettimeofday(&tv, nullptr);
  return double(tv.tv_sec) * 1000.0 + double(tv.tv_usec) / 1000.0;
#endif
}

/// Milliseconds on a clock that never goes back.
double steadyMs() {
  using namespace std::chrono;
  return double(duration_cast<microseconds>(steady_clock::now().time_since_epoch()).count()) / 1000.0;
}

/// Milliseconds on the clock the timers run on: on Android CLOCK_BOOTTIME, which goes on while the phone sleeps (a
/// 10 s wait begun before a sleep is over after it, as the Rust core's `sleep` had it with the wall clock); elsewhere
/// the steady one.
double timerMs() {
#ifdef __ANDROID__
  timespec t{};
  clock_gettime(CLOCK_BOOTTIME, &t);
  return double(t.tv_sec) * 1000.0 + double(t.tv_nsec) / 1e6;
#else
  return steadyMs();
#endif
}

/// Whether `op` is a call only the app can do (the host's app_call), not the shell's.
bool appCall(const std::string& op) {
  if (op.rfind("secure.", 0) == 0 || op.rfind("listen.", 0) == 0) return true;
  // a file the app saved where the person keeps files, read back (the core's downloads: hosts/bridge.ts kept.read)
  if (op.rfind("kept.", 0) == 0) return true;
#ifdef __ANDROID__
  // a picked file's parts as it goes up (the app reads them from the system's content)
  if (op.rfind("picked.", 0) == 0) return true;
#endif
  return false;
}

void randomBytes(uint8_t* p, size_t n) {
#ifdef _WIN32
  BCryptGenRandom(nullptr, p, ULONG(n), BCRYPT_USE_SYSTEM_PREFERRED_RNG);
#else
  arc4random_buf(p, n);
#endif
}

/// A JSON string literal of `s` (for `{"fatal": …}`).
std::string quote(const std::string& s) {
  std::string out = "\"";
  for (unsigned char c : s) {
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (c < 0x20) {
          char buf[8];
          snprintf(buf, sizeof buf, "\\u%04x", c);
          out += buf;
        } else out += char(c);
    }
  }
  return out + "\"";
}

class Engine;

/// What the shell answers through (as on Android): stopping the shell does not wait for what it is doing, so an answer
/// can come after the engine is gone. The shell holds this rather than the engine; stopping takes the engine out of it.
/// Never freed: a few bytes per restart.
struct Gate {
  std::mutex mutex;
  Engine* engine;
};

/// Bytes the runtime keeps as its script.
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
  Engine(std::string script, std::string url, std::string dataDir, std::string cloudOrigin, bool beta, std::string os, sf_engine_host host)
      : script_(std::move(script)), url_(std::move(url)), dataDir_(std::move(dataDir)), cloudOrigin_(std::move(cloudOrigin)), os_(std::move(os)), beta_(beta), host_(host) {}

  bool start() {
#ifdef _WIN32
    // Hermes's parser and interpreter want more native stack than a thread gets by default (1 MB on Windows).
    thread_ = reinterpret_cast<HANDLE>(_beginthreadex(nullptr, 8 * 1024 * 1024, &Engine::threadMain, this, STACK_SIZE_PARAM_IS_A_RESERVATION, nullptr));
    return thread_ != nullptr;
#else
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, 8 * 1024 * 1024);
    int failed = pthread_create(&thread_, &attr, [](void* self) -> void* {
      static_cast<Engine*>(self)->run();
      return nullptr;
    }, this);
    pthread_attr_destroy(&attr);
    return failed == 0;
#endif
  }

  void receive(std::string json, std::string bytes, bool hasBytes) {
    post([this, json = std::move(json), bytes = std::move(bytes), hasBytes](jsi::Runtime& rt) {
      if (hasBytes) {
        stillfail(rt).getPropertyAsFunction(rt, "receiveBytes").callWithThis(rt, stillfail(rt), jsi::Value(client_), jsi::String::createFromUtf8(rt, json), arrayBuffer(rt, bytes.data(), bytes.size()));
      } else {
        stillfail(rt).getPropertyAsFunction(rt, "receive").callWithThis(rt, stillfail(rt), jsi::Value(client_), jsi::String::createFromUtf8(rt, json));
      }
    });
  }

  /// Ends the loop and waits for it; the shell's answers still on their way are let go.
  void stop() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      stopping_ = true;
    }
    wake_.notify_all();
#ifdef _WIN32
    WaitForSingleObject(thread_, INFINITE);
    CloseHandle(thread_);
#else
    pthread_join(thread_, nullptr);
#endif
    {
      // An answer under way finishes posting first; none reaches this engine after.
      std::lock_guard<std::mutex> lock(gate_->mutex);
      gate_->engine = nullptr;
    }
    void* shell;
    {
      std::lock_guard<std::mutex> lock(tapMutex_);
      shell = shell_;
      shell_ = nullptr;
    }
    if (shell) sf_shell_stop(shell);
  }

  /// Where the shell says a tapped remote screen's records (sf_engine_tap): set on it now if it has started, else as
  /// it starts.
  void tap(sf_engine_said say, sf_engine_media media, void* ctx) {
    std::lock_guard<std::mutex> lock(tapMutex_);
    say_ = say;
    media_ = media;
    tapCtx_ = ctx;
    tapShell();
  }

  /// (under tapMutex_) the shell told where it says a tapped view's records, once both are here
  void tapShell() {
    if (!shell_ || !say_) return;
    sf_shell_set_say(shell_, say_, tapCtx_);
    if (media_) sf_shell_set_media(shell_, media_, tapCtx_);
  }

  int screenAck(uint64_t call, double ts) {
    std::lock_guard<std::mutex> lock(tapMutex_);
    return shell_ ? sf_shell_screen_ack(shell_, call, ts) : 0;
  }

  /// An answer (the shell's, from one of its threads, or the app's): a task for the loop.
  void completed(uint64_t id, std::string json, std::string error, std::string bytes, bool hasBytes) {
    post([id, json = std::move(json), error = std::move(error), bytes = std::move(bytes), hasBytes](jsi::Runtime& rt) {
      jsi::Value j = error.empty() ? jsi::Value(jsi::String::createFromUtf8(rt, json)) : jsi::Value::null();
      jsi::Value e = error.empty() ? jsi::Value::null() : jsi::Value(jsi::String::createFromUtf8(rt, error));
      jsi::Value b = hasBytes ? jsi::Value(arrayBuffer(rt, bytes.data(), bytes.size())) : jsi::Value::undefined();
      stillfail(rt).getPropertyAsFunction(rt, "complete").callWithThis(rt, stillfail(rt), jsi::Value(double(id)), j, e, b);
    });
  }

 private:
  using Task = std::function<void(jsi::Runtime&)>;

#ifdef _WIN32
  static unsigned __stdcall threadMain(void* self) {
    static_cast<Engine*>(self)->run();
    return 0;
  }
#endif

  static jsi::Object stillfail(jsi::Runtime& rt) { return rt.global().getPropertyAsObject(rt, "__stillfail"); }

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

  void say(const std::string& json, const uint8_t* bytes, size_t size) {
    if (host_.say) host_.say(host_.ctx, json.data(), json.size(), bytes, size);
  }

  void log(int level, const std::string& text) {
    if (host_.log) host_.log(host_.ctx, level, text.data(), text.size());
    else fprintf(stderr, "[core] %s\n", text.c_str());
  }

  void fatal(const std::string& reason) {
    if (dead_) return;
    dead_ = true;
    log(3, "the core failed: " + reason);
    say("{\"fatal\":" + quote(reason) + "}", nullptr, 0);
  }

  void install(jsi::Runtime& rt) {
    jsi::Object native(rt);
    auto fn = [&](const char* name, unsigned args, jsi::HostFunctionType f) {
      native.setProperty(rt, name, jsi::Function::createFromHostFunction(rt, jsi::PropNameID::forAscii(rt, name), args, std::move(f)));
    };
    fn("call", 4, [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* a, size_t n) -> jsi::Value {
      uint64_t id = uint64_t(a[0].asNumber());
      std::string op = a[1].asString(rt).utf8(rt);
      std::string json = a[2].asString(rt).utf8(rt);
      bool hasBytes = n > 3 && a[3].isObject() && a[3].asObject(rt).isArrayBuffer(rt);
      const uint8_t* data = nullptr;
      size_t size = 0;
      static const uint8_t none = 0;
      if (hasBytes) {
        jsi::ArrayBuffer b = a[3].asObject(rt).getArrayBuffer(rt);
        data = b.size(rt) ? b.data(rt) : &none;
        size = b.size(rt);
      }
      if (appCall(op)) {
        if (host_.app_call) host_.app_call(host_.ctx, id, op.c_str(), json.data(), json.size(), hasBytes ? data : nullptr, size);
        else completed(id, "", "unsupported", "", false);
        return jsi::Value::undefined();
      }
      sf_shell_call(shell_, id, op.c_str(), reinterpret_cast<const uint8_t*>(json.data()), json.size(), data, size, hasBytes ? 1 : 0);
      return jsi::Value::undefined();
    });
    // A script more, given as bytes (bytecode, or source), run in this runtime as the core's own is: mermaid's, which the
    // app carries and gives the core as a chart is first drawn (client/core-ts/src/mermaid.ts provideMermaid).
    fn("evaluate", 2, [](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* a, size_t n) -> jsi::Value {
      jsi::ArrayBuffer b = a[0].asObject(rt).getArrayBuffer(rt);
      std::string bytes(reinterpret_cast<const char*>(b.data(rt)), b.size(rt));
      std::string name = n > 1 && a[1].isString() ? a[1].asString(rt).utf8(rt) : std::string("script");
      return rt.evaluateJavaScript(std::make_shared<Bytes>(std::move(bytes)), name);
    });
    fn("callSync", 2, [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* a, size_t) -> jsi::Value {
      std::string op = a[0].asString(rt).utf8(rt);
      std::string json = a[1].asString(rt).utf8(rt);
      // what only the app answers (its system's order of names): the host's, when it gives one
      if (host_.app_sync && op.rfind("text.", 0) == 0) {
        if (char* said = host_.app_sync(host_.ctx, op.c_str(), json.data(), json.size())) {
          jsi::String s = jsi::String::createFromUtf8(rt, reinterpret_cast<const uint8_t*>(said), std::strlen(said));
          std::free(said);
          return s;
        }
      }
      size_t len = 0;
      uint8_t* out = sf_shell_call_sync(shell_, op.c_str(), reinterpret_cast<const uint8_t*>(json.data()), json.size(), &len);
      jsi::String s = jsi::String::createFromUtf8(rt, out, len);
      sf_free(out, len);
      return s;
    });
    fn("emit", 2, [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* a, size_t) -> jsi::Value {
      say(a[1].asString(rt).utf8(rt), nullptr, 0);
      return jsi::Value::undefined();
    });
    fn("emitBytes", 3, [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* a, size_t n) -> jsi::Value {
      static const uint8_t none = 0;
      std::string json = a[1].asString(rt).utf8(rt);
      if (n > 2 && a[2].isObject() && a[2].asObject(rt).isArrayBuffer(rt)) {
        jsi::ArrayBuffer b = a[2].asObject(rt).getArrayBuffer(rt);
        say(json, b.size(rt) ? b.data(rt) : &none, b.size(rt));
      } else {
        say(json, &none, 0);
      }
      return jsi::Value::undefined();
    });
    fn("fatal", 1, [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* a, size_t) -> jsi::Value {
      fatal(a[0].isString() ? a[0].asString(rt).utf8(rt) : "the core failed");
      return jsi::Value::undefined();
    });
    fn("now", 0, [](jsi::Runtime&, const jsi::Value&, const jsi::Value*, size_t) -> jsi::Value { return jsi::Value(wallMs()); });
    fn("monotonic", 0, [](jsi::Runtime&, const jsi::Value&, const jsi::Value*, size_t) -> jsi::Value { return jsi::Value(steadyMs()); });
    fn("utcOffset", 1, [](jsi::Runtime&, const jsi::Value&, const jsi::Value* a, size_t) -> jsi::Value { return jsi::Value(double(sf_utc_offset_min(a[0].asNumber()))); });
    fn("random", 1, [](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* a, size_t) -> jsi::Value {
      size_t n = size_t(a[0].asNumber());
      std::string bytes(n, '\0');
      if (n) randomBytes(reinterpret_cast<uint8_t*>(bytes.data()), n);
      return arrayBuffer(rt, bytes.data(), n);
    });
    fn("setTimer", 2, [this](jsi::Runtime&, const jsi::Value&, const jsi::Value* a, size_t) -> jsi::Value {
      uint64_t id = uint64_t(a[0].asNumber());
      double due = timerMs() + a[1].asNumber();
      std::lock_guard<std::mutex> lock(mutex_);
      timers_[id] = due;
      dues_.emplace(due, id);
      return jsi::Value::undefined();
    });
    fn("clearTimer", 1, [this](jsi::Runtime&, const jsi::Value&, const jsi::Value* a, size_t) -> jsi::Value {
      std::lock_guard<std::mutex> lock(mutex_);
      timers_.erase(uint64_t(a[0].asNumber()));
      return jsi::Value::undefined();
    });
    fn("log", 2, [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* a, size_t) -> jsi::Value {
      log(int(a[0].asNumber()), a[1].asString(rt).utf8(rt));
      return jsi::Value::undefined();
    });
    native.setProperty(rt, "os", jsi::String::createFromUtf8(rt, os_));
    rt.global().setProperty(rt, "__native", native);
  }

  static void onComplete(void* ctx, uint64_t id, const uint8_t* json, size_t jl, const uint8_t* error, size_t el, const uint8_t* bytes, size_t bl, uint8_t has) {
    auto* gate = static_cast<Gate*>(ctx);
    std::lock_guard<std::mutex> lock(gate->mutex);
    Engine* self = gate->engine;
    if (!self) return;
    self->completed(id, std::string(reinterpret_cast<const char*>(json), jl), std::string(reinterpret_cast<const char*>(error), el),
                    has ? std::string(reinterpret_cast<const char*>(bytes), bl) : std::string(), has != 0);
  }

  void run() {
    if (host_.thread) host_.thread(host_.ctx);
    double t0 = steadyMs();
    void* shell = sf_shell_start(dataDir_.c_str(), &Engine::onComplete, gate_);
    {
      std::lock_guard<std::mutex> lock(tapMutex_);
      shell_ = shell;
      tapShell();
    }
    if (!shell_) {
      fatal("the core's files cannot be kept: " + dataDir_);
    } else if (host_.shell) {
      // (what the host asks of the shell itself: a remote screen's frames, past the core's JS)
      host_.shell(host_.ctx, shell_);
    }
    std::unique_ptr<facebook::hermes::HermesRuntime> rt;
    if (!dead_) {
#ifdef __ANDROID__
      // (with Intl, which hermes-android has, and registered for sampling: sf_engine_profile)
      auto config = ::hermes::vm::RuntimeConfig::Builder().withMicrotaskQueue(true).withEnableBlockScoping(true).withIntl(true).withEnableSampleProfiling(true).build();
#else
      auto config = ::hermes::vm::RuntimeConfig::Builder().withMicrotaskQueue(true).withEnableBlockScoping(true).build();
#endif
      rt = facebook::hermes::makeHermesRuntime(config);
      try {
        double t1 = steadyMs();
        install(*rt);
        rt->evaluateJavaScript(std::make_shared<Bytes>(std::move(script_)), url_);
        double t2 = steadyMs();
        stillfail(*rt).getPropertyAsFunction(*rt, "start").callWithThis(*rt, stillfail(*rt), jsi::String::createFromUtf8(*rt, cloudOrigin_), jsi::Value(beta_), jsi::String::createFromUtf8(*rt, os_));
        client_ = stillfail(*rt).getPropertyAsFunction(*rt, "connect").callWithThis(*rt, stillfail(*rt)).asNumber();
        rt->drainMicrotasks();
        char line[160];
        snprintf(line, sizeof line, "started in Hermes: shell %.1f ms, script %.1f ms, start %.1f ms", t1 - t0, t2 - t1, steadyMs() - t2);
        log(1, line);
      } catch (const std::exception& e) {
        fatal(std::string("the core did not start: ") + e.what());
      }
    }
    for (;;) {
      Task task;
      uint64_t timer = 0;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        for (;;) {
          if (stopping_) break;
          if (!tasks_.empty()) {
            task = std::move(tasks_.front());
            tasks_.pop_front();
            break;
          }
          // The next timer still set (one cleared, or set again later, is passed over).
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
            double left = dues_.begin()->first - timerMs();
            if (left <= 0) {
              timer = dues_.begin()->second;
              timers_.erase(timer);
              dues_.erase(dues_.begin());
              break;
            }
            // (waits on the steady clock: a sleep in between is caught up on as soon as it wakes)
            wake_.wait_for(lock, std::chrono::microseconds(int64_t(left * 1000)));
          } else {
            wake_.wait(lock);
          }
        }
        if (stopping_) break;
      }
      if (dead_ || !rt) continue;
      try {
        if (task) task(*rt);
        else rt->global().getPropertyAsFunction(*rt, "__stillfail_timer").call(*rt, jsi::Value(double(timer)));
        rt->drainMicrotasks();
      } catch (const std::exception& e) {
        fatal(e.what());
      }
    }
    tasks_.clear();
    rt.reset();
  }

  std::string script_, url_, dataDir_, cloudOrigin_, os_;
  bool beta_;
  sf_engine_host host_;
  void* shell_ = nullptr;
  // where a tapped remote screen's records go (sf_engine_tap), and shell_ as it is set and let go, under tapMutex_
  std::mutex tapMutex_;
  sf_engine_said say_ = nullptr;
  sf_engine_media media_ = nullptr;
  void* tapCtx_ = nullptr;
  Gate* gate_ = new Gate{{}, this};
#ifdef _WIN32
  HANDLE thread_ = nullptr;
#else
  pthread_t thread_{};
#endif
  std::mutex mutex_;
  std::condition_variable wake_;
  std::deque<Task> tasks_;
  std::unordered_map<uint64_t, double> timers_;
  std::multimap<double, uint64_t> dues_;
  bool stopping_ = false;
  bool dead_ = false;
  double client_ = 0;
};

}  // namespace

struct sf_engine {
  std::unique_ptr<Engine> engine;
};

#ifdef __ANDROID__
/// Hermes's methods that Android answers in Java (String's normalize, localeCompare and toLocale…Case, Date's and
/// Number's toLocaleString, Intl) find their Java classes (Hermes's AndroidUnicodeUtils, its Intl ones) by FindClass
/// the first time one runs, and keep them. On the core's thread, made here and not by Java, FindClass looks in the
/// system's class loader, which has none of the app's: the class is not found and the core ends (a formula's first
/// letter: MathJax's isLatinOrGreekChar, normalize("NFD")). Each run once in a runtime of its own, on the app's thread
/// that starts the first engine (android_core.c: the UI's, or a push's), finds and keeps them for every engine after
/// (NativeLoader set up and fbjni loaded first: CoreHost.java).
static void findJavaClasses(const sf_engine_host& host) {
  static std::once_flag once;
  std::call_once(once, [&host] {
    static const std::string touch =
        "'\\u00e9'.normalize('NFD'); 'a'.localeCompare('b'); 'A'.toLocaleLowerCase(); 'a'.toLocaleUpperCase();"
        "new Date(0).toLocaleString(); (1.5).toLocaleString();"
        "new Intl.Collator().compare('a', 'b'); new Intl.DateTimeFormat().format(0); new Intl.NumberFormat().format(1);";
    try {
      auto config = ::hermes::vm::RuntimeConfig::Builder().withIntl(true).build();
      std::unique_ptr<facebook::hermes::HermesRuntime> rt = facebook::hermes::makeHermesRuntime(config);
      rt->evaluateJavaScript(std::make_shared<jsi::StringBuffer>(touch), "classes.js");
    } catch (const std::exception& e) {
      std::string why = std::string("Hermes's Java classes not found: ") + e.what();
      if (host.log) host.log(host.ctx, 3, why.data(), why.size());
    }
  });
}
#endif

extern "C" SF_ENGINE_API sf_engine* sf_engine_start(const uint8_t* script, size_t script_len, const char* script_url, const char* data_dir,
                                                    const char* cloud_origin, int beta, const char* os, const sf_engine_host* host) {
#ifdef __ANDROID__
  findJavaClasses(*host);
#endif
  auto* e = new sf_engine{std::make_unique<Engine>(std::string(reinterpret_cast<const char*>(script), script_len), script_url ? script_url : "core.hbc",
                                                   data_dir, cloud_origin, beta != 0, os ? os : "windows", *host)};
  if (!e->engine->start()) {
    delete e;
    return nullptr;
  }
  return e;
}

extern "C" SF_ENGINE_API void sf_engine_receive(sf_engine* e, const char* json, size_t len, const uint8_t* bytes, size_t blen) {
  e->engine->receive(std::string(json, len), bytes ? std::string(reinterpret_cast<const char*>(bytes), blen) : std::string(), bytes != nullptr);
}

extern "C" SF_ENGINE_API void sf_engine_complete(sf_engine* e, uint64_t id, const char* json, size_t len, const char* error, size_t elen,
                                                 const uint8_t* bytes, size_t blen) {
  e->engine->completed(id, error && elen ? std::string() : std::string(json ? json : "", json ? len : 0), error ? std::string(error, elen) : std::string(),
                      bytes ? std::string(reinterpret_cast<const char*>(bytes), blen) : std::string(), bytes != nullptr);
}

extern "C" SF_ENGINE_API void sf_engine_stop(sf_engine* e) {
  e->engine->stop();
  delete e;
}

extern "C" SF_ENGINE_API void sf_engine_tap(sf_engine* e, sf_engine_said say, sf_engine_media media, void* ctx) {
  e->engine->tap(say, media, ctx);
}

extern "C" SF_ENGINE_API int sf_engine_screen_ack(sf_engine* e, uint64_t call, double ts) {
  return e->engine->screenAck(call, ts);
}

#ifdef __ANDROID__
extern "C" SF_ENGINE_API void sf_engine_profile(int seconds, const char* path) {
  auto* root = jsi::castInterface<facebook::hermes::IHermesRootAPI>(facebook::hermes::makeHermesRootAPI());
  if (!root) return;
  root->enableSamplingProfiler();
  std::thread([root, seconds, out = std::string(path)] {
    std::this_thread::sleep_for(std::chrono::seconds(seconds));
    root->dumpSampledTraceToFile(out);
    root->disableSamplingProfiler();
  }).detach();
}

extern "C" SF_ENGINE_API char* sf_engine_shell_stats(size_t* len) {
  size_t n = 0;
  uint8_t* out = sf_shell_stats(&n);
  char* copy = static_cast<char*>(malloc(n + 1));
  if (copy) {
    std::memcpy(copy, out, n);
    copy[n] = 0;
  }
  sf_free(out, n);
  *len = copy ? n : 0;
  return copy;
}
#endif
