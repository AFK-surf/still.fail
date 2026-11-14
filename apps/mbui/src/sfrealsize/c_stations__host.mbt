// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `stations` as `host`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"stations","scope":"ws"}
  let messages =
    #|[[{"path":[],"key":["station"],"patch":"ws/maple","ops":[{"path":["host","meters",0,"big"],"set":"34"},{"path":["host","meters",0,"left"],"set":34},{"path":["host","meters",0,"note"],"set":"负载 13.3 · Apple M4 Max"},{"path":["host","meters",0,"percent"],"set":66},{"path":["host","meters",0,"remaining"],"set":"空闲 34%"},{"path":["host","meters",0,"total"],"set":"负载 13.3"},{"path":["host","meters",0,"value"],"set":"66%"}]}]]
  put_changes(asked, "host", messages)
}
