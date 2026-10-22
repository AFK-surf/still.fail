///|
extern "js" fn math_evidence() -> String =
  #|() => process.env.MATH_EVIDENCE || ""
