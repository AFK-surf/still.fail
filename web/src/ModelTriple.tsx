// The one way a model is chosen, wherever it is: the model, the runtime (where it can still change, and the model runs
// on more than one), how hard it thinks, and who runs it (the station's pick, or one profile kept to). One panel, from
// one control that shows them together. Picks there are a draft until 确定; a panel closed otherwise changes nothing.
import { ChevronDown } from "./icons.tsx";
import { Popover } from "radix-ui";
import { useLayoutEffect, useRef, useState } from "react";
import type { ModelOption, RunnableProfile, RuntimeKind } from "./api.ts";
import { QuotaBars } from "./components.tsx";
import { RUNTIME_LABEL } from "./format.ts";
import { ModelLogo, ProviderLogo, RuntimeLogo } from "./ui.tsx";

/** What the control leaves out, in turn, as its room narrows: the account first (its name, then all of it), the runtime, the effort. Never the model. */
const DROPS = ["", "name", "name account", "name account runtime", "name account runtime effort"];

/** `profile`: the one kept to; null: the station picks. */
export interface Pick { model: string; runtime: RuntimeKind; effort: string | null; profile: string | null }


export function ModelTriple({ options, value, onPick, current, runtimeFixed, side = "bottom", title = "换模型" }: {
  options: ModelOption[];
  value: Pick;
  onPick(pick: Pick): void;
  /** A session's: the account it runs on now (the station's pick shows it). */
  current?: RunnableProfile | undefined;
  runtimeFixed?: boolean;
  side?: "top" | "bottom";
  title?: string;
}) {
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState<Pick>(value);
  const option = options.find((o) => o.model === draft.model);
  const on: RuntimeKind = runtimeFixed ? value.runtime : option?.runtimes.includes(draft.runtime) ? draft.runtime : option?.runtimes[0] ?? value.runtime;
  const askRuntime = !runtimeFixed && (option?.runtimes.length ?? 0) > 1;
  const accounts: RunnableProfile[] = option?.accounts[on] ?? [];
  const efforts = option?.efforts[on] ?? [];
  // An account kept to that does not run the model drafted gives way to the station's pick, said so.
  const profile = draft.profile && accounts.some((a) => a.id === draft.profile) ? draft.profile : null;
  const dropped = draft.profile !== null && profile === null;
  const effort = draft.effort && efforts.includes(draft.effort) ? draft.effort : null;
  const next: Pick = { model: option?.model ?? value.model, runtime: on, effort, profile };
  const changed = next.model !== value.model || next.runtime !== value.runtime || next.effort !== value.effort || next.profile !== value.profile;
  const valueOption = options.find((o) => o.model === value.model);
  const kept = value.profile ? valueOption?.accounts[value.runtime]?.find((a) => a.id === value.profile) ?? current : undefined;
  const shown = kept ?? current;
  const set = (patch: Partial<Pick>) => setDraft((d) => ({ ...d, ...patch }));
  const [filter, setFilter] = useState("");
  const listed = options.filter((o) => o.model.toLowerCase().includes(filter.trim().toLowerCase()));
  const byMaker = new Map<string, ModelOption[]>();
  for (const o of listed) {
    const who = o.maker?.name ?? "其他";
    byMaker.set(who, [...(byMaker.get(who) ?? []), o]);
  }
  const groups = [...byMaker].sort(([a], [b]) => (a === "其他" ? 1 : b === "其他" ? -1 : a.localeCompare(b)));
  // Shown within the room it has: the most it can say that fits, dropping what matters least first.
  const fit = useRef<HTMLSpanElement>(null);
  const [drop, setDrop] = useState(0);
  const label = `${value.model}|${value.runtime}|${value.effort}|${value.profile}|${shown?.name ?? ""}`;
  useLayoutEffect(() => {
    const room = fit.current;
    const trigger = room?.firstElementChild as HTMLElement | null;
    if (!room || !trigger) return;
    const measure = () => {
      let level = 0;
      for (; level < DROPS.length - 1; level++) {
        trigger.dataset.drop = DROPS[level]!;
        if (trigger.scrollWidth <= room.clientWidth) break;
      }
      trigger.dataset.drop = DROPS[level]!;
      setDrop(level);
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(room);
    return () => observer.disconnect();
  }, [label]);

  return (
    <Popover.Root open={open} onOpenChange={(o) => { setOpen(o); if (o) { setDraft(value); setFilter(""); } }}>
      <span className="model-triple-fit" ref={fit}>
        <Popover.Trigger className="model-triple" title={title} disabled={options.length === 0} data-drop={DROPS[drop]}>
          {options.length === 0 ? <span className="triple-model">没有可用模型</span> : (
            <>
              <span className="triple-model"><ModelLogo maker={valueOption?.maker} runtime={value.runtime} size={13} /><span className="triple-model-name">{value.model || "选模型"}</span></span>
              {!runtimeFixed && (valueOption?.runtimes.length ?? 0) > 1 && <span className="triple-part triple-runtime">{RUNTIME_LABEL[value.runtime]}</span>}
              <span className="triple-part triple-effort" data-default={value.effort === null || undefined}>{value.effort ?? "默认深度"}</span>
              <span className="triple-part triple-account">
                {shown && <ProviderLogo runtime={value.runtime} kind={shown.kind ?? "env"} size={13} />}
                <span className="triple-account-name">{value.profile ? shown?.name ?? value.profile : shown ? `自动 · ${shown.name}` : "自动分配"}</span>
                {!value.profile && <span className="triple-account-short">自动</span>}
                {shown && <span className="triple-rings"><QuotaBars quota={shown.quota} compact ring={15} /></span>}
              </span>
            </>
          )}
          <ChevronDown size={12} className="chooser-chevron" />
        </Popover.Trigger>
      </span>
      <Popover.Portal>
        <Popover.Content className="popover run-picker-panel" side={side} align="start" sideOffset={6} collisionPadding={8}>
          <div className="run-picker">
            <div className="run-picker-column run-picker-models">
              <h4>模型</h4>
              {/* Many models: a filter, and the models by who made them. */}
              {options.length > 8 && (
                <input className="input run-picker-filter" placeholder="搜索模型" value={filter} onChange={(e) => setFilter(e.target.value)} autoFocus />
              )}
              {groups.map(([who, list]) => (
                <div key={who} className="run-picker-group">
                  {groups.length > 1 && <h5>{who}</h5>}
                  {list.map((o) => (
                    <button key={o.model} type="button" className="run-picker-option" aria-pressed={next.model === o.model} onClick={() => set({ model: o.model })}>
                      <ModelLogo maker={o.maker} runtime={o.runtimes[0] ?? value.runtime} size={13} />
                      <span className="run-option-text"><span>{o.model}</span>{o.spent && <span className="run-picker-spent">{o.spent.text}</span>}</span>
                    </button>
                  ))}
                </div>
              ))}
              {listed.length === 0 && <p className="muted run-picker-empty">没有叫这个的模型</p>}
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
              {[null, ...efforts].map((e) => (
                <button key={e ?? ""} type="button" className="run-picker-option" aria-pressed={effort === e} onClick={() => set({ effort: e })}>{e ?? "默认"}</button>
              ))}
            </div>
            <div className="run-picker-column run-picker-accounts">
              <h4>账号</h4>
              {dropped && <p className="run-picker-note">指定的账号没有启用 {next.model}，改成了自动分配</p>}
              <button type="button" className="run-picker-option" aria-pressed={profile === null} onClick={() => set({ profile: null })}>
                <span className="run-option-text"><strong>自动分配</strong><span className="muted">额度用完或登录失效时换一个</span>{current && !value.profile && <span className="muted">现在：{current.name}</span>}</span>
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
