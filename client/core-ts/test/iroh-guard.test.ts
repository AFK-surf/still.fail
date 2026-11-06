// A decision can change between two Effect primitives. The test uses each real iroh adapter with a fake native
// endpoint, and asks the scheduler to yield at the first opportunity after the decision was checked.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect, Scheduler } from "effect";
import { CoreError } from "../src/error.ts";
import { Bridge, bridgeIroh } from "../src/hosts/bridge.ts";
import { wrapIroh } from "../src/iroh-bindings.ts";
import type { Iroh, IrohConnection } from "../src/iroh.ts";
import { Link } from "../src/mesh.ts";
import { utf8 } from "../src/util.ts";
import { run } from "./run.ts";

const options = { secretKey: new Uint8Array(32), relayUrls: [], lookup: false, relayOnly: false };

async function connection(iroh: Iroh): Promise<IrohConnection> {
  const endpoint = await run(iroh.bind(options));
  return run(endpoint.connect({ id: "station" }, utf8("test"), []));
}

for (const kind of ["bridge", "binding"] as const) {
  test(`${kind} checks a guarded request at the actual write boundary`, async () => {
    let allowed = true, guardCalls = 0;
    const writes: boolean[] = [];
    let iroh: Iroh;
    if (kind === "bridge") {
      let bridge: Bridge;
      const native = {
        call(id: number, op: string) {
          if (op === "istream.write") writes.push(allowed);
          const answer = op === "iroh.bind" ? { id: 1 } : op === "iroh.connect" ? { id: 2 } : op === "conn.openBi" ? { id: 3 } : {};
          const bytes = op === "istream.read" ? utf8('{"status":200}\n') : null;
          queueMicrotask(() => bridge.complete(id, JSON.stringify(answer), null, bytes));
        },
      };
      bridge = new Bridge(native as never);
      iroh = bridgeIroh(bridge);
    } else {
      const stream = {
        read: async () => utf8('{"status":200}\n'),
        write: async () => { writes.push(allowed); },
        finish: async () => {},
        stopped: async () => null,
        reset: async () => {},
      };
      const conn = { openBi: async () => stream };
      iroh = wrapIroh(async () => ({ connect: async () => conn }) as never, (bytes) => bytes);
    }
    const conn = await connection(iroh);
    const link = new Link(conn, {} as never, "", (() => Effect.succeed({})) as never, null);
    const request = link.adb({ method: "POST", path: "/admin/api/adb", headers: [] }, { op: "sign" }, () => {
      guardCalls++;
      if (guardCalls === 1) queueMicrotask(() => { allowed = false; });
      return allowed ? null : CoreError.invalid("taken back");
    });
    // The old code could check, yield here, then call the native writer after the take-back.
    const scheduler = new Scheduler.MixedScheduler();
    const normalYield = scheduler.shouldYield.bind(scheduler);
    let yielded = false;
    scheduler.shouldYield = (fiber) => {
      if (guardCalls > 0 && !yielded) { yielded = true; return true; }
      return normalYield(fiber);
    };
    const result = await Effect.runPromise(Effect.result(request), { scheduler });
    assert.equal(result._tag, "Success", "a decision still valid at handoff can send");
    assert.ok(guardCalls > 0, "the decision was checked");
    assert.ok(yielded, "the scheduler got an opportunity to yield after the check");
    assert.deepEqual(writes, [true], "no bytes were handed to the host after the take-back");

    const after = await run(conn.openBi());
    const refused = CoreError.invalid("taken back");
    assert.ok(after.writeGuarded);
    await assert.rejects(run(after.writeGuarded(utf8("another request"), () => refused)), (e) => e === refused);
    assert.deepEqual(writes, [true], "a decision already taken back never reaches the host");
  });
}
