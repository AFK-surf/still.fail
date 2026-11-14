// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `stationUpdates` whole on a
// workspace of real size.
///|
fn init {
  let asked =
    #|{"topic":"stationUpdates","scope":"ws"}
  let value =
    #|{"items":[{"station":"ws/willow","name":"Willow","state":"offered","versionText":"0.1.7018 → 0.1.7020","canUpdate":true}],"offered":1,"labelText":"1 台 station 有新版本","titleText":"Station 更新"}
  put(asked, value)
}
