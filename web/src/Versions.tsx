// A station's software and whether newer versions are out (the station's updates.rs): the station itself, Claude Code
// and Codex, each updated (or a runtime installed) from here by whoever may. Grey but for what wants doing.
import type { ReactNode } from "react";
import type { SoftwareVersion } from "./core/shapes.ts";
import { stationApi, useAction, useStationCall } from "./api.ts";
import { useDoing } from "./doing.ts";
import { DoingMark } from "./DoingMark.tsx";
import { EdgeChip } from "./components.tsx";
import { Button, Switch, Tip } from "./ui.tsx";
import { ProviderLogo } from "./ui.tsx";
import { Mark } from "./brand.tsx";
import { Server } from "./icons.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as css from "./Versions.css.ts";
import { t } from "./i18n.ts";

/**
 * `updates`: the station's overview's (none from a station older than them: nothing shows); `manager`: may update;
 * `beta`: the 测试版 switch is offered (the core's `betaOffered`).
 */
export function Versions({ station, updates, manager, beta = false }: { station: string; updates: SoftwareVersion[] | undefined; manager: boolean; beta?: boolean }) {
  const { update, check, channel, auto } = useSoftware(station);
  const batch = useDoing("software.updateAll", { station });
  if (!updates?.length) return null;
  const checked = updates[0]?.checkedAt;
  const on = onBeta(updates, channel);
  const autoOn = autoUpdating(updates, auto);
  const error = update.error ?? channel.error ?? auto.error ?? (check.error && new Error(t("web-main.versions.checkFailedWhy", { error: check.error.message })));
  return (
    <div className={css.versions}>
      {updates.map((v) => <Item key={v.id} v={v} manager={manager} busy={batch || (update.busy && update.args?.[0] === v.id)} onUpdate={() => void update.run(v.id)} />)}
      {beta && manager && on != null && (
        <label className={css.channel}>
          {t("web-main.versions.beta")}
          <Switch small checked={on} disabled={batch || channel.busy} label={t("web-main.versions.beta")} onChange={(next) => void channel.run(next ? "beta" : "stable")} />
        </label>
      )}
      {manager && autoOn != null && (
        <Tip label={updates.find((v) => v.id === "station")?.idleOnly ? t("web-main.versions.autoIdleTip") : t("web-main.versions.autoTip")}>
          <label className={css.channel}>
            {t("web-main.versions.auto")}
            <Switch small checked={autoOn} disabled={batch || auto.busy} label={t("web-main.versions.auto")} onChange={(next) => void auto.run(next)} />
          </label>
        </Tip>
      )}
      {checked == null ? <span>{t("web-main.versions.checkingVersions")}</span>
        : <Tip label={t("web-main.versions.lastChecked", { time: new Date(checked).toLocaleString() })}>
          <button type="button" className={css.check} disabled={check.busy} onClick={() => void check.run()}>{check.busy ? t("web-main.versions.checking") : t("web-main.versions.check")}</button>
        </Tip>}
      {error && <span className={css.failed}>{error.message}</span>}
    </div>
  );
}

/** Only software that needs attention on a station's overview; its full version/settings UI is in the detail. */
export function UpdateSummary({ station, updates, manager }: { station: string; updates: SoftwareVersion[] | undefined; manager: boolean }) {
  const api = stationApi(useStationCall(station));
  const update = useAction(() => api.updateAllSoftware<SoftwareVersion[]>());
  const busy = useDoing(["software.updateAll", "software.update"], { station });
  const visible = (updates ?? []).filter((v) => v.installed && ((v.updatable && (v.newer || v.downgrade)) || v.state === "updating" || v.state === "failed"));
  const updating = visible.some((v) => v.state === "updating");
  const failed = visible.some((v) => v.state === "failed");
  if (!visible.length && !busy && !update.error) return null;
  return <div className={css.summary}>
    <span className={css.summaryText}>
      {updating ? visible.map((v) => <span key={v.id} className={v.state === "failed" ? css.failed : undefined}>{t("web-main.versions.nameState", { name: v.name, state: v.state === "updating" ? describe(v).updating : v.state === "failed" ? t("web-main.versions.updateFailed") : t("web-main.versions.pending") })}</span>)
        : <span>{t("web-main.versions.nameState", { name: visible.map((v) => v.name).join(t("web-main.list.separator")), state: failed ? t("web-main.versions.updateFailed") : busy ? t("web-main.versions.updating") : visible.length ? t("web-main.versions.available") : "" })}</span>}
      {update.error && <span className={css.failed} role="alert">{update.error.message}</span>}
    </span>
    {manager && <span className={css.summaryAction}>
      <DoingMark calls={["software.updateAll", "software.update"]} on={{ station }} size={14} />
      <button type="button" className={css.action} disabled={busy || updating || !visible.some((v) => v.updatable)} onClick={() => void update.run()}>{busy || updating ? t("web-main.versions.updating") : failed ? t("common.retry") : t("web-main.versions.update")}</button>
    </span>}
  </div>;
}

