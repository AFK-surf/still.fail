// A station's software on its page on a narrow screen, as the Android app has it (apps/android/…/screens/Versions.kt):
// the wide screen's versions (../Versions.tsx: useSoftware, describe), one to a row on a card, then the check. What the
// wide screen says on hover is said under the name.
import type { SoftwareVersion } from "../core/shapes.ts";
import { autoUpdating, describe, DownloadChip, onBeta, useSoftware } from "../Versions.tsx";
import { lang, t } from "../i18n.ts";
import { ListCard, ListRow, SectionHeader, Spinner } from "./parts.tsx";
import * as connectsCss from "./Connects.css.ts";
import * as css from "./Versions.css.ts";

/**
 * `updates`: the station's overview's (none from a station older than them: nothing shows); `manager`: may update;
 * `beta`: the 测试版 switch is offered (the core's `betaOffered`).
 */
export function Versions({ station, updates, manager, beta = false }: { station: string; updates: SoftwareVersion[] | undefined; manager: boolean; beta?: boolean }) {
  const { update, check, channel, auto } = useSoftware(station);
  if (!updates?.length) return null;
  const checked = updates[0]?.checkedAt;
  const failed = update.error ?? check.error ?? channel.error ?? auto.error;
  const on = onBeta(updates, channel);
  const autoOn = autoUpdating(updates, auto);
  return (
    <>
      <SectionHeader title={t("web-mobile.versions.title")} trailing={checked != null ? t("web-mobile.versions.checked", { when: new Date(checked).toLocaleString(lang() === "zh" ? "zh-CN" : "en", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" }) }) : undefined} start={24} />
      <ListCard>
        {updates.map((v) => <Row key={v.id} v={v} manager={manager} busy={update.busy && update.args?.[0] === v.id} onUpdate={() => void update.run(v.id)} />)}
        {beta && manager && on != null && (
          <ListRow onClick={channel.busy ? undefined : () => void channel.run(on ? "stable" : "beta")}>
            <span className={css.mVersionText}>
              <span className={css.mVersionName}>{t("web-mobile.versions.beta")}</span>
              <span className={css.mVersionNote}>{t("web-mobile.versions.betaNote")}</span>
            </span>
            {channel.busy && <Spinner size={13} />}
            <span className={connectsCss.mSwitch} data-on={on || undefined} />
          </ListRow>
        )}
        {manager && autoOn != null && (
          <ListRow onClick={auto.busy ? undefined : () => void auto.run(!autoOn)}>
            <span className={css.mVersionText}>
              <span className={css.mVersionName}>{t("web-mobile.versions.auto")}</span>
              <span className={css.mVersionNote}>{t("web-mobile.versions.autoNote")}</span>
            </span>
            {auto.busy && <Spinner size={13} />}
            <span className={connectsCss.mSwitch} data-on={autoOn || undefined} />
          </ListRow>
        )}
        <ListRow onClick={checked == null || check.busy ? undefined : () => void check.run()}>
          <span className={css.mVersionCheck}>{checked == null ? t("web-mobile.versions.checkingFirst") : check.busy ? t("web-mobile.versions.checking") : t("web-mobile.versions.check")}</span>
          {(checked == null || check.busy) && <Spinner size={13} />}
        </ListRow>
      </ListCard>
      {failed && <p className={css.mVersionError}>{failed.message}</p>}
    </>
  );
}

function Row({ v, manager, busy, onUpdate }: { v: SoftwareVersion; manager: boolean; busy: boolean; onUpdate(): void }) {
  const { shown, failed, tip, updating, beta } = describe(v);
  const note = [v.state === "idle" ? v.done : null, tip, v.state === "failed" ? v.message : null].filter(Boolean).join(t("web-mobile.versions.noteSeparator"));
  const action = (label: string) => manager && v.updatable && (
    busy ? <Spinner size={13} /> : <button type="button" className={css.mVersionAction} onClick={onUpdate}>{label}</button>
  );
  return (
    <ListRow>
      <span className={css.mVersionText}>
        <span className={css.mVersionHead}><span className={css.mVersionName}>{v.name}</span><span className={css.mVersionShown}>{shown}</span>{beta && <span className={css.mVersionBeta}>{t("web-mobile.versions.beta")}</span>}</span>
        {note && <span className={css.mVersionNote} data-failed={v.state === "failed" || undefined}>{note}</span>}
      </span>
      {v.state === "updating" ? <span className={css.mVersionState}>{v.percent != null ? <DownloadChip percent={v.percent} /> : <Spinner size={12} />}{updating}</span>
        : v.state === "failed" ? <span className={css.mVersionState}><span className={css.mVersionNote} data-failed style={{ fontWeight: 500 }}>{failed}</span>{action(t("common.retry"))}</span>
        : !v.installed ? <span className={css.mVersionState}>{action(t("web-mobile.versions.install"))}</span>
        : v.newer && v.latest ? <span className={css.mVersionState}>→ {v.latest}{action(t("web-mobile.versions.update"))}</span>
        : v.downgrade && v.latest ? <span className={css.mVersionState}>→ {v.latest}{action(t("web-mobile.versions.downgrade"))}</span>
        : null}
    </ListRow>
  );
}
