///|
#borrow(name)
extern "C" fn env(name : String) -> String = "mb_coredemo_env"

///|
/// The engine the core runs in (Hermes, on every native host).
extern "C" fn engine_name() -> String = "mb_coredemo_engine"

///|
/// MBUI_SECURE_TEST=1: secure.set/get/delete round-tripped through the host's own answers to the core, the outcome in
/// the log (SECURE_TEST …); 0 when this host has no such test.
extern "C" fn secure_test() -> Int = "mb_coredemo_secure_test"
