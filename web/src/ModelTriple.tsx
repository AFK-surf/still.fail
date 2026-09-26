// The one way a model is chosen, wherever it is: the model, the runtime (where it can still change, and the model runs
// on more than one), how hard it thinks, and who runs it (the station's pick, or one profile kept to). One panel, from
// one control that shows them together. Picks there are a draft until 确定; a panel closed otherwise changes nothing.
import { ChevronDown } from "lucide-react";
import { Popover } from "radix-ui";
import { useState } from "react";
import type { ProfileView, RunnableProfile, RuntimeKind } from "./api.ts";
import { QuotaBars } from "./components.tsx";
import { EFFORTS, RUNTIME_LABEL, timeUntil } from "./format.ts";
import { ModelLogo, ProviderLogo, RuntimeLogo } from "./ui.tsx";

/** A model that can be chosen: the runtimes it runs on, and whether its accounts' quota is used up. */
export interface ModelOption { model: string; runtimes: RuntimeKind[]; spent?: { until: number | null } | null }

/** `profile`: the one kept to; null: the station picks. */
export interface Pick { model: string; runtime: RuntimeKind; effort: string | null; profile: string | null }

/** An account as the control shows it. */
export type Account = Pick_<RunnableProfile, "id" | "name" | "kind" | "quota">;
type Pick_<T, K extends keyof T> = { [P in K]: T[P] };

/** Who can run a model on a runtime, from a station's profiles (those with it on). */
export function profilesFrom(profiles: ProfileView[]): (model: string, runtime: RuntimeKind) => Account[] {
  return (model, runtime) => profiles
    .filter((p) => p.runtimes.includes(runtime) && p.models.includes(model))
    .map((p) => ({ id: p.id, name: p.name, kind: p.access.kind, quota: p.quota ?? null }));
}

export function ModelTriple({ options, value, onPick, profilesFor, current, runtimeFixed, side = "bottom", title = "换模型" }: {
  options: ModelOption[];
  value: Pick;
  onPick(pick: Pick): void;
  profilesFor(model: string, runtime: RuntimeKind): Account[];
  /** A session's: the account it runs on now (the station's pick shows it). */
  current?: Account;
  runtimeFixed?: boolean;
  side?: "top" | "bottom";
  title?: string;
}) {
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState<Pick>(value);
  const option = options.find((o) => o.model === draft.model);
  const on: RuntimeKind = runtimeFixed ? value.runtime : option?.runtimes.includes(draft.runtime) ? draft.runtime : option?.runtimes[0] ?? value.runtime;
  const askRuntime = !runtimeFixed && (option?.runtimes.length ?? 0) > 1;
  const accounts = option ? profilesFor(option.model, on) : [];
  // An account kept to that does not run the model drafted gives way to the station's pick, said so.
  const profile = draft.profile && accounts.some((a) => a.id === draft.profile) ? draft.profile : null;
  const dropped = draft.profile !== null && profile === null;
  const effort = draft.effort && EFFORTS[on].includes(draft.effort) ? draft.effort : null;
  const next: Pick = { model: option?.model ?? value.model, runtime: on, effort, profile };
  const changed = next.model !== value.model || next.runtime !== value.runtime || next.effort !== value.effort || next.profile !== value.profile;
  const kept = value.profile ? profilesFor(value.model, value.runtime).find((a) => a.id === value.profile) ?? current : undefined;
  const shown = kept ?? current;
  const valueOption = options.find((o) => o.model === value.model);
  const set = (patch: Partial<Pick>) => setDraft((d) => ({ ...d, ...patch }));

  return (
    <Popover.Root open={open} onOpenChange={(o) => { setOpen(o); if (o) setDraft(value); }}>
      <Popover.Trigger className="model-triple" title={title} disabled={options.length === 0}>
        {options.length === 0 ? <span>没有可用模型</span> : (
          <>
            <ModelLogo model={value.model} runtime={value.runtime} size={13} />
            <span>{value.model || "选模型"}</span>
            {!runtimeFixed && (valueOption?.runtimes.length ?? 0) > 1 && <><span className="triple-dot">·</span><span>{RUNTIME_LABEL[value.runtime]}</span></>}
            <span className="triple-dot">·</span><span>{value.effort ?? "默认深度"}</span>
            <span className="triple-dot">·</span>
            {shown && <ProviderLogo runtime={value.runtime} kind={shown.kind ?? "env"} size={13} />}
            <span className="triple-account">{value.profile ? shown?.name ?? value.profile : shown ? `自动 · ${shown.name}` : "自动分配"}</span>
            {shown && <QuotaBars quota={shown.quota} compact />}
          </>
        )}
        <ChevronDown size={12} className="chooser-chevron" />
      </Popover.Trigger>
      <Popover.Portal>
        <Popover.Content className="popover run-picker-panel" side={side} align="start" sideOffset={6} collisionPadding={8}>
          <div className="run-picker">
            <div className="run-picker-column">
              <h4>模型</h4>
              {options.map((o) => (
                <button key={o.model} type="button" className="run-picker-option" aria-pressed={next.model === o.model} onClick={() => set({ model: o.model })}>
                  <ModelLogo model={o.model} runtime={o.runtimes[0] ?? value.runtime} size={13} />
                  <span className="run-option-text"><span>{o.model}</span>{o.spent && <span className="run-picker-spent">额度用完{o.spent.until ? ` · ${timeUntil(o.spent.until)}恢复` : ""}</span>}</span>
                </button>
              ))}
            </div>
            {askRuntime && (
              <div className="run-picker-column">
                <h4>运行时</h4>
                {option!.runtimes.map((r) => (
                  <button key={r} type="button" className="run-picker-option" aria-pressed={on === r} onClick={() => set({ runtime: r })}>
                    <RuntimeLogo runtime={r} size={13} />{RUNTIME_LABEL[r]}
                  </button>
                ))}
              </div>
            )}
            <div className="run-picker-column">
              <h4>思考深度</h4>
              {[null, ...EFFORTS[on]].map((e) => (
                <button key={e ?? ""} type="button" className="run-picker-option" aria-pressed={effort === e} onClick={() => set({ effort: e })}>{e ?? "默认"}</button>
              ))}
            </div>
            <div className="run-picker-column run-picker-accounts">
              <h4>账号</h4>
              {dropped && <p className="run-picker-note">指定的账号没有启用 {next.model}，改成了自动分配</p>}
              <button type="button" className="run-picker-option" aria-pressed={profile === null} onClick={() => set({ profile: null })}>
                <span className="run-option-text"><strong>自动分配</strong><span className="muted">{current && !value.profile ? `现在在「${current.name}」；额度用完或登录失效时换一个` : "额度用完或登录失效时换一个"}</span></span>
              </button>
              {accounts.map((a) => (
                <button key={a.id} type="button" className="run-picker-option" aria-pressed={profile === a.id} onClick={() => set({ profile: a.id })}>
                  <ProviderLogo runtime={on} kind={a.kind ?? "env"} size={15} />
                  <span className="run-option-text"><span>{a.name}</span></span>
                  <QuotaBars quota={a.quota} compact />
                </button>
              ))}
            </div>
          </div>
          <div className="run-picker-foot">
            <Popover.Close className="btn btn-ghost btn-sm">取消</Popover.Close>
            {/* Nothing changed: it says so, and only closes. */}
            <button type="button" className={changed ? "btn btn-primary btn-sm" : "btn btn-secondary btn-sm"} disabled={!option}
              onClick={() => { setOpen(false); if (changed) onPick(next); }}>{changed ? "确定" : "不变"}</button>
          </div>
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}
