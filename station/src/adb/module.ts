// Phones lent to the station over members' links (adb/link.ts) as a part of the station (parts.ts): the offers and asks
// that come on a member's link, the agents' tool that lists them, with the station's page for them in the app.
import { Effect, Layer } from "effect";
import { writeLine } from "../mesh/serve.ts";
import { readOnly } from "../mesh/credential.ts";
import { Agents } from "../sessions/agents.ts";
import { ControlPlane, Parts } from "../services.ts";
import { adbTools } from "../tools/adb.ts";
import { Shares, answerAdb } from "./link.ts";

export const AdbLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const plane = yield* ControlPlane;
    const parts = yield* Parts;
    const { place } = yield* Agents;
    const shares = yield* Effect.acquireRelease(Effect.sync(() => new Shares({ cloud: plane.state })), (s) => Effect.promise(() => s.close()));
    // An offer or an ask (its send side came finished, what it hears goes down the stream).
    parts.streams("adb", async ({ conn, viewer, head, stream, reader }) => {
      // Lending a phone is a change a read-only member does not make.
      if (readOnly(viewer)) {
        await writeLine(stream, { status: 403, headers: { "content-type": "application/json" } });
        await stream.write(Buffer.from(JSON.stringify({ error: "read-only members cannot lend or use phones" })));
        return stream.finish();
      }
      return answerAdb(shares, conn, viewer, head, stream, reader);
    });
    parts.tools(
      adbTools(() => shares.list(), () => {
        const s = place();
        return s && plane.spec().pages ? `${s.origin}/w/${s.workspace}/s/${s.station}/adb` : null;
      }),
    );
  }),
);
