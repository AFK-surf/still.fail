// What a chat runs on, as the core has it chosen (client/core/src/choose.rs): a new chat's page (`newChat`: its
// stations, the one it starts on and what it runs there, as last picked on this device) and a model control (`pick`:
// what it runs on now and what its panel picked). The pages only show them and say what was picked.
import { useMemo } from "react";
import { useCall, useTopic } from "./core/react.ts";
import type { NewChatView, PickView, RuntimeKind } from "./core/shapes.ts";

/** A pick: each field given changes only that; null is the default depth, the station's pick of account. */
export interface PickPatch { model?: string; runtime?: RuntimeKind; effort?: string | null; profile?: string | null }

/** A new chat's page in a workspace. */
export function useNewChat(scope: string) {
  const state = useTopic<NewChatView>({ topic: "newChat", scope });
  const call = useCall();
  const actions = useMemo(() => ({
    /** The station it starts on (its id) and what it runs there, kept for next time. */
    pick: (p: PickPatch & { station?: string }) => void call("newChat.pick", { scope, ...p }).catch(() => undefined),
    /** The chat, made on `station` with what is picked there (as `chat.create` makes it). */
    create: (station: string) => call("newChat.create", { station }) as Promise<{ key: string; runtime: RuntimeKind; model: string; effort?: string }>,
  }), [call, scope]);
  return { ...state, ...actions };
}

export interface Picking {
  view: PickView | undefined;
  /** Picks in its panel; `open`: from what it runs on now again; `clear`: a connect being added starts over. */
  set(patch: PickPatch & { open?: boolean; clear?: boolean }): void;
  /** What the panel picked becomes what it runs on (nothing changed: nothing done). */
  save(): Promise<{ saved: boolean }>;
}

/**
 * A model control on `station`: `of` new (a new chat there), `session:<key>`, `connect:<id>` or `connect-new`. A new
 * chat's page has its control with it (`page`): nothing more to wait for.
 */
export function usePick(station: string, of: string, page?: NewChatView): Picking {
  const own = useTopic<PickView>(page ? null : { topic: "pick", station, of }).value;
  const value = page ? page.pick : own;
  const call = useCall();
  const actions = useMemo(() => ({
    set: (patch: PickPatch & { open?: boolean; clear?: boolean }) => void call("pick.set", { station, of, ...patch }).catch(() => undefined),
    save: () => call("pick.save", { station, of }) as Promise<{ saved: boolean }>,
  }), [call, station, of]);
  return useMemo(() => ({ view: value, ...actions }), [value, actions]);
}
