// The core in TypeScript in Hermes, for the app (docs/core-ts.md, Android): one thread per core runs the Hermes
// runtime and its loop (tasks posted to it, timers due, microtasks drained after each); the core's script
// (client/core-ts hosts/hermes.ts, as bytecode) gets `__native`, whose calls go to the Rust shell (client/shell: HTTP,
// still.fail cloud's socket, files and core.db, TCP, iroh) and whose answers come back as tasks; what the core says to
// the app goes to Kotlin (HermesEngine.kt) through JNI. The calls for what is kept sealed (`secure.*`: the Keystore, and
// the prompt for the person) go to Kotlin instead of the shell (SecureStore.kt), answered through `complete`. A JS error that escapes, or a bug the core reports, ends the
// core as a panic ended the Rust one: `{"fatal": …}`, and the app starts another.
//
// The same engine runs the core on iOS (the React Native app, apps/mobile-rn/modules/stillfail-core/ios/CoreEngine.mm,
// which compiles this file into itself): what is the platform's is the clocks, randomness and the log below, and the
// app's side (`Edge`), JNI here under __ANDROID__ and Objective-C++ there.
#ifdef __ANDROID__
#include <jni.h>
#include <android/log.h>
#include <sys/random.h>
#else
#include <mach/mach_time.h>
#include <os/log.h>
#include <stdlib.h>
#endif
#include <pthread.h>
#include <time.h>

#include <atomic>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
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

const char* TAG = "StillFailCore";

double clockMs(clockid_t clock) {
  timespec t{};
  clock_gettime(clock, &t);
  return double(t.tv_sec) * 1000.0 + double(t.tv_nsec) / 1e6;
}

enum class Level { Debug, Info, Warn, Error };

#ifdef __ANDROID__
/// Timers run on CLOCK_BOOTTIME, which goes on while the phone sleeps: a 10 s wait begun before a sleep is over after
/// it (the Rust core's `sleep` did the same with the wall clock).
double bootMs() { return clockMs(CLOCK_BOOTTIME); }

/// `monotonic`: a clock that stops while the phone sleeps.
const clockid_t STEADY = CLOCK_MONOTONIC;

void randomBytes(char* out, size_t n) {
  for (size_t at = 0; at < n;) {
    ssize_t got = getrandom(out + at, n - at, 0);
    if (got > 0) at += size_t(got);
  }
}

void logText(Level level, const std::string& text) {
  int priority = level == Level::Error ? ANDROID_LOG_ERROR : level == Level::Warn ? ANDROID_LOG_WARN : level == Level::Info ? ANDROID_LOG_INFO : ANDROID_LOG_DEBUG;
  __android_log_print(priority, TAG, "%s", text.c_str());
}
#else
/// Timers run on mach_continuous_time, which goes on while the phone sleeps (Android's CLOCK_BOOTTIME).
double bootMs() {
  static const double msPerTick = [] {
    mach_timebase_info_data_t base{};
    mach_timebase_info(&base);
    return double(base.numer) / double(base.denom) / 1e6;
  }();
  return double(mach_continuous_time()) * msPerTick;
}

/// `monotonic`: as Android's CLOCK_MONOTONIC, a clock that stops while the phone sleeps (Darwin's CLOCK_MONOTONIC
/// does not).
const clockid_t STEADY = CLOCK_UPTIME_RAW;

void randomBytes(char* out, size_t n) { arc4random_buf(out, n); }

/// The unified log, subsystem fail.still.core (`log stream --predicate 'subsystem == "fail.still.core"'`).
void logText(Level level, const std::string& text) {
  static os_log_t log = os_log_create("fail.still.core", TAG);
  os_log_type_t type = level == Level::Error ? OS_LOG_TYPE_ERROR : level == Level::Warn ? OS_LOG_TYPE_DEFAULT : level == Level::Info ? OS_LOG_TYPE_INFO : OS_LOG_TYPE_DEBUG;
  os_log_with_type(log, type, "%{public}s", text.c_str());
}
#endif

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

