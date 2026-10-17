// The new-connect page's adapter on the core's connect flow (the Android app's screens/ConnectFlow.kt): the page
// (Connects.tsx NewConnectScreen) shows the core's `connectFlow` view and sends what is done to it.
import { useEffect, useMemo } from "react";
import { core, useTopic } from "../../../../web/src/core/react.ts";
import type { ConnectFlowView } from "../../../../web/src/core/shapes.ts";
import { useDoing, useDoingFailed } from "../../../../web/src/doing.ts";
import type { AppState } from "../AppState";
import { t } from "../i18n";

/**
 * UI adapter only: the core owns the steps, draft, model choices and writes.
 *
 * Kotlin's `view` is Compose state, and `busy` / `error` read `app.isDoing` / `app.failedOf` (Compose state too): what
 * reads them is drawn again when they change. Here they are React state behind the class: `rememberConnectFlow` reads
 * the topic and the doing list with hooks, and puts what they say on the flow each render, as Kotlin's
 * `flow.view = topic.value` does; the page that holds the flow (and every part it is handed to) is drawn again with them.
 */
export class ConnectFlow {
  view: ConnectFlowView | null = null;
  private readonly calls = ["config", "make", "verify", "create"].map((it) => `connect.flow.${it}`);
  #busy = false;
  #error: string | null = null;

  constructor(private readonly app: AppState, readonly station: string, readonly form: string) {}

  get busy(): boolean { return this.#busy; }
  get error(): string | null { return this.#error; }

  /** What the hooks of `rememberConnectFlow` read this render: the core's view, and whether a write is under way or failed. */
  seen(view: ConnectFlowView | null, busy: boolean, error: string | null) {
    this.view = view;
    this.#busy = busy;
    this.#error = error;
  }
  /** The calls whose being under way (or failed) is the flow's `busy` (`error`). */
  get doingCalls(): readonly string[] { return this.calls; }

  call(action: string, input: Record<string, unknown> = {}): Promise<unknown> {
    return core().call(`connect.flow.${action}`, { station: this.station, form: this.form, input });
  }
  edit(fill: Record<string, unknown>) {
    this.app.act(t("android-settings.flow.edit"), () => this.call("edit", fill));
  }
  go(to: string, close: () => void = () => {}) {
    this.app.act(t("android-settings.flow.go"), async () => {
      const r = (await this.call("go", { to })) as { close?: unknown } | null;
      if (r?.close === true) close();
    });
  }
  act(action: string, done: (result: Record<string, unknown>) => void = () => {}) {
    if (!this.busy) this.app.act(this.view?.title ?? t("android-settings.flow.add"), async () => { done((await this.call(action)) as Record<string, unknown>); });
  }
  choose(fill: Record<string, unknown>) {
    this.app.act(t("android-settings.flow.choose"), async () => {
      await this.app.api(this.station).pickSet(`connect-new:${this.form}`, fill);
      await this.app.api(this.station).pickSave(`connect-new:${this.form}`);
    });
  }
}

/** The flow of a new connect on `station` (a hook: Kotlin's name kept), opened (going on with `resume`) and dropped with the page. */
export function rememberConnectFlow(app: AppState, station: string, resume: string | null | undefined): ConnectFlow {
  const flow = useMemo(() => new ConnectFlow(app, station, crypto.randomUUID()), [app, station]);
  const topic = useTopic<ConnectFlowView>({ topic: "connectFlow", station, form: flow.form });
  const busy = useDoing(flow.doingCalls, { station, form: flow.form });
  const error = useDoingFailed(flow.doingCalls, { station, form: flow.form });
  flow.seen(topic.value ?? null, busy, error ?? null);
  useEffect(() => {
    app.act(t("android-settings.flow.open"), () => flow.call("open", { mobile: true, resume: resume ?? null }));
  }, [flow, resume]);
  useEffect(() => () => {
    app.act(t("android-settings.flow.drop"), () => flow.call("drop"));
  }, [flow]);
  return flow;
}
