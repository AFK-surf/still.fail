///|
#borrow(name)
extern "C" fn env(name : String) -> String = "mb_coredemo_env"

///|
/// The engine the core runs in (JavaScriptCore on Apple's systems, Hermes on Android).
extern "C" fn engine_name() -> String = "mb_coredemo_engine"
