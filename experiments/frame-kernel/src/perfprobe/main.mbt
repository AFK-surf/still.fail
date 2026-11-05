fn now_ms() -> Double = "spectest" "now"

///|
fn main {
  @kernel.benchmark_development_runtime(now_ms)
}
