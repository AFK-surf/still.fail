// The list catching up on what changed while away (the chats' `syncing`; docs/ui-panels.md 等待): beside the list's
// filter, the refresh mark turning in the grey of what says nothing (a turn each 1.4s, slow at its ends), its words its
// tip and what it is said to be. Only once it has gone on a while (LATER_MS): a moment's catching up shows nothing. Once
// all is here, it becomes a tick, there a second, then fades. As mbui's `@sf.sync_key`.
import { useEffect, useRef, useState } from "react";
import { Check, Refresh } from "@stillfail/ui/icons.tsx";
import { Tip } from "@stillfail/ui/parts.tsx";
import { LATER_MS } from "@stillfail/ui/waiting.css.ts";
import * as css from "./SyncMark.css.ts";

/** How long the tick stays, and how long it takes to fade. */
const DONE_MS = 1000;
const OUT_MS = 400;

export function SyncMark({ syncing, size = 32, mark = 16 }: { syncing: string | null | undefined; size?: number; mark?: number }) {
  const on = !!syncing;
  const [phase, setPhase] = useState<"none" | "on" | "done" | "out">("none");
  const said = useRef("");
  if (syncing) said.current = syncing;
  useEffect(() => {
    if (on) {
      const at = setTimeout(() => setPhase("on"), LATER_MS);
      return () => clearTimeout(at);
    }
    // Gone: what showed becomes a tick, then fades; what had not shown yet, nothing.
    setPhase((was) => (was === "on" ? "done" : "none"));
    return undefined;
  }, [on]);
  useEffect(() => {
    if (phase !== "done" && phase !== "out") return;
    const at = setTimeout(() => setPhase(phase === "done" ? "out" : "none"), phase === "done" ? DONE_MS : OUT_MS);
    return () => clearTimeout(at);
  }, [phase]);
  if (phase === "none") return null;
  return (
    <Tip label={said.current}>
      <span className={css.syncMark} style={{ width: size, height: size }} data-phase={phase} role="status" aria-label={said.current} tabIndex={0}>
        <span className={css.syncTurning}><Refresh size={mark} /></span>
        <span className={css.syncTick}><Check size={mark} /></span>
      </span>
    </Tip>
  );
}
