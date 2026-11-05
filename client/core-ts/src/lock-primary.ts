// Whether this device is one of its person's primary trusted devices (主授信设备, docs/workspace-lock.md): an app the
// person chose to be told, wherever its app is, when a new device of theirs asks to be approved face to face. None
// chosen, nothing changes. Kept on this device (its host's storage, as its push registration is), and told to the
// cloud with its push registration (sync/cloud.ts `pushRegistered`, `primary`), which the cloud pushes to then
// (cloud/src/push.ts `lockWake`); while the app runs behind (a desktop's in the notification area), a notice says it
// (views/pair.ts `serveTrusted`, attention.ts `pairing`).
import { Effect } from "effect";
import type { Inner } from "./core.ts";

/// Where it is kept: "1" when it is one.
export const PRIMARY_KEY = "lock-primary";

const primaries = new WeakMap<Inner, boolean>();

/// Whether this device is one of its person's primary trusted devices (false until it is read, at the start).
export const isPrimary = (inner: Inner): boolean => primaries.get(inner) === true;

/// As this device keeps it.
export function loadPrimary(inner: Inner): Effect.Effect<boolean> {
  return Effect.map(Effect.orElseSucceed(inner.host.storageGet(PRIMARY_KEY), () => null), (bytes) => {
    const on = bytes !== null && new TextDecoder().decode(bytes) === "1";
    primaries.set(inner, on);
    return on;
  });
}

/// Made one, or no longer one: kept on this device.
export function setPrimary(inner: Inner, on: boolean): Effect.Effect<void> {
  return Effect.suspend(() => {
    primaries.set(inner, on);
    const kept = on ? inner.host.storageSet(PRIMARY_KEY, new TextEncoder().encode("1")) : inner.host.storageDelete(PRIMARY_KEY);
    return Effect.ignore(kept, { log: "Unhandled", message: "primary trusted device kept" });
  });
}