/// The app's side of the engine: where what the core says goes, and who answers its `secure.*` calls (through
/// Engine::completed, from any thread). Kotlin through JNI on Android (JniEdge, below).
class Edge {
 public:
  virtual ~Edge() = default;
  /// On the loop's thread, as it begins and as it ends.
  virtual void enter() = 0;
  virtual void leave() = 0;
  virtual void say(const std::string& json) = 0;
  /// What the core says with bytes beside it (a screen view's frame: client/core-ts hosts/bridge.ts emitBytes).
  virtual void sayBytes(const std::string& json, const uint8_t* data, size_t size) = 0;
  /// False when the app did not take the call.
  virtual bool secure(uint64_t id, const std::string& op, const std::string& json, const uint8_t* data, size_t size, bool hasBytes) = 0;
};

/// What the shell answers through. Stopping the shell (sf_shell_stop, tokio's shutdown_background) does not wait for
/// what it is doing: a task already running, or a disk read on its blocking threads, still answers after the engine is
/// gone (a crash on a destroyed mutex after a core restart, 2026-10). So the shell holds this rather than the engine:
/// stopping takes the engine out of it, and an answer after that is dropped. It outlives the shell's threads, which
/// nothing waits for, so it is never freed: a few bytes per restart.
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
  Engine(std::unique_ptr<Edge> edge, std::string script, std::string url, std::string dataDir, std::string cloudOrigin, bool beta)
      : edge_(std::move(edge)), script_(std::move(script)), url_(std::move(url)), dataDir_(std::move(dataDir)), cloudOrigin_(std::move(cloudOrigin)), beta_(beta) {}

  void start() {
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    // Hermes's parser and interpreter want more native stack than a thread gets by default.
    pthread_attr_setstacksize(&attr, 8 * 1024 * 1024);
    pthread_create(&thread_, &attr, [](void* self) -> void* {
      static_cast<Engine*>(self)->run();
      return nullptr;
    }, this);
    pthread_attr_destroy(&attr);
  }

  int64_t connect() {
    int64_t client = nextClient_++;
    post([](jsi::Runtime& rt) { stillfail(rt).getPropertyAsFunction(rt, "connect").callWithThis(rt, stillfail(rt)); });
    return client;
  }

  void receive(int64_t client, std::string json) {
    post([client, json = std::move(json)](jsi::Runtime& rt) {
      stillfail(rt).getPropertyAsFunction(rt, "receive").callWithThis(rt, stillfail(rt), jsi::Value(double(client)), jsi::String::createFromUtf8(rt, json));
    });
  }

  /// Ends the loop and waits for it; the shell's answers still on their way are let go.
  void stop() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      stopping_ = true;
    }
    wake_.notify_all();
    pthread_join(thread_, nullptr);
    {
      // An answer under way finishes posting first; none reaches this engine after.
      std::lock_guard<std::mutex> lock(gate_->mutex);
      gate_->engine = nullptr;
    }
    if (shell_) sf_shell_stop(shell_);
    edge_.reset();
  }

  /// The shell's answer, from one of its threads: a task for the loop.
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

  /// A `secure.*` call, to the app: it answers on its own threads, through `completed`.
  void secure(uint64_t id, const std::string& op, const std::string& json, const uint8_t* data, size_t size, bool hasBytes) {
    if (!edge_->secure(id, op, json, data, size, hasBytes)) completed(id, "", "the app did not take " + op, "", false);
  }

  void fatal(const std::string& reason) {
    if (dead_) return;
    dead_ = true;
    logText(Level::Error, "the core failed: " + reason);
    edge_->say("{\"fatal\":" + quote(reason) + "}");
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
      if (op.rfind("secure.", 0) == 0) {
        if (hasBytes) {
          jsi::ArrayBuffer b = a[3].asObject(rt).getArrayBuffer(rt);
          secure(id, op, json, b.data(rt), b.size(rt), true);
        } else {
          secure(id, op, json, nullptr, 0, false);
        }
        return jsi::Value::undefined();
      }
      if (hasBytes) {
        jsi::ArrayBuffer b = a[3].asObject(rt).getArrayBuffer(rt);
        sf_shell_call(shell_, id, op.c_str(), reinterpret_cast<const uint8_t*>(json.data()), json.size(), b.data(rt), b.size(rt), 1);
      } else {
        sf_shell_call(shell_, id, op.c_str(), reinterpret_cast<const uint8_t*>(json.data()), json.size(), nullptr, 0, 0);
      }
      return jsi::Value::undefined();
    });
    fn("callSync", 2, [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* a, size_t) -> jsi::Value {
      std::string op = a[0].asString(rt).utf8(rt);
      std::string json = a[1].asString(rt).utf8(rt);
      size_t len = 0;
      uint8_t* out = sf_shell_call_sync(shell_, op.c_str(), reinterpret_cast<const uint8_t*>(json.data()), json.size(), &len);
      jsi::String s = jsi::String::createFromUtf8(rt, out, len);
      sf_free(out, len);
      return s;
    });
    fn("emit", 2, [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* a, size_t) -> jsi::Value {
      edge_->say(a[1].asString(rt).utf8(rt));
      return jsi::Value::undefined();
    });
    fn("emitBytes", 3, [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* a, size_t n) -> jsi::Value {
      std::string json = a[1].asString(rt).utf8(rt);
      if (n > 2 && a[2].isObject() && a[2].asObject(rt).isArrayBuffer(rt)) {
        jsi::ArrayBuffer b = a[2].asObject(rt).getArrayBuffer(rt);
        edge_->sayBytes(json, b.data(rt), b.size(rt));
      } else {
        edge_->sayBytes(json, nullptr, 0);
      }
      return jsi::Value::undefined();
    });
    fn("fatal", 1, [this](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* a, size_t) -> jsi::Value {
      fatal(a[0].isString() ? a[0].asString(rt).utf8(rt) : "the core failed");
      return jsi::Value::undefined();
    });
    fn("now", 0, [](jsi::Runtime&, const jsi::Value&, const jsi::Value*, size_t) -> jsi::Value { return jsi::Value(clockMs(CLOCK_REALTIME)); });
    fn("monotonic", 0, [](jsi::Runtime&, const jsi::Value&, const jsi::Value*, size_t) -> jsi::Value { return jsi::Value(clockMs(STEADY)); });
    fn("utcOffset", 1, [](jsi::Runtime&, const jsi::Value&, const jsi::Value* a, size_t) -> jsi::Value { return jsi::Value(double(sf_utc_offset_min(a[0].asNumber()))); });
    fn("random", 1, [](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* a, size_t) -> jsi::Value {
      size_t n = size_t(a[0].asNumber());
      std::string bytes(n, '\0');
      randomBytes(bytes.data(), n);
      return arrayBuffer(rt, bytes.data(), n);
    });
    fn("setTimer", 2, [this](jsi::Runtime&, const jsi::Value&, const jsi::Value* a, size_t) -> jsi::Value {
      uint64_t id = uint64_t(a[0].asNumber());
      double due = bootMs() + a[1].asNumber();
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
    fn("log", 2, [](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* a, size_t) -> jsi::Value {
      int level = int(a[0].asNumber());
      logText(level >= 3 ? Level::Error : level == 2 ? Level::Warn : level == 1 ? Level::Info : Level::Debug, a[1].asString(rt).utf8(rt));
      return jsi::Value::undefined();
    });
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
    edge_->enter();
    shell_ = sf_shell_start(dataDir_.c_str(), &Engine::onComplete, gate_);
    if (!shell_) {
      fatal("the core's files cannot be kept: " + dataDir_);
      return;
    }
    auto config = ::hermes::vm::RuntimeConfig::Builder().withMicrotaskQueue(true).withEnableBlockScoping(true).withIntl(true).build();
    std::unique_ptr<facebook::hermes::HermesRuntime> rt = facebook::hermes::makeHermesRuntime(config);
    try {
      install(*rt);
      rt->evaluateJavaScript(std::make_shared<Bytes>(std::move(script_)), url_);
      stillfail(*rt).getPropertyAsFunction(*rt, "start").callWithThis(*rt, stillfail(*rt), jsi::String::createFromUtf8(*rt, cloudOrigin_), jsi::Value(beta_));
      rt->drainMicrotasks();
    } catch (const std::exception& e) {
      fatal(std::string("the core did not start: ") + e.what());
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
            double left = dues_.begin()->first - bootMs();
            if (left <= 0) {
              timer = dues_.begin()->second;
              timers_.erase(timer);
              dues_.erase(dues_.begin());
              break;
            }
            // Waits on the steady clock; a sleep in between is caught up on as soon as it wakes.
            wake_.wait_for(lock, std::chrono::microseconds(int64_t(left * 1000)));
          } else {
            wake_.wait(lock);
          }
        }
        if (stopping_) break;
      }
      if (dead_) continue;
      try {
        if (task) task(*rt);
        else rt->global().getPropertyAsFunction(*rt, "__stillfail_timer").call(*rt, jsi::Value(double(timer)));
        rt->drainMicrotasks();
      } catch (const std::exception& e) {
        fatal(e.what());
      }
    }
    rt.reset();
    edge_->leave();
  }

  std::unique_ptr<Edge> edge_;
  std::string script_, url_, dataDir_, cloudOrigin_;
  bool beta_;
  void* shell_ = nullptr;
  Gate* gate_ = new Gate{{}, this};
  pthread_t thread_{};
  std::mutex mutex_;
  std::condition_variable wake_;
  std::deque<Task> tasks_;
  std::unordered_map<uint64_t, double> timers_;
  std::multimap<double, uint64_t> dues_;
  bool stopping_ = false;
  bool dead_ = false;
  std::atomic<int64_t> nextClient_{1};
};

