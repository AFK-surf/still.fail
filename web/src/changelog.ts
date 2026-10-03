// What changed in still.fail, as the core puts it together for this app (its `changelog` topic, client/core-ts/src/
// changelog.ts): the changelog's pages (pages/Changelog.tsx, mobile/Changelog.tsx) and what an update brought, shown
// once (`news`) until the changelog is opened or it is put away (`changelog.seen`).
import { useCallback } from "react";
import { useCall, useTopic } from "./core/react.ts";
import type { ChangelogView } from "./core/shapes.ts";

export function useChangelog() {
  return useTopic<ChangelogView>({ topic: "changelog" });
}

/** Says the changelog was seen up to this build: what it brought is not news any more. */
export function useChangelogSeen(): () => void {
  const call = useCall();
  return useCallback(() => void call("changelog.seen").catch(() => undefined), [call]);
}
