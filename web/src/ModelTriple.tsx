// The one way a model is chosen, wherever it is: the model, the runtime (where it can still change, and the model runs
// on more than one), how hard it thinks, and who runs it (the station's pick, or one profile kept to). One panel, from
// one control that shows them together. Picks there are a draft until 确定; a panel closed otherwise changes nothing.
import { ChevronDown, ChevronRight } from "./icons.tsx";
import { Popover } from "radix-ui";
import { useLayoutEffect, useRef, useState } from "react";
import type { ModelOption } from "./api.ts";
import type { Picking } from "./pick.ts";
import { QuotaBars } from "./components.tsx";
import { RUNTIME_LABEL } from "./format.ts";
import { ModelLogo, ProviderLogo, RuntimeLogo, Tip } from "./ui.tsx";
import * as css from "./ModelTriple.css.ts";
import * as css2 from "./ModelTriple.css.ts";
import * as chatCss from "./styles/chat.css.ts";
import * as controlsCss from "./styles/controls.css.ts";
import * as shellCss from "./styles/shell.css.ts";
import { DoingShown } from "./DoingMark.tsx";
import { t } from "./i18n.ts";

/** What the control leaves out, in turn, as its room narrows: the account first (its name, then all of it), the runtime, the effort. Never the model. */
const DROPS = ["", "name", "name account", "name account runtime", "name account runtime effort"];

/** The option a model is, however it is spelled (openai/gpt-6-astra is gpt-6-astra). */
export function optionOf<O extends { model: string; ids?: string[] }>(options: O[], model: string | null | undefined): O | undefined {
  if (!model) return undefined;
  return options.find((o) => o.model === model) ?? options.find((o) => o.ids?.includes(model));
}

/** What a model is called: its option's name, else as it is spelled. */
export function modelName(options: { model: string; name?: string; ids?: string[] }[], model: string): string {
  return optionOf(options, model)?.name ?? model;
}

/**
 * The control of a model pick (pick.ts `usePick`): the core says what it runs on, what the panel has picked and
 * what that means; this draws it and says what is picked. `onConfirm`: 确定 with something changed (the owner saves).
 */