#ifdef __ANDROID__
/// The app's side on Android: Kotlin's HermesListener (Engine.kt), called through JNI on the loop's thread.
class JniEdge : public Edge {
 public:
  JniEdge(JavaVM* vm, jobject listener) : vm_(vm), listener_(listener) {}

  ~JniEdge() override {
    JNIEnv* env = nullptr;
    if (vm_->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) == JNI_OK && env) env->DeleteGlobalRef(listener_);
  }

  void enter() override { env(); }
  void leave() override { vm_->DetachCurrentThread(); }

  /// What the core says to the app.
  void say(const std::string& json) override {
    JNIEnv* e = env();
    if (!onBytes_) {
      jclass cls = e->GetObjectClass(listener_);
      onBytes_ = e->GetMethodID(cls, "onBytes", "([B)V");
      e->DeleteLocalRef(cls);
    }
    // Modified UTF-8 is not UTF-8 (an emoji would be wrong): the bytes go as they are, made a String in Kotlin.
    jbyteArray bytes = e->NewByteArray(jsize(json.size()));
    e->SetByteArrayRegion(bytes, 0, jsize(json.size()), reinterpret_cast<const jbyte*>(json.data()));
    e->CallVoidMethod(listener_, onBytes_, bytes);
    e->DeleteLocalRef(bytes);
    if (e->ExceptionCheck()) e->ExceptionClear();
  }

  /// A `secure.*` call, to Kotlin (Engine.kt `onSecure`): it answers on its own threads, through HermesNative.complete.
  bool secure(uint64_t id, const std::string& op, const std::string& json, const uint8_t* data, size_t size, bool hasBytes) override {
    JNIEnv* e = env();
    if (!onSecure_) {
      jclass cls = e->GetObjectClass(listener_);
      onSecure_ = e->GetMethodID(cls, "onSecure", "(JLjava/lang/String;[B[B)V");
      e->DeleteLocalRef(cls);
    }
    jstring name = e->NewStringUTF(op.c_str());
    jbyteArray head = e->NewByteArray(jsize(json.size()));
    e->SetByteArrayRegion(head, 0, jsize(json.size()), reinterpret_cast<const jbyte*>(json.data()));
    jbyteArray bytes = nullptr;
    if (hasBytes) {
      bytes = e->NewByteArray(jsize(size));
      if (size > 0) e->SetByteArrayRegion(bytes, 0, jsize(size), reinterpret_cast<const jbyte*>(data));
    }
    e->CallVoidMethod(listener_, onSecure_, jlong(id), name, head, bytes);
    e->DeleteLocalRef(name);
    e->DeleteLocalRef(head);
    if (bytes) e->DeleteLocalRef(bytes);
    if (e->ExceptionCheck()) {
      e->ExceptionClear();
      return false;
    }
    return true;
  }

  /// The JSON without the bytes, and the bytes copied once, straight from the JS heap into a Java array.
  void sayBytes(const std::string& json, const uint8_t* data, size_t size) override {
    JNIEnv* e = env();
    if (!onFrame_) {
      jclass cls = e->GetObjectClass(listener_);
      onFrame_ = e->GetMethodID(cls, "onFrame", "([B[B)V");
      e->DeleteLocalRef(cls);
    }
    jbyteArray head = e->NewByteArray(jsize(json.size()));
    e->SetByteArrayRegion(head, 0, jsize(json.size()), reinterpret_cast<const jbyte*>(json.data()));
    jbyteArray bytes = e->NewByteArray(jsize(size));
    if (size > 0) e->SetByteArrayRegion(bytes, 0, jsize(size), reinterpret_cast<const jbyte*>(data));
    e->CallVoidMethod(listener_, onFrame_, head, bytes);
    e->DeleteLocalRef(head);
    e->DeleteLocalRef(bytes);
    if (e->ExceptionCheck()) e->ExceptionClear();
  }

 private:
  JNIEnv* env() {
    JNIEnv* env = nullptr;
    if (vm_->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) vm_->AttachCurrentThread(&env, nullptr);
    return env;
  }

  JavaVM* vm_;
  jobject listener_;
  jmethodID onBytes_ = nullptr;
  jmethodID onFrame_ = nullptr;
  jmethodID onSecure_ = nullptr;
};

