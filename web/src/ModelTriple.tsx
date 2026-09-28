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
import * as css from "./ModelTriple.css.ts";
import * as css2 from "./ModelTriple.css.ts";
import * as chatCss from "./styles/chat.css.ts";
import * as controlsCss from "./styles/controls.css.ts";
import * as shellCss from "./styles/shell.css.ts";

/** What the control leaves out, in turn, as its room narrows: the account first (its name, then all of it), the runtime, the effort. Never the model. */
const DROPS = ["", "name", "name account", "name account runtime", "name account runtime effort"];

/** `profile`: the one kept to; null: the station picks. */
export interface Pick { model: string; runtime: RuntimeKind; effort: string | null; profile: string | null }

/** The option a model is, however it is spelled (openai/gpt-6-astra is gpt-6-astra). */
export function optionOf<O extends { model: string; ids?: string[] }>(options: O[], model: string | null | undefined): O | undefined {
  if (!model) return undefined;
  return options.find((o) => o.model === model) ?? options.find((o) => o.ids?.includes(model));
}

/** What a model is called: its option's name, else as it is spelled. */
export function modelName(options: { model: string; name?: string; ids?: string[] }[], model: string): string {
  return optionOf(options, model)?.name ?? model;
}

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
  const option = optionOf(options, draft.model);
  const valueOption = optionOf(options, value.model);
  const on: RuntimeKind = runtimeFixed ? value.runtime : option?.runtimes.includes(draft.runtime) ? draft.runtime : option?.runtimes[0] ?? value.runtime;
  const askRuntime = !runtimeFixed && (option?.runtimes.length ?? 0) > 1;
  const accounts: RunnableProfile[] = option?.accounts[on] ?? [];
  const efforts = option?.efforts[on] ?? [];
  // An account kept to that does not run the model drafted gives way to the station's pick, said so.
  const profile = draft.profile && accounts.some((a) => a.id === draft.profile) ? draft.profile : null;
  const dropped = draft.profile !== null && profile === null;
  const effort = draft.effort && efforts.includes(draft.effort) ? draft.effort : null;
  // The model it has, as it spells it, stays: another spelling of it is not a change.
  const next: Pick = { model: option && option !== valueOption ? option.model : value.model, runtime: on, effort, profile };
  const changed = next.model !== value.model || next.runtime !== value.runtime || next.effort !== value.effort || next.profile !== value.profile;
  const kept = value.profile ? valueOption?.accounts[value.runtime]?.find((a) => a.id === value.profile) ?? current : undefined;
  const shown = kept ?? current;
  const set = (patch: Partial<Pick>) => setDraft((d) => ({ ...d, ...patch }));
  const [filter, setFilter] = useState("");
  const words = filter.trim().toLowerCase();
  const listed = options.filter((o) => [o.name, o.model, ...o.ids].some((s) => s.toLowerCase().includes(words)));
  // By series, in the core's order (Claude's biggest first, the rest by name; newest first in each).
  const bySeries = new Map<string, ModelOption[]>();
  for (const o of listed) bySeries.set(o.family ?? "其他", [...(bySeries.get(o.family ?? "其他") ?? []), o]);
  const groups = [...bySeries];
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
      <span className={css2.modelTripleFit} ref={fit}>
        <Popover.Trigger className={css2.modelTriple} title={title} disabled={options.length === 0} data-drop={DROPS[drop]}>
          {options.length === 0 ? <span className={css2.tripleModel}>没有可用模型</span> : (
            <>
              <span className={css2.tripleModel}><ModelLogo maker={valueOption?.maker} runtime={value.runtime} size={13} /><span className="triple-model-name" title={value.model || undefined}>{value.model ? valueOption?.name ?? value.model : "选模型"}</span></span>
              {!runtimeFixed && (valueOption?.runtimes.length ?? 0) > 1 && <span className={`${css2.triplePart} ${css2.tripleRuntime}`}><RuntimeLogo runtime={value.runtime} size={13} />{RUNTIME_LABEL[value.runtime]}</span>}
              <span className={`${css2.triplePart} ${css2.tripleEffort}`} data-default={value.effort === null || undefined}>{value.effort ?? "默认深度"}</span>
              <span className={`${css2.triplePart} ${css2.tripleAccount}`}>
                {shown && <ProviderLogo runtime={value.runtime} kind={shown.kind ?? "env"} size={13} />}
                <span className={css2.tripleAccountName}>{value.profile ? shown?.name ?? value.profile : shown ? `自动 · ${shown.name}` : "自动分配"}</span>
                {!value.profile && <span className={css2.tripleAccountShort}>自动</span>}
                {shown && <span className={css2.tripleRings}><QuotaBars quota={shown.quota} compact small /></span>}
              </span>
            </>
          )}
          <ChevronDown size={12} className={chatCss.chooserChevron} />
        </Popover.Trigger>
      </span>
      <Popover.Portal>
        <Popover.Content className={`${controlsCss.popover} ${css2.runPickerPanel}`} side={side} align="start" sideOffset={6} collisionPadding={8}>
          <div className={css2.runPicker}>
            <div className={`${css2.runPickerColumn} ${css2.runPickerModels}`}>
              <h4>模型</h4>
              {/* Many models: a filter; the models by series. */}
              {options.length > 8 && (
                <input className={`${controlsCss.input} ${css2.runPickerFilter}`} placeholder="搜索模型" value={filter} onChange={(e) => setFilter(e.target.value)} autoFocus />
              )}
              {groups.map(([who, list]) => (
                <div key={who} className={`${css2.runPickerGroup} ${css.series}`}>
                  {groups.length > 1 && <h5>{who}</h5>}
                  {list.map((o) => (
                    <button key={o.model} type="button" className={css2.runPickerOption} title={o.ids.join("\n")} aria-pressed={option === o} onClick={() => set({ model: o.model })}>
                      <ModelLogo maker={o.maker} runtime={o.runtimes[0] ?? value.runtime} size={13} />
                      <span className={css2.runOptionText}><span>{o.name}</span>{o.spent && <span className={css2.runPickerSpent}>{o.spent.text}</span>}</span>
                    </button>
                  ))}
                </div>
              ))}
              {listed.length === 0 && <p className={`${shellCss.muted} ${css2.runPickerEmpty}`}>没有叫这个的模型</p>}
            </div>
            {askRuntime && (
              <div className={css2.runPickerColumn}>
                <h4>运行时</h4>
                {option!.runtimes.map((r) => (
                  <button key={r} type="button" className={css2.runPickerOption} aria-pressed={on === r} onClick={() => set({ runtime: r })}>
                    <RuntimeLogo runtime={r} size={13} />{RUNTIME_LABEL[r]}
                  </button>
                ))}
              </div>
            )}
            <div className={css2.runPickerColumn}>
              <h4>思考深度</h4>
              {[null, ...efforts].map((e) => (
                <button key={e ?? ""} type="button" className={css2.runPickerOption} aria-pressed={effort === e} onClick={() => set({ effort: e })}>{e ?? "默认"}</button>
              ))}
            </div>
            <div className={`${css2.runPickerColumn} ${css2.runPickerAccounts}`}>
              <h4>账号</h4>
              {dropped && <p className={css2.runPickerNote}>指定的账号没有启用 {option?.name ?? next.model}，改成了自动分配</p>}
              <button type="button" className={css2.runPickerOption} aria-pressed={profile === null} onClick={() => set({ profile: null })}>
                <span className={css2.runOptionText}><strong>自动分配</strong><span className={shellCss.muted}>额度用完或登录失效时换一个</span>{current && !value.profile && <span className={shellCss.muted}>现在：{current.name}</span>}</span>
              </button>
              {accounts.map((a) => (
                <button key={a.id} type="button" className={css2.runPickerOption} aria-pressed={profile === a.id} onClick={() => set({ profile: a.id })}>
                  <ProviderLogo runtime={on} kind={a.kind ?? "env"} size={15} />
                  <span className={css2.runOptionText}><span>{a.name}</span></span>
                  <QuotaBars quota={a.quota} compact />
                </button>
              ))}
            </div>
          </div>
          <div className={css2.runPickerFoot}>
            <Popover.Close className={`${controlsCss.btn} ${controlsCss.btnGhost} ${css2.btnSm}`}>取消</Popover.Close>
            {/* Nothing changed: it says so, and only closes. */}
            <button type="button" className={changed ? `${controlsCss.btn} ${controlsCss.btnPrimary} ${css2.btnSm}` : `${controlsCss.btn} btn-secondary ${css2.btnSm}`} disabled={!option}
              onClick={() => { setOpen(false); if (changed) onPick(next); }}>{changed ? "确定" : "不变"}</button>
          </div>
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}
