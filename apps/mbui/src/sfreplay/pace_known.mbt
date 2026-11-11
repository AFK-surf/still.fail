///|
/// The flows whose pace pass (orders: the strict pass again with run_for's frames at 7 a second, and at 120) tells
/// the core otherwise than the strict pass, by trace, at which rates: each stops at its first split (PACE-SPLIT says
/// where, message by message). Only falls: a flow that splits and is not here fails, one here that splits no more
/// fails till it is taken out. Why they split, by kind, is said below each; a cause mended a layer down may show the
/// next one further on, the same flow still here.
// kept across runs: a value
let pace_splits_known : Map[String, Array[Int]] = {}