/**
 * Whether the station is on the test channel, as its versions say (while a switch is going, as it was asked); null
 * when it cannot be put on one (a station older than channels, or one not updated from here).
 */
export function onBeta(updates: SoftwareVersion[], channel: ReturnType<typeof useSoftware>["channel"]): boolean | null {
  const now = updates.find((v) => v.id === "station")?.channel;
  if (now == null) return null;
  return channel.busy && channel.args ? channel.args[0] === "beta" : now === "beta";
}

/**
 * Whether the station updates itself, as its versions say (while it is being turned on or off, as it was asked); null
 * when it cannot (a station older than it, or one not updated from here).
 */
export function autoUpdating(updates: SoftwareVersion[], auto: ReturnType<typeof useSoftware>["auto"]): boolean | null {
  const now = updates.find((v) => v.id === "station")?.auto;
  if (now == null) return null;
  return auto.busy && auto.args ? auto.args[0] : now;
}

/** Updating a station's software and checking for newer versions, as both screens do (the phone's: ./mobile/Versions.tsx). */
export function useSoftware(station: string) {
  const api = stationApi(useStationCall(station));
  const update = useAction((id: string) => api.updateSoftware<SoftwareVersion[]>(id));
  const check = useAction(() => api.checkSoftware<SoftwareVersion[]>());
  const channel = useAction((to: "stable" | "beta") => api.setSoftwareChannel<SoftwareVersion[]>(to));
  const auto = useAction((on: boolean) => api.setSoftwareAuto<SoftwareVersion[]>(on));
  return { update, check, channel, auto };
}

/**
 * How a piece of software is said: its version as shown, what updating it is called, what is said about it on hover,
 * whether it is the test channel's (a 测试版 tag beside its version), and while it updates where that is (the station
 * says; one older than that, nothing more than 正在更新).
 */
export function describe(v: SoftwareVersion): { shown: string; verb: string; failed: string; tip: string; updating: string; beta: boolean } {
  return {
    shown: v.installed ? (v.version ?? (v.id === "station" ? t("web-main.versions.dev") : t("web-main.versions.unknown"))) : t("web-main.versions.notInstalled"),
    verb: v.installed ? t("web-main.versions.update") : t("web-main.versions.install"),
    failed: v.installed ? t("web-main.versions.updateFailed") : t("web-main.versions.installFailed"),
    tip: [v.note, v.installed && !v.newer && !v.downgrade && v.latest ? t("web-main.versions.latest") : null, v.installed && !v.latest && v.checkedAt ? t("web-main.versions.checkFailedRetry") : null].filter(Boolean).join(t("web-main.list.semicolon")),
    beta: v.channel === "beta",
    updating: v.progress ?? (v.installed ? t("web-main.versions.updating") : t("web-main.versions.installing")),
  };
}

function Item({ v, manager, busy, onUpdate }: { v: SoftwareVersion; manager: boolean; busy: boolean; onUpdate(): void }) {
  const { shown, failed, tip, updating, beta } = describe(v);
  const button = (label: string) => manager && v.updatable && (
    <button type="button" className={css.action} disabled={busy} onClick={onUpdate}>{label}</button>
  );
  let rest;
  if (v.state === "updating") rest = <>{v.percent != null && <DownloadChip percent={v.percent} />}<span className={css.newer}>{updating}</span></>;
  else if (v.state === "failed") rest = <><Tip label={v.message ?? ""}><span className={css.failed}>{failed}</span></Tip>{button(t("common.retry"))}</>;
  else if (!v.installed) rest = button(t("web-main.versions.install"));
  else if (v.newer && v.latest) rest = <><span className={css.newer}>→ {v.latest}</span>{button(t("web-main.versions.update"))}</>;
  else if (v.downgrade && v.latest) rest = <><span className={css.newer}>→ {v.latest}</span>{button(t("web-main.versions.backToStable"))}</>;
  else if (v.done) rest = <span className={css.newer}>{v.done}</span>;
  return (
    <span className={css.item}>
      <Tip label={tip}><span>{v.name} <span className={css.version}>{shown}</span></span></Tip>
      {beta && <span className={css.betaTag}>{t("web-main.versions.beta")}</span>}
      {rest}
    </span>
  );
}

/** How much of what a runtime's install downloads is in: the allowance's rounded box, its edge going round as it comes. */
export function DownloadChip({ percent }: { percent: number }) {
  return <EdgeChip fill={percent} level="progress" label={t("web-main.versions.downloaded", { percent })} bare />;
}

/** What a piece of software is drawn with: still.fail's mark for the station, its maker's for a runtime. */
function SoftwareMark({ id }: { id: string }) {
  if (id === "station") return <Mark size={18} />;
  if (id === "claude" || id === "codex") return <ProviderLogo runtime={id} kind="subscription" size={18} />;
  return <Server size={18} strokeWidth={1.7} />;
}

