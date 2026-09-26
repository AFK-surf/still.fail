// The one way a model is chosen, wherever it is: the model, the runtime (where it can still change, and the model runs
// on more than one), how hard it thinks, and who runs it (the station's pick, or one profile kept to). One panel, from
// one control that shows them together. Only the last pick makes the choice, so a panel left halfway changes nothing:
// how hard it thinks is the last when the account stays as it is (the station's pick, or one kept to that runs the
// model); else who runs it is.
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
  const [model, setModel] = useState(value.model);
  const [runtime, setRuntime] = useState<RuntimeKind>(value.runtime);
  const [effort, setEffort] = useState(value.effort);
  const option = options.find((o) => o.model === model);
  const on: RuntimeKind = runtimeFixed ? value.runtime : option?.runtimes.includes(runtime) ? runtime : option?.runtimes[0] ?? value.runtime;
  const askRuntime = !runtimeFixed && (option?.runtimes.length ?? 0) > 1;
  const accounts = option ? profilesFor(option.model, on) : [];
  // The account stays as it is: the one kept to runs the model; the station's pick, which for a session is the account
  // it is on (a model that one does not run moves it, so it is picked again).
  const stays = value.profile ? accounts.some((a) => a.id === value.profile) : !current || accounts.some((a) => a.id === current.id);
  const done = (pick: Pick) => { setOpen(false); onPick(pick); };
  const kept = value.profile ? profilesFor(value.model, value.runtime).find((a) => a.id === value.profile) ?? current : undefined;
  const shown = kept ?? current;
  const valueOption = options.find((o) => o.model === value.model);

  return (
    <Popover.Root open={open} onOpenChange={(next) => {
      setOpen(next);
      if (next) { setModel(value.model); setRuntime(value.runtime); setEffort(value.effort); }
    }}>
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
        <Popover.Content className="popover run-picker" side={side} align="start" sideOffset={6} collisionPadding={8}>
          <div className="run-picker-column">
            <h4>模型</h4>
            {options.map((o) => (
              <button key={o.model} type="button" className="run-picker-option" aria-pressed={model === o.model} onClick={() => setModel(o.model)}>
                <ModelLogo model={o.model} runtime={o.runtimes[0] ?? value.runtime} size={13} />
                <span className="run-option-text"><span>{o.model}</span>{o.spent && <span className="run-picker-spent">额度用完{o.spent.until ? ` · ${timeUntil(o.spent.until)}恢复` : ""}</span>}</span>
              </button>
            ))}
          </div>
          {askRuntime && (
            <div className="run-picker-column">
              <h4>运行时</h4>
              {option!.runtimes.map((r) => (
                <button key={r} type="button" className="run-picker-option" aria-pressed={on === r} onClick={() => setRuntime(r)}>
                  <RuntimeLogo runtime={r} size={13} />{RUNTIME_LABEL[r]}
                </button>
              ))}
            </div>
          )}
          <div className="run-picker-column">
            <h4>思考深度</h4>
            {[null, ...EFFORTS[on]].map((e) => (
              <button key={e ?? ""} type="button" className="run-picker-option" aria-pressed={effort === e} onClick={() => {
                setEffort(e);
                if (option && stays) done({ model: option.model, runtime: on, effort: e, profile: value.profile });
              }}>{e ?? "默认"}</button>
            ))}
          </div>
          <div className="run-picker-column run-picker-accounts">
            <h4>账号</h4>
            {!option ? <p className="muted">先选一个模型</p> : (
              <>
                {!stays && <p className="run-picker-note">{value.profile ? "指定的" : "现在的"}账号没有启用 {option.model}，选一个</p>}
                {/* Nothing here is marked as picked: picking one is what makes the choice. What it has now says 当前. */}
                <button type="button" className="run-picker-option" onClick={() => done({ model: option.model, runtime: on, effort, profile: null })}>
                  <span className="run-option-text"><strong>自动分配</strong><span className="muted">额度用完或登录失效时换一个</span></span>
                  {!value.profile && <span className="run-picker-current">当前</span>}
                </button>
                {accounts.map((a) => (
                  <button key={a.id} type="button" className="run-picker-option" onClick={() => done({ model: option.model, runtime: on, effort, profile: a.id })}>
                    <ProviderLogo runtime={on} kind={a.kind ?? "env"} size={15} />
                    <span className="run-option-text"><span>{a.name}</span>{!value.profile && current?.id === a.id && <span className="muted">自动分配到这里</span>}</span>
                    {value.profile === a.id && <span className="run-picker-current">当前</span>}
                    <QuotaBars quota={a.quota} compact />
                  </button>
                ))}
              </>
            )}
          </div>
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}
