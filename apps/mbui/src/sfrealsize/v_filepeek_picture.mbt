// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `filePeek picture` whole on a
// workspace of real size.
///|
fn init {
  let asked =
    #|{"topic":"filePeek","station":"ws/maple","key":"k-maple-0","path":".stillfail/uploads/bench-full.png"}
  let value =
    #|{"kind":"image","path":"/Users/maple/.stillfail/sessions/chat/k-maple-0/workspace/.stillfail/uploads/bench-full.png","name":"bench-full.png","size":262144,"mtime":1791273600000,"type":"image/png","image":{"type":"image/png","picture":"1elgw9ieo3b-7hp4"},"time":{"mtime":{"at":1791273600000,"ago":"1 小时前","full":"10/6 08:00:00","until":"1 分钟内","past":true}}}
  put(asked, value)
}
