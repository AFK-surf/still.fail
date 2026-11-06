// A fixed worker validates and persists personal chains; the event loop never waits for signatures or SQLite locks.
import { parentPort, workerData } from "node:worker_threads";
import { admitPerson, fold, personFold } from "../cloud/lock.ts";
import { PersonChains } from "./person-chains.ts";
import type { PersonRequest } from "./person-verifier.ts";

const chains = new PersonChains(workerData.data as string);
parentPort!.on("message", (message: PersonRequest & { id: number }) => {
  try {
    if (message.kind === "snapshot") {
      const person = personFold(message.entries, message.sub);
      if (message.bindings.includes(person.genesis)) {
        const newest = chains.newest(person.genesis, message.sub, message.entries);
        if (newest !== message.entries && personFold(newest, message.sub).genesis !== person.genesis) throw new Error("another personal lock");
        const kept = chains.keep(person.genesis, newest);
        // A concurrent station process may have extended it before keep's transaction.
        if (kept !== newest && personFold(kept, message.sub).genesis !== person.genesis) throw new Error("another personal lock");
      }
      // The cloud version belongs to the received snapshot, even if a longer verified prefix is kept locally.
      // Admission always checks that longer chain again.
      parentPort!.postMessage({ id: message.id, person });
    } else {
      // The rules keep an opaque state in a WeakMap; reconstruct it here, since structured cloning a view loses it.
      const state = fold(message.workspace, null);
      const pin = state.persons.get(message.who.sub);
      if (!pin) throw new Error("no personal lock bound here");
      const newest = chains.newest(pin, message.who.sub, message.entries);
      if (personFold(newest, message.who.sub).genesis !== pin) throw new Error("another personal lock");
      const kept = chains.keep(pin, newest);
      const { role } = admitPerson(state, message.who, kept);
      parentPort!.postMessage({ id: message.id, role });
    }
  } catch (error) {
    parentPort!.postMessage({ id: message.id, error: (error as Error).message });
  }
});
