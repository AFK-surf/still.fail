// The views render the core's wizard and send edits; navigation, validation, model resolution and writes live there.
import { useEffect, useState } from "react";
import { useCall, useTopic } from "./core/react.ts";
import type { ConnectFlowView } from "./core/shapes.ts";
import { useDoing, useDoingFailed } from "./doing.ts";
import { useToast, failure } from "./toast.tsx";
import { usePick } from "./pick.ts";

const actions = ["config", "make", "verify", "create"].map((a) => `connect.flow.${a}`);
export function useConnectFlow(station: string, mobile: boolean, resume?: string | null) {
  const [form] = useState(() => crypto.randomUUID());
  const call = useCall();
  const toast = useToast();
  const address = { station, form };
  const state = useTopic<ConnectFlowView>({ topic: "connectFlow", ...address });
  const [opened, setOpened] = useState(false);
  const [unsupported, setUnsupported] = useState(false);
  const pick = usePick(station, `connect-new:${form}`);
  const busy = useDoing(actions, address);
  const error = useDoingFailed(actions, address);
  const send = (action: string, input: Record<string, unknown> = {}) => call(`connect.flow.${action}`, { ...address, input });
  useEffect(() => {
    let active = true;
    void call("connect.flow.open", { station, form, input: { mobile, resume: resume ?? null } }).then(() => { if (active) setOpened(true); }, (e: Error & { code?: string }) => {
      if (!active) return;
      if (e.code === "unknown_call") setUnsupported(true);
      else toast(failure(e));
    });
    return () => { active = false; void call("connect.flow.drop", { station, form }).catch(() => undefined); };
  }, [call, station, form, mobile, resume, toast]);
  const act = (action: string, done?: (answer: Record<string, unknown>) => void) => {
    if (busy) return;
    void send(action).then((v) => done?.(v as Record<string, unknown>), (e: unknown) => toast(failure(e)));
  };
  return {
    form, pick, busy, error, unsupported, view: opened ? state.value : undefined,
    edit: (input: Record<string, unknown>) => { void send("edit", input).catch((e: unknown) => toast(failure(e))); },
    go: (to: string, close?: () => void) => { void send("go", { to }).then((v) => { if ((v as { close?: boolean }).close) close?.(); }, (e: unknown) => toast(failure(e))); },
    choose: (patch: Record<string, unknown>) => {
      void call("pick.set", { station, of: `connect-new:${form}`, ...patch }).then(() => call("pick.save", { station, of: `connect-new:${form}` })).catch((e: unknown) => toast(failure(e)));
    },
    act,
  };
}