/**
 * A station's software on its own page (cloud/StationPage.tsx), a row each as the page's other lists (no card round them), its mark, name and
 * version (the test channel's tagged), what is newer and updating it at the row's end, the station's own switches (its
 * channel, updating by itself) under its version; then when it was last checked, with checking again. Grey but for what wants doing.
 */
export function SoftwareList({ station, updates, manager, beta = false }: { station: string; updates: SoftwareVersion[] | undefined; manager: boolean; beta?: boolean }) {
  const { update, check, channel, auto } = useSoftware(station);
  const batch = useDoing("software.updateAll", { station });
  if (!updates?.length) return null;
  const checked = updates[0]?.checkedAt;
  const on = onBeta(updates, channel);
  const autoOn = autoUpdating(updates, auto);
  const idle = updates.find((v) => v.id === "station")?.idleOnly;
  const error = update.error ?? channel.error ?? auto.error ?? (check.error && new Error(t("web-main.versions.checkFailedWhy", { error: check.error.message })));
  return (
    <div className={pagesCss.list}>
      {updates.map((v) => (
        <SoftwareRow key={v.id} v={v} manager={manager} busy={batch || (update.busy && update.args?.[0] === v.id)} onUpdate={() => void update.run(v.id)}>
          {/* The station's own: which releases it takes, and whether it takes them by itself. */}
          {v.id === "station" && manager && ((beta && on != null) || autoOn != null) && (
            <span className={css.softSwitches}>
              {beta && on != null && (
                <Tip label={t("web-main.versions.betaNote")}>
                  <label className={css.channel}>{t("web-main.versions.beta")}
                    <Switch small checked={on} disabled={batch || channel.busy} busy={channel.busy} label={t("web-main.versions.betaStation")} onChange={(next) => void channel.run(next ? "beta" : "stable")} />
                  </label>
                </Tip>
              )}
              {autoOn != null && (
                <Tip label={idle ? t("web-main.versions.autoIdleTip") : t("web-main.versions.autoTip")}>
                  <label className={css.channel}>{t("web-main.versions.auto")}
                    <Switch small checked={autoOn} disabled={batch || auto.busy} busy={auto.busy} label={t("web-main.versions.auto")} onChange={(next) => void auto.run(next)} />
                  </label>
                </Tip>
              )}
            </span>
          )}
        </SoftwareRow>
      ))}
      <div className={css.cardFoot}>
        <span>{checked == null ? t("web-main.versions.checkingVersions") : t("web-main.versions.lastChecked", { time: new Date(checked).toLocaleString() })}</span>
        {error && <span className={css.failed} role="alert">{error.message}</span>}
        {checked != null && <button type="button" className={css.check} disabled={check.busy} onClick={() => void check.run()}>{check.busy ? t("web-main.versions.checking") : t("web-main.versions.check")}</button>}
      </div>
    </div>
  );
}

/** `children`: what is set of it, under its version (the station's channel and updating by itself). */
function SoftwareRow({ v, manager, busy, onUpdate, children }: { v: SoftwareVersion; manager: boolean; busy: boolean; onUpdate(): void; children?: ReactNode }) {
  const { shown, failed, tip, updating, beta } = describe(v);
  const button = (label: string, primary: boolean) => manager && v.updatable && (
    <Button variant={primary ? "primary" : "secondary"} disabled={busy} onClick={onUpdate}>{label}</Button>
  );
  let rest;
  if (v.state === "updating") rest = <>{v.percent != null && <DownloadChip percent={v.percent} />}<span className={css.newer}>{updating}</span></>;
  else if (v.state === "failed") rest = <><Tip label={v.message ?? ""}><span className={css.failed} tabIndex={0}>{failed}</span></Tip>{button(t("common.retry"), false)}</>;
  else if (!v.installed) rest = button(t("web-main.versions.install"), false);
  else if (v.newer && v.latest) rest = <><span className={css.newer}>{v.latest}</span>{button(t("web-main.versions.update"), true)}</>;
  else if (v.downgrade && v.latest) rest = <><span className={css.newer}>{v.latest}</span>{button(t("web-main.versions.backToStable"), false)}</>;
  else if (v.done) rest = <span className={css.newer}>{v.done}</span>;
  return (
    <div className={`${pagesCss.listRow} ${css.softRow}`}>
      <span className={`${pagesCss.mark} ${css.softMark}`}>{<SoftwareMark id={v.id} />}</span>
      <span className={pagesCss.cardRowText}>
        <strong className={css.softName}>{v.name}{beta && !children && <span className={css.betaTag}>{t("web-main.versions.beta")}</span>}</strong>
        <Tip label={tip}><span className={css.softVersion}>{shown}</span></Tip>
        {children}
      </span>
      {rest && <span className={css.softRest}>{rest}</span>}
    </div>
  );
}
