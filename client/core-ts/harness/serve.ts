// The fake cloud and station on their own (harness/measure.ts runs them apart from the core it measures).
//
//   node harness/serve.ts <port> <chats> <per>
import { FakeCloud } from "./cloud.ts";
import { FakeStation } from "./station.ts";

const [port, chats, per] = process.argv.slice(2).map(Number);
const cloud = new FakeCloud(new FakeStation(chats - 1, per));
await cloud.listen(port);
console.log("ready");
