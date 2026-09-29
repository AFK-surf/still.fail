// A step that reaches past the demo (Slack, a model's account, signing in, another machine, ember cloud's members)
// cannot be done in it: the demo says so over itself, and offers the real ember (station.ts NeedsReal, mount.tsx).
import { useSyncExternalStore } from "react";
import { createPortal } from "react-dom";
import * as css from "./real.css.ts";

const APP = "https://ember.3720.org";

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

export function RealEmber() {
  const shown = useSyncExternalStore((l) => { listeners.add(l); return () => listeners.delete(l); }, () => open, () => false);
  if (!shown) return null;
  // On the page itself, over whatever the app has open (its dialogs are on the page too, and hold the pointer).
  return createPortal(
    <div className={css.veil} data-real-ember="" onClick={(e) => { if (e.target === e.currentTarget) set(false); }}>
      <div className={css.card} role="dialog" aria-modal="true" aria-labelledby="real-ember-title">
        <img className={css.mark} src="/mark-dark.svg" alt="" />
        <h2 id="real-ember-title" className={css.title}>这一步要在真实的 still.fail 里做</h2>
        <div className={css.actions}>
          <button type="button" className={css.button} onClick={() => set(false)}>知道了</button>
          <a className={css.button} data-primary="" href={APP}>打开 still.fail</a>
        </div>
      </div>
    </div>,
    document.body,
  );
}
