// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `stationNet` whole on a
// workspace of real size.
///|
fn init {
  let asked =
    #|{"topic":"stationNet","station":"ws/maple"}
  let value =
    #|{"path":"直连","via":"direct","rtt":{"text":"23 ms","level":"ok"},"rttHistory":[18.4,25.4,19.4,26.4,20.4,27.4,21.4,28.4,22.4,29.4,23.4,30.4,24.4,18.4,25.4,19.4,26.4,20.4,27.4,21.4,28.4,22.4,29.4,23.4,30.4,24.4,18.4,25.4,19.4,26.4],"down":"18 KB/s","up":"10 KB/s","total":"今天共 ↓ 1.1 GB · ↑ 94 MB","downTotal":"1.1 GB","upTotal":"94 MB","measured":{"measuring":false,"relays":[{"name":"直连","rtt":{"text":"23 ms","level":"ok"},"current":true},{"name":"https://relay.still.fail","rtt":{"text":"61 ms","level":"ok"},"current":false},{"name":"https://relay-bj.still.fail","rtt":{"text":"38 ms","level":"ok"},"current":false},{"name":"https://relay-sg.still.fail","rtt":{"text":"84 ms","level":"ok"},"current":false},{"name":"https://relay.acme.dev","rtt":{"text":"47 ms","level":"ok"},"current":false}]},"lan":["192.168.1.20:52001","10.8.0.3:52001","[fe80::1c2a:3bff:fe4d:9a01]:52001"]}
  put(asked, value)
}
