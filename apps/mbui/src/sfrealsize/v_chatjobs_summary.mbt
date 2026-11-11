// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `chatJobs summary` whole on a
// workspace of real size.
///|
fn init {
  let asked =
    #|{"topic":"chatJobs","station":"ws/maple","session":"k-maple-0","compact":true,"summary":true}
  let value =
    #|{"jobs":[],"hasJobs":true,"servicesNote":"","jobsNote":"","allText":""}
  put(asked, value)
}