std::string utf8(JNIEnv* env, jstring s) {
  // GetStringUTFChars is modified UTF-8: the bytes of the String's UTF-8 come from Java instead.
  jclass string = env->FindClass("java/lang/String");
  jmethodID getBytes = env->GetMethodID(string, "getBytes", "(Ljava/lang/String;)[B");
  jstring charset = env->NewStringUTF("UTF-8");
  auto bytes = static_cast<jbyteArray>(env->CallObjectMethod(s, getBytes, charset));
  jsize n = env->GetArrayLength(bytes);
  std::string out(size_t(n), '\0');
  env->GetByteArrayRegion(bytes, 0, n, reinterpret_cast<jbyte*>(out.data()));
  env->DeleteLocalRef(bytes);
  env->DeleteLocalRef(charset);
  env->DeleteLocalRef(string);
  return out;
}

#endif

}  // namespace

#ifdef __ANDROID__
extern "C" JNIEXPORT jlong JNICALL Java_fail_still_core_HermesNative_start(JNIEnv* env, jobject, jbyteArray script, jstring url, jstring dataDir, jstring cloudOrigin, jboolean beta, jobject listener) {
  JavaVM* vm = nullptr;
  env->GetJavaVM(&vm);
  jsize n = env->GetArrayLength(script);
  std::string bytes(size_t(n), '\0');
  env->GetByteArrayRegion(script, 0, n, reinterpret_cast<jbyte*>(bytes.data()));
  auto* engine = new Engine(std::make_unique<JniEdge>(vm, env->NewGlobalRef(listener)), std::move(bytes), utf8(env, url), utf8(env, dataDir), utf8(env, cloudOrigin), beta == JNI_TRUE);
  engine->start();
  return reinterpret_cast<jlong>(engine);
}

