// The person's own lock left out of a test of the lending itself: what a test takes for it (`takeAll`: every grant holds
// as the station says it).
import { Effect } from "effect";
import type { AdbEnv } from "../src/adb.ts";

export const personalStub = (): Pick<AdbEnv, "personal" | "subOf" | "sub" | "pair"> => ({
  personal: {
    chain: () => ({ devices: new Map(), hash: null }),
    refresh: () => Effect.void,
    view: () => ({ standing: "member", devices: [] }),
    signGrant: () => Effect.succeed({ body: {}, sig: {} }),
  } as unknown as AdbEnv["personal"],
  subOf: () => "s",
  sub: () => "s",
  pair: { begin: () => Effect.succeed(null), code: () => Effect.succeed(null), cancel: () => {}, state: () => null },
});

export const takeAll = (adb: { check: unknown }) => {
  adb.check = (g: { exp?: number }) => g.exp ?? null;
};
