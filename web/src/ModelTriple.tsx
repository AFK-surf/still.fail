// The one way a model is chosen, wherever it is: the model, then (when it runs on more than one) the runtime, how hard
// it thinks, and for a session who runs it; in one panel, from one control that shows them together. Only the last
// pick makes the choice, so a panel left halfway changes nothing.
import { ChevronDown } from "lucide-react";
import { Popover } from "radix-ui";
import { useState, type ReactNode } from "react";
import type { RunnableProfile, RuntimeKind } from "./api.ts";
import { QuotaBars } from "./components.tsx";
import { EFFORTS, RUNTIME_LABEL, timeUntil } from "./format.ts";
import { ModelLogo, ProviderLogo, RuntimeLogo } from "./ui.tsx";

/** A model that can be chosen: the runtimes it runs on, whether its accounts' quota is used up, and who runs it. */
export interface ModelOption {
  model: string;
  runtimes: RuntimeKind[];
  spent?: { until: number | null } | null;
  /** For a session: the profiles that run it (`current`: the one it is on). */
  profiles?: RunnableProfile[];
}

export interface Pick { model: string; runtime: RuntimeKind; effort: string | null; profile?: string | null }

/**
 * `account`: a session's, which is also moved to an account with the model on (kept to it by hand, or null: the
 * station's pick); `pinned` whether it is kept to its account now. When the account it is on runs the model picked,
 * the effort makes the pick and it stays there.
 */
export interface AccountChoice { pinned: boolean; current: { name: string; kind: string | null; quota: RunnableProfile["quota"] } | null; profile: string }

export function ModelTriple({ options, value, onPick, account, side = "bottom", title = "换模型" }: {
  options: ModelOption[]; value: Pick; onPick(pick: Pick): void; account?: AccountChoice; side?: "top" | "bottom"; title?: string;
}) {
  const [open, setOpen] = useState(false);
  const [model, setModel] = useState(value.model);
  const [runtime, setRuntime] = useState<RuntimeKind>(value.runtime);
  const [effort, setEffort] = useState(value.effort);
  const option = options.find((o) => o.model === model);
  // The runtime it goes on: the one marked if the model runs there, else the model's first.
  const on: RuntimeKind = option?.runtimes.includes(runtime) ? runtime : option?.runtimes[0] ?? value.runtime;
  const askRuntime = !account && (option?.runtimes.length ?? 0) > 1;
  const same = model === value.model && effort === value.effort;
  const stays = !account || (option?.profiles?.some((p) => p.current) ?? false);
  const done = (pick: Pick) => { setOpen(false); onPick(pick); };
  const current = account?.current;

  let label: ReactNode = (
    <>
      <ModelLogo model={value.model} runtime={value.runtime} size={13} />
      <span>{value.model || "选模型"}</span>
      {!account && options.find((o) => o.model === value.model)?.runtimes.length! > 1 && <><span className="triple-dot">·</span><span>{RUNTIME_LABEL[value.runtime]}</span></>}
      <span className="triple-dot">·</span><span>{value.effort ?? "默认深度"}</span>
      {account && (
        <>
          <span className="triple-dot">·</span>
          <ProviderLogo runtime={value.runtime} kind={current?.kind ?? "env"} size={13} />
          <span className="triple-account">{account.pinned ? current?.name : `自动 · ${current?.name ?? ""}`}</span>
          <QuotaBars quota={current?.quota} compact />
        </>
      )}
    </>
  );
  if (options.length === 0) label = <span>没有可用模型</span>;

  return (
    <Popover.Root open={open} onOpenChange={(next) => {
      setOpen(next);
      if (next) { setModel(value.model); setRuntime(value.runtime); setEffort(value.effort); }
    }}>
      <Popover.Trigger className="model-triple" title={title} disabled={options.length === 0}>
        {label}
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
                if (option && stays) done({ model: option.model, runtime: on, effort: e, ...(account ? { profile: account.pinned ? account.profile : null } : {}) });
              }}>{e ?? "默认"}</button>
            ))}
          </div>
          {account && (
            <div className="run-picker-column run-picker-accounts">
              <h4>账号</h4>
              {!option ? <p className="muted">先选一个模型</p> : (
                <>
                  {!stays && <p className="run-picker-note">现在的账号没有启用 {option.model}，选一个</p>}
                  <button type="button" className="run-picker-option" aria-pressed={same && !account.pinned} onClick={() => done({ model: option.model, runtime: on, effort, profile: null })}>
                    <span className="run-option-text"><strong>自动分配</strong><span className="muted">额度用完或登录失效时换一个</span></span>
                  </button>
                  {(option.profiles ?? []).map((p) => (
                    <button key={p.id} type="button" className="run-picker-option" aria-pressed={same && account.pinned && p.current} onClick={() => done({ model: option.model, runtime: on, effort, profile: p.id })}>
                      <ProviderLogo runtime={p.runtime ?? on} kind={p.kind ?? "env"} size={15} />
                      <span className="run-option-text"><span>{p.name}</span>{same && p.current && !account.pinned && <span className="muted">当前</span>}</span>
                      <QuotaBars quota={p.quota} compact />
                    </button>
                  ))}
                </>
              )}
            </div>
          )}
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}
