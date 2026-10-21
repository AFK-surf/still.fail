///|
/// The process's environment (node's), to print only when asked (scripts/android-ref.sh).
extern "js" fn android_ref_env(name : String) -> String =
  #|(n) => (typeof process !== "undefined" && process.env[n]) || ""
