// Made by client/core-ts/test/real-size-app.test.ts (REAL_SIZE_WRITE=1): what the core sends `railCard usage` as `down`
// happens (real-size-asked.ts CAUSES), each message the ops applied to what it holds, in order.
///|
fn init {
  let asked =
    #|{"topic":"railCard","scope":"ws","place":"usage"}
  let messages =
    #|[[{"path":["days",0,"share"],"set":0.9880930347337898},{"path":["days",1,"share"],"set":0.7689555185390832},{"path":["days",3,"share"],"set":0.8559750755752975},{"path":["days",4,"share"],"set":0.8620210993892281},{"path":["days",5,"share"],"set":0.9430254796717872},{"path":["days",6,"share"],"set":0.7238879634770806},{"path":["head"],"set":"近 7 天折合 $5,973"},{"path":["rows",0,"value"],"set":"$1,045 · 17%"},{"path":["rows",1,"value"],"set":"$1,019 · 17%"},{"path":["rows",2,"value"],"set":"$968 · 16%"},{"path":["stats",0,"value"],"set":"$704"},{"path":["stats",1,"value"],"set":"5.8 亿"}]]
  put_changes(asked, "down", messages)
}
