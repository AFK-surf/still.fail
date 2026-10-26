// A step that reaches past the demo (Slack, a model's account, signing in, another machine, still.fail cloud's members)
// cannot be done in it: the demo says so as the app asks anything (Confirm, over whatever the app has open), and offers
// the real still.fail instance (station.ts NeedsReal, mount.tsx).
import { useSyncExternalStore } from "react";
import { t } from "../i18n.ts";
import { Confirm } from "../ui.tsx";

const APP = "https://app.still.fail";

let open = false;
const listeners = new Set<() => void>();
function set(next: boolean): void {
  open = next;
  for (const listener of listeners) listener();
}

/** Shows the note (from the demo's core, as such a step is asked for). */
export function askForReal(): void {
  set(true);
}

export function RealStillFail() {
  const shown = useSyncExternalStore((l) => { listeners.add(l); return () => listeners.delete(l); }, () => open, () => false);
  return (
    <Confirm open={shown} title={t("web-main.demoReal.title")} action={t("web-main.demoReal.open")} tone="primary"
      cancel={t("web-main.demoReal.dismiss")} onConfirm={() => location.assign(APP)} onClose={() => set(false)} />
  );
}
