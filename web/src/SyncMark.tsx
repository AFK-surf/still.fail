// The list catching up on what changed while away (the chats' `syncing`; docs/ui-panels.md 等待): beside the list's
// filter, the refresh mark with how far it has come round it, close to it (the spinner's quarter turning while that is
// not known), its words its tip and what it is said to be. Only once it has gone on a while (LATER_MS): a moment's
// catching up shows nothing. As mbui's `@sf.sync_key`.
import { useEffect, useState } from "react";
import { Refresh } from "@stillfail/ui/icons.tsx";
import { Tip } from "@stillfail/ui/parts.tsx";
import { LATER_MS } from "@stillfail/ui/waiting.css.ts";
import type { ChatsSyncing } from "./core/shapes.ts";
import * as css from "./SyncMark.css.ts";

export function SyncMark({ syncing, size = 32, mark = 16 }: { syncing: ChatsSyncing | null | undefined; size?: number; mark?: number }) {
  const on = !!syncing;
  const [waited, setWaited] = useState(false);
  useEffect(() => {
    if (!on) { setWaited(false); return; }
    const at = setTimeout(() => setWaited(true), LATER_MS);
    return () => clearTimeout(at);
  }, [on]);
  if (!syncing || !waited) return null;
  const part = syncing.part ?? null;
  // (the ring's inside 2 off the mark, its line 2: the update key's)
  const ring = mark + 8;
  const r = (ring - 2) / 2;
  const round = 2 * Math.PI * r;
  return (
    <Tip label={syncing.text}>
      <span className={css.syncMark} style={{ width: size, height: size }} role="status" aria-label={syncing.text} tabIndex={0}>
        <Refresh size={mark} />
        <svg className={css.syncRing} data-unknown={part === null || undefined} width={ring} height={ring} viewBox={`0 0 ${ring} ${ring}`} aria-hidden="true">
          <circle className={css.syncTrack} cx={ring / 2} cy={ring / 2} r={r} />
          <circle className={css.syncArc} cx={ring / 2} cy={ring / 2} r={r} strokeDasharray={`${(part === null ? 0.25 : Math.min(1, Math.max(0, part))) * round} ${round}`}
            transform={`rotate(-90 ${ring / 2} ${ring / 2})`} />
        </svg>
      </span>
    </Tip>
  );
}
