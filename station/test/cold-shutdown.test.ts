import assert from "node:assert/strict";
import { test } from "node:test";
import { Rig } from "./hub-fakes.ts";

test("disposing a session waits until its archive stops writing", async () => {
  const started = Promise.withResolvers<void>(), release = Promise.withResolvers<void>();
  let packs = 0;
  const cold = { isCold: () => false, restore: () => {}, pack: async () => { packs++; started.resolve(); await release.promise; } };
  const rig = new Rig({ cold });
  let closing: Promise<void> | undefined;
  try {
    rig.store.insertSession({ key: "s", connect: "cl", runtime: "claude", profile: "cc", workspace: rig.dir,
      token: "s", createdAt: 1, lastActiveAt: 1 });
    const actor = rig.hub.actor(rig.store.getSession("s")!);
    void actor.cleanArchive();
    await started.promise;
    void actor.cleanArchive();
    let closed = false;
    closing = actor.dispose().then(() => { closed = true; });
    await new Promise<void>((resolve) => setImmediate(resolve));
    assert.equal(closed, false, "an active archive must finish before its directory can be removed");
    release.resolve();
    await closing;
    assert.equal(packs, 1, "the archive queued behind it is skipped after the actor closes");
  } finally {
    release.resolve();
    await closing;
    await rig.close();
  }
});

test("an archive that fails while closing does not make disposal fail", async () => {
  const started = Promise.withResolvers<void>(), release = Promise.withResolvers<void>();
  const cold = { isCold: () => false, restore: () => {}, pack: async () => { started.resolve(); await release.promise; throw new Error("archive failed"); } };
  const rig = new Rig({ cold });
  let closing: Promise<void> | undefined;
  try {
    rig.store.insertSession({ key: "s", connect: "cl", runtime: "claude", profile: "cc", workspace: rig.dir,
      token: "s", createdAt: 1, lastActiveAt: 1 });
    const actor = rig.hub.actor(rig.store.getSession("s")!);
    void actor.cleanArchive();
    await started.promise;
    closing = actor.dispose();
    release.resolve();
    await closing;
  } finally {
    release.resolve();
    await closing;
    await rig.close();
  }
});
