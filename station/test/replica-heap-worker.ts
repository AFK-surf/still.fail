// The export, a whole fold and a restore of a copy many times the heap they are given (replica-heap-bounded.test.ts):
// run in a worker whose heap is that small.
import { join } from "node:path";
import { parentPort, workerData } from "node:worker_threads";
import { Exporter, genDir, nothingTold, ownDir } from "../src/replica/export.ts";
import { build } from "../src/replica/restore.ts";

const { data, to, origin, home } = workerData as { data: string; to: string; origin: string; home: string };
const e = new Exporter({ db: join(data, "stillfail.db"), replica: join(data, "replica"), dataDir: data, origin, now: () => 1, batchBytes: 1 << 20 });
e.setPlaces({ home, workspaces: [{ workspace: home, name: "big" }] });
let p = e.pass(nothingTold());
while (p.more) p = e.pass(nothingTold());
const exported = p.heads[home]!;
// a chat deleted: the whole generation folded
const told = nothingTold();
told.removedSessions.push({ key: "chat:none", ws: null });
const folded = e.pass(told).heads[home]!;
e.close();
const built = build(join(to, "stillfail.db"), genDir(ownDir(join(data, "replica")), home, folded.gen), join(to, "files"), to);
parentPort!.postMessage({ batches: exported.batches.length, foldedBatches: folded.batches.length, messages: folded.messages, rows: built.rows });
