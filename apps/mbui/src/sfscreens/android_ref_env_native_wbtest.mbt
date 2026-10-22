///|
/// The process's environment (scripts/android-ref.sh: MBUI_ANDROID_REF, MBUI_ANDROID_WINDOW).
fn android_ref_env(name : String) -> String {
  @env.get_env_var(name).unwrap_or("")
}