extern "C" JNIEXPORT jlong JNICALL Java_fail_still_core_HermesNative_connect(JNIEnv*, jobject, jlong handle) {
  return reinterpret_cast<Engine*>(handle)->connect();
}

extern "C" JNIEXPORT void JNICALL Java_fail_still_core_HermesNative_receive(JNIEnv* env, jobject, jlong handle, jlong client, jstring json) {
  reinterpret_cast<Engine*>(handle)->receive(client, utf8(env, json));
}

/// Kotlin's answer to a `secure.*` call (Engine.kt): `error` null when it succeeded. Never after `close`.
extern "C" JNIEXPORT void JNICALL Java_fail_still_core_HermesNative_complete(JNIEnv* env, jobject, jlong handle, jlong id, jstring json, jstring error, jbyteArray bytes) {
  std::string data;
  if (bytes) {
    jsize n = env->GetArrayLength(bytes);
    data.resize(size_t(n));
    env->GetByteArrayRegion(bytes, 0, n, reinterpret_cast<jbyte*>(data.data()));
  }
  reinterpret_cast<Engine*>(handle)->completed(uint64_t(id), json ? utf8(env, json) : std::string(), error ? utf8(env, error) : std::string(), std::move(data), bytes != nullptr);
}

extern "C" JNIEXPORT void JNICALL Java_fail_still_core_HermesNative_close(JNIEnv*, jobject, jlong handle) {
  auto* engine = reinterpret_cast<Engine*>(handle);
  engine->stop();
  delete engine;
}
#endif
