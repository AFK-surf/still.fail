// The person's own lock left out of a test of the lending itself: every grant holds as the station says it.
import { Effect } from "effect";
import type { AdbEnv } from "../src/adb.ts";

export const personalStub = (): Pick<AdbEnv, "personal" | "holds" | "subOf" | "sub" | "pair"> => ({
  personal: {
    chain: () => ({ devices: new Map(), hash: null }),
    refresh: () => Effect.void,
    view: () => ({ standing: "member", devices: [] }),
    signGrant: () => Effect.succeed({ body: {}, sig: {} }),
  } as unknown as AdbEnv["personal"],
  holds: (g) => (g as { exp?: number }).exp ?? null,
  subOf: () => "s",
  sub: () => "s",
  pair: { begin: () => Effect.succeed(null), code: () => Effect.succeed(null), cancel: () => {}, state: () => null },
});
