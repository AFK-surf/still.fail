// The export's thread (work.ts): what the station tells it, one at a time, answered as each is done.
import { parentPort, workerData } from "node:worker_threads";
import { wall } from "../ops/fibers.ts";
import { ExportWork } from "./work.ts";
import type { Asked } from "./runner.ts";

const work = new ExportWork({ ...workerData, now: () => wall.now() });
let queue = Promise.resolve();

parentPort!.on("message", (m: Asked & { id: number }) => {
  queue = queue.then(async () => {
    try {
      let answer: unknown = null;
      if (m.type === "places") work.setPlaces(m.places);
      else if (m.type === "pass") answer = await work.pass(m.told);
      else if (m.type === "newGenerations") work.newGenerations(m.after);
      else if (m.type === "sources") answer = work.sources(m.hashes);
      else if (m.type === "close") {
        work.close();
        parentPort!.postMessage({ id: m.id, answer: null });
        parentPort!.close();
        return;
      }
      parentPort!.postMessage({ id: m.id, answer });
    } catch (e) {
      parentPort!.postMessage({ id: m.id, error: (e as Error).message });
    }
  });
});
