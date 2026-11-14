// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `stationPart machineLogins` whole on a
// workspace of real size.
///|
fn init {
  let asked =
    #|{"topic":"stationPart","scope":"ws","station":"ws/maple","part":"machineLogins"}
  let value =
    #|[{"runtime":"claude","email":"me@x.com","planText":"Max 20x","usable":true,"quota":{"state":"ok","windows":[{"label":"5 小时","mark":"5H","left":40,"level":"ok","refills":"2 小时 14 分钟后刷新"},{"label":"每周","mark":"W","left":40,"level":"ok","refills":"5 天 5 小时后刷新"},{"label":"每周 · Opus","scope":"opus","mark":"Opus","left":50,"level":"ok","refills":"5 天 5 小时后刷新"},{"label":"每周 · Fable","scope":"fable","mark":"Fable","left":70,"level":"ok","refills":"5 天 5 小时后刷新"}],"resetCount":3,"resets":[{"id":"session","kind":"session","left":1,"usable":true,"title":"5 小时重置","leftText":"剩 1 次","text":"","refills":"立即恢复 5 小时额度"},{"id":"weekly","kind":"weekly","left":2,"expiries":[1791536400000,1792054800000],"usable":false,"title":"每周重置","leftText":"剩 2 次","text":"2 天 23 小时后、8 天 23 小时后到期 · 到达它能恢复的上限后才能用","refills":"立即恢复每周额度"}],"time":{"checkedAt":{"ago":"4 分钟前"}}},"offered":false},{"runtime":"codex","email":"lina@acme.dev","planText":"Pro 200","usable":true,"quota":{"state":"ok","windows":[{"label":"5 小时","mark":"5H","left":100,"level":"ok","refills":"3 小时 33 分钟后刷新"},{"label":"每周","mark":"W","left":45,"level":"ok","refills":"2 天 11 小时后刷新"}],"creditsText":"-90 积分","resetCount":0,"resets":[],"time":{"checkedAt":{"ago":"6 分钟前"}}},"offered":false}]
  put(asked, value)
}
