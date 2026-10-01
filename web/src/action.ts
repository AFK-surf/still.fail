// Buttons observe the core's operation state. Only host work (browser/native APIs) needs a local pending flag.
import { useCallback, useRef, useState } from "react";
import { callDetails, captureCall } from "./core/client.ts";
import { useTopic } from "./core/react.ts";
import { doingMatches, failed } from "./doing.ts";
import type { DoingView } from "./core/shapes.ts";
import { useToast, failure } from "./toast.tsx";

export interface Action<A extends unknown[], T> {
  run(...args: A): Promise<T | undefined>;
  busy: boolean;
  error: Error | null;
  data: T | undefined;
  args: A | undefined;
}

export function useAction<A extends unknown[], T>(fn: (...args: A) => Promise<T>, onDone?: (result: T, ...args: A) => void): Action<A, T> {
  const latest = useRef({ fn, onDone });
  latest.current = { fn, onDone };
  const toast = useToast();
  const doing = useTopic<DoingView>({ topic: "doing" });
  const locked = useRef(false);
  const [state, setState] = useState<{ pending: boolean; call: ReturnType<typeof callDetails>; error: Error | null; data: T | undefined; args: A | undefined }>({ pending: false, call: undefined, error: null, data: undefined, args: undefined });
  const run = useCallback(async (...args: A) => {
    if (locked.current) return undefined;
    locked.current = true;
    try {
      const { promise, details } = captureCall(() => latest.current.fn(...args));
      setState((s) => ({ ...s, pending: true, call: details, error: null, args }));
      const data = await promise;
      setState((s) => ({ ...s, pending: false, error: null, data, args }));
      latest.current.onDone?.(data, ...args);
      return data;
    } catch (error) {
      const e = error instanceof Error ? error : new Error(String(error));
      setState((s) => ({ ...s, pending: false, error: e, args }));
      toast(failure(error));
      return undefined;
    } finally { locked.current = false; }
  }, [toast]);
  // A pre-doing desktop core and calls that are purely browser/native work retain local feedback.
  const busy = state.call?.tracked && !doing.error
    ? (doing.value?.doing ?? []).some((item) => !failed(item) && doingMatches(item, state.call!.name, state.call!.on))
    : state.pending;
  return { run, busy, error: state.error, data: state.data, args: state.args };
}