export function ModelTriple({ pick, onConfirm, side = "bottom" }: { pick: Picking; onConfirm(): void; side?: "top" | "bottom" }) {
  const [open, setOpen] = useState(false);
  const v = pick.view;
  const options = v?.options ?? [];
  const value = v?.value;
  const valueOption = v?.valueOption;
  const account = v?.account;
  // Who runs it waits behind the foot's line, in a panel of its own beside this one: most of the time it is the station's pick.
  const [showAccounts, setShowAccounts] = useState(false);
  const [filter, setFilter] = useState("");
  // The models' column keeps the width it opened with, whatever the filter leaves in it.
  const [modelsWidth, setModelsWidth] = useState<number | null>(null);
  const words = filter.trim().toLowerCase();
  const listed = options.filter((o) => [o.name, o.model, ...o.ids].some((s) => s.toLowerCase().includes(words)));
  // By series, in the core's order (Claude's biggest first, the rest by name; newest first in each).
  const bySeries = new Map<string, ModelOption[]>();
  const other = t("web-main.model.otherSeries");
  for (const o of listed) bySeries.set(o.family ?? other, [...(bySeries.get(o.family ?? other) ?? []), o]);
  const groups = [...bySeries];
  // Shown within the room it has: the most it can say that fits, dropping what matters least first.
  const fit = useRef<HTMLSpanElement>(null);
  const [drop, setDrop] = useState(0);
  const label = `${value?.model}|${value?.runtime}|${value?.effort}|${value?.fast}|${v?.fastText}|${value?.profile}|${account?.text ?? ""}`;
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
  if (!v || !value) return null;
  const draft = v.draft;

  return (
    <Popover.Root open={open} onOpenChange={(o) => { setOpen(o); if (o) { pick.set({ open: true }); setFilter(""); setModelsWidth(null); setShowAccounts(false); } }}>
      <span className={css2.modelTripleFit} ref={fit}>
        <Popover.Trigger className={css2.modelTriple} disabled={options.length === 0 || pick.saving} aria-busy={pick.saving || undefined} data-drop={DROPS[drop]}>
          {options.length === 0 ? <span className={css2.tripleModel}>{t("web-main.model.none")}</span> : (
            <>
              <Tip label={value.model || null}><span className={css2.tripleModel}><ModelLogo maker={valueOption?.maker} runtime={value.runtime} size={14} /><span className="triple-model-name">{value.model ? valueOption?.name ?? value.model : t("web-main.model.pick")}</span></span></Tip>
              {!v.runtimeFixed && (valueOption?.runtimes.length ?? 0) > 1 && <span className={`${css2.triplePart} ${css2.tripleRuntime}`}><RuntimeLogo runtime={value.runtime} size={14} />{RUNTIME_LABEL[value.runtime]}</span>}
              <span className={`${css2.triplePart} ${css2.tripleEffort}`} data-default={!value.effort || undefined}>{value.effort ?? t("web-main.model.defaultEffort")}</span>
              {v.fastText && <span className={`${css2.triplePart} ${css2.tripleEffort}`}>{v.fastText}</span>}
              {account && (
                <span className={`${css2.triplePart} ${css2.tripleAccount}`} data-level={account.level}>
                  {account.profile && <ProviderLogo runtime={value.runtime} kind={account.profile.kind ?? "env"} size={14} />}
                  <span className={css2.tripleAccountName}>{account.text}</span>
                  {account.auto && <span className={css2.tripleAccountShort}>{t("web-main.model.auto")}</span>}
                  {account.profile && <span className={css2.tripleRings}><QuotaBars quota={account.profile.quota} compact small bare /></span>}
                </span>
              )}
            </>
          )}
          {/* What was picked on its way: a ring in place of the chevron, not opened again meanwhile; failed, a red mark there a few seconds. */}
          <DoingShown state={{ running: !!pick.saving, error: pick.saveFailed }} className={css2.tripleSpinner} label={t("web-main.saving")} side="top"
            idle={<ChevronDown size={12} className={chatCss.chooserChevron} />} />
        </Popover.Trigger>
      </span>
      <Popover.Portal>
        <Popover.Content className={`${controlsCss.popover} ${css2.runPickerPanel}`} side={side} align="start" sideOffset={6} collisionPadding={8}>
          {/* The accounts' panel stands beside this one: this one is what it is placed by. */}
          <Popover.Root open={showAccounts} onOpenChange={setShowAccounts}>
          <Popover.Anchor asChild><div>
          <div className={css2.runPicker}>
            <div className={`${css2.runPickerColumn} ${css2.runPickerModels}`} style={modelsWidth === null ? undefined : { width: modelsWidth }}
              ref={(el) => { if (el && modelsWidth === null) setModelsWidth(Math.ceil(parseFloat(getComputedStyle(el).width))); }}>
              <h4>{t("web-main.model.models")}</h4>
              {/* Many models: a filter; the models by series. */}
              {options.length > 8 && (
                <input className={`${controlsCss.input} ${css2.runPickerFilter}`} placeholder={t("web-main.model.search")} value={filter} onChange={(e) => setFilter(e.target.value)} autoFocus />
              )}
              {groups.map(([who, list]) => (
                <div key={who} className={`${css2.runPickerGroup} ${css.series}`}>
                  {groups.length > 1 && <h5>{who}</h5>}
                  {list.map((o) => (
                    <Tip key={o.model} label={o.ids.join("\n")}><button type="button" className={css2.runPickerOption} aria-pressed={v.option === o.model} onClick={() => pick.set({ model: o.model })}>
                      <ModelLogo maker={o.maker} runtime={o.runtimes[0] ?? value.runtime} size={14} />
                      <span className={css2.runOptionText}><span className={css2.runOptionName}>{o.name}</span>{o.spent && <span className={css2.runPickerSpent}>{o.spent.text}</span>}</span>
                    </button></Tip>
                  ))}
                </div>
              ))}
              {listed.length === 0 && <p className={`${shellCss.muted} ${css2.runPickerEmpty}`}>{t("web-main.model.noMatch")}</p>}
            </div>
            {v.runtimes.length > 0 && (
              <div className={css2.runPickerColumn}>
                <h4>{t("web-main.model.runtime")}</h4>
                {v.runtimes.map((r) => (
                  <button key={r} type="button" className={css2.runPickerOption} aria-pressed={draft.runtime === r} onClick={() => pick.set({ runtime: r })}>
                    <RuntimeLogo runtime={r} size={14} />{RUNTIME_LABEL[r]}
                  </button>
                ))}
              </div>
            )}
            <div className={`${css2.runPickerColumn} ${css2.runPickerEfforts}`}>
              <h4>{t("web-main.model.effort")}</h4>
              {[null, ...v.efforts].map((e) => (
                <button key={e ?? ""} type="button" className={css2.runPickerOption} aria-pressed={(draft.effort ?? null) === e} onClick={() => pick.set({ effort: e })}>{e ?? t("web-main.model.default")}</button>
              ))}
              {v.fastAvailable && <>
                <h4>{t("web-main.model.speed")}</h4>
                {([null, false, true] as const).map((fast) => (
                  <Tip key={String(fast)} label={fast === true ? t("web-main.model.fastNote") : null}><button type="button" className={css2.runPickerOption} aria-pressed={(draft.fast ?? null) === fast} onClick={() => pick.set({ fast })}>{fast === null ? t("web-main.model.fastSubscription") : fast ? "Fast" : t("web-main.model.standard")}</button></Tip>
                ))}
              </>}
            </div>
          </div>
          <div className={css2.runPickerFoot}>
              {/* In the room the columns leave: a long name is cut short rather than widening the panel. */}
              <span className={css2.runPickerWhoRoom}><Popover.Trigger className={css2.runPickerWho} data-level={v.whoLevel}>
                {/* Short, in the room it has: the account kept to by its name before the @; amber says the station's pick runs low, or the one kept to gave way (its panel says which). */}
                <span className={css2.runOptionName}>{v.who}</span>
                <ChevronRight size={12} className={css2.runPickerWhoChevron} />
              </Popover.Trigger></span>
            {/* Not a Popover.Close: within the accounts' Root, that would close theirs. */}
            <button type="button" className={`${controlsCss.btn} ${controlsCss.btnGhost} ${css2.btnSm}`} onClick={() => setOpen(false)}>{t("common.cancel")}</button>
            {/* Nothing changed: it says so, and only closes. */}
            <button type="button" className={v.changed ? `${controlsCss.btn} ${controlsCss.btnPrimary} ${css2.btnSm}` : `${controlsCss.btn} btn-secondary ${css2.btnSm}`} disabled={!v.option}
              onClick={() => { setOpen(false); if (v.changed) onConfirm(); }}>{v.changed ? t("common.confirm") : t("web-main.model.unchanged")}</button>
          </div>
          </div></Popover.Anchor>
              <Popover.Portal>
                {/* The accounts: a panel beside this one, its foot on this one's foot. */}
                <Popover.Content className={`${controlsCss.popover} ${css2.runPickerPanel} ${css2.runPickerAccounts}`} side="right" align="end" sideOffset={14} alignOffset={-6} collisionPadding={8}
                  onOpenAutoFocus={(e) => e.preventDefault()}>
                  <h4>{t("web-main.model.account")}</h4>
                  {v.dropped && <p className={css2.runPickerNote}>{v.dropped}</p>}
                  <button type="button" className={css2.runPickerOption} aria-pressed={!draft.profile} onClick={() => pick.set({ profile: null })}>
                    <span className={css2.runOptionText}><span className={css2.runOptionName}>{t("web-main.model.auto")}</span>
                    <span className={css2.runAccountNote}>{v.autoNote}</span></span>
                  </button>
                  {v.accounts.map((a) => (
                    <button key={a.id} type="button" className={css2.runPickerOption} aria-pressed={draft.profile === a.id} onClick={() => pick.set({ profile: a.id })}>
                      <span className={css2.runOptionText}><span className={css2.runOptionName}>{a.name}</span>
                      {a.quotaLine && <span className={css2.runAccountNote} data-level={a.quotaLine.level}>{a.quotaLine.text}</span>}</span>
                    </button>
                  ))}
                </Popover.Content>
              </Popover.Portal>
          </Popover.Root>
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}
