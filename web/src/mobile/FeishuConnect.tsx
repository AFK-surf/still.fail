// A new connect's platform step and its Feishu (Lark) path on a narrow screen, a step a screen, as the desktop's
// ../pages/FeishuConnect.tsx draws the same wizard of the core's (`connectFlow`).
import { useEffect, useRef, useState, type ReactNode } from "react";
import type { useConnectFlow } from "../connect-flow.ts";
import type { ConnectFlowView } from "../core/shapes.ts";
import { RUNTIME_LABEL } from "../format.ts";
import { t } from "../i18n.ts";
import { QrCode } from "../QrCode.tsx";
import { stationBase, useStation } from "../station.tsx";
import { FeishuLogo, SlackLogo } from "../ui.tsx";
import { Spinner } from "@stillfail/ui/waiting.tsx";
import { useApp } from "./app.tsx";
import { Button, GroupLabel, ListCard, MakerIcon, PickRow, Seg } from "./parts.tsx";
import * as css from "./Connects.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as settingsCss from "./styles/settings.css.ts";
import * as sheetsCss from "./styles/sheets.css.ts";

type Flow = ReturnType<typeof useConnectFlow>;

/** The steps drawn here; the rest are Slack's (./Connects.tsx). */
export const FEISHU_STEPS = ["platform", "feishuBind", "feishuWay", "feishuScan", "feishuApp", "done"];

/** The platform a new connect is on, `platform` chosen: Slack, or Feishu where the station has it (`feishu`); then on. */
export function PlatformPick({ platform, feishu, onPick, onNext }: { platform: string; feishu: boolean; onPick(platform: "slack" | "feishu"): void; onNext(): void }) {
  return (
    <>
      <ListCard>
        <PickRow label="Slack" sub={t("web-mobile.connects.feishu.slackNote")} leading={<SlackLogo size={20} />} checked={platform === "slack"} onClick={() => onPick("slack")} />
        <PickRow label={t("web-mobile.connects.feishu.name")} sub={feishu ? t("web-mobile.connects.feishu.feishuNote") : t("web-mobile.connects.feishu.update")} leading={<FeishuLogo size={20} />}
          checked={platform === "feishu"} enabled={feishu} onClick={() => onPick("feishu")} />
      </ListCard>
      <Button label={t("web-mobile.connects.next")} primary onClick={onNext} />
    </>
  );
}

/** One of those steps; `mode`: the mode picker, as the Slack path has it. Its connect added, its page replaces this one. */
export function FeishuSteps({ view, flow, mode }: { view: ConnectFlowView; flow: Flow; mode: ReactNode }) {
  const app = useApp();
  const station = useStation();
  const [echo, setEcho] = useState<{ appId?: string; appSecret?: string }>({});
  const made = view.step === "done" ? (view.feishu?.connect ?? null) : null;
  const gone = useRef(false);
  useEffect(() => {
    if (!made || gone.current) return;
    gone.current = true;
    app.toast(t("web-mobile.connects.feishu.added"));
    app.replace(`${stationBase(station.address)}/connects/${encodeURIComponent(made)}`);
  }, [made, app, station.address]);
  const f = view.feishu!;
  const busy = flow.busy;
  if (view.step === "platform") {
    const platform = view.platform ?? "slack";
    const feishu = view.platforms.includes("feishu");
    return <PlatformPick platform={platform} feishu={feishu} onPick={(platform) => flow.edit({ platform })} onNext={() => flow.go(platform === "feishu" && feishu ? "feishuBind" : "team")} />;
  }
  if (view.step === "feishuBind") {
    const models = view.pick?.options ?? [];
    const entry = view.pick?.valueOption;
    const rt = view.pick?.value.runtime ?? "claude";
    return (
      <>
        <GroupLabel>{t("web-mobile.history.model")}</GroupLabel>
        {models.length === 0 ? <p className={settingsCss.mCallout}>{t("web-mobile.connects.noModelsHere")}</p> : (
          <ListCard>{models.map((m) => <PickRow key={m.model} label={m.name} sub={m.runtimes.map((r) => RUNTIME_LABEL[r] ?? r).join(" · ")} checked={entry?.model === m.model}
            leading={<MakerIcon maker={m.maker} runtime={m.runtimes[0]} size={18} />} onClick={() => flow.choose({ model: m.model })} />)}</ListCard>
        )}
        {entry && entry.runtimes.length > 1 && (
          <>
            <GroupLabel>{t("web-mobile.connects.runtimeFixed")}</GroupLabel>
            <Seg options={entry.runtimes.map((r) => RUNTIME_LABEL[r] ?? r)} selected={Math.max(0, entry.runtimes.indexOf(rt))} onSelect={(i) => flow.choose({ runtime: entry.runtimes[i]! })} height={36} fill />
          </>
        )}
        <GroupLabel>{t("web-mobile.connects.mode")}</GroupLabel>
        {mode}
        <Button label={t("web-mobile.connects.next")} primary enabled={view.canCreate} onClick={() => flow.go("feishuWay")} />
      </>
    );
  }
  if (view.step === "feishuWay") {
    return (
      <>
        <ListCard>
          <PickRow label={t("web-mobile.connects.feishu.scan")} sub={t("web-mobile.connects.feishu.scanNote")} checked={f.way === "scan"} onClick={() => flow.edit({ feishu: { way: "scan" } })} />
          <PickRow label={t("web-mobile.connects.feishu.app")} sub={t("web-mobile.connects.feishu.appNote")} checked={f.way === "app"} onClick={() => flow.edit({ feishu: { way: "app" } })} />
        </ListCard>
        <Button label={t("web-mobile.connects.next")} primary busy={busy} onClick={() => (f.way === "app" ? flow.go("feishuApp") : flow.act("register"))} />
      </>
    );
  }
  if (view.step === "feishuScan" || (view.step === "done" && f.registration)) {
    const r = f.registration;
    const waiting = r?.state === "waiting";
    return (
      <>
        <p className={f.failed || f.error ? partsCss.mError : partsCss.mMuted} role="status">
          {(f.creating || (r?.state === "done" && !f.error && !f.connect)) && <Spinner inline />} {f.stateText}
        </p>
        {waiting && r && (
          <>
            <a className={`${partsCss.mLink} ${settingsCss.mStepAlt}`} href={r.url} target="_blank" rel="noopener">{t("web-mobile.connects.feishu.openInFeishu")}</a>
            {f.qr && <div className={css.mQr}><QrCode code={f.qr} size={220} label={t("web-mobile.connects.feishu.qr")} /></div>}
            <p className={`${partsCss.mSmall} ${partsCss.mMuted}`}>{t("web-mobile.connects.feishu.scanHint")}</p>
          </>
        )}
        {f.error && <p className={partsCss.mError}>{f.error}</p>}
        {f.failed && <Button label={t("web-mobile.connects.feishu.newQr")} primary busy={busy} onClick={() => flow.act("register")} />}
        {f.error && !f.failed && <Button label={t("web-mobile.connects.feishu.retry")} primary busy={busy || f.creating} onClick={() => flow.act("create")} />}
      </>
    );
  }
  const appId = echo.appId ?? f.appId;
  const appSecret = echo.appSecret ?? f.appSecret;
  const set = (patch: { appId?: string; appSecret?: string }) => { setEcho({ ...echo, ...patch }); flow.edit({ feishu: patch }); };
  const tenant = f.identity?.tenant?.name;
  return (
    <>
      <p className={`${partsCss.mSmall} ${partsCss.mMuted}`}>{t("web-mobile.connects.feishu.appHint")}</p>
      <b className={sheetsCss.mFormLabel}>App ID</b>
      <input className={listsCss.mField} data-mono autoComplete="off" spellCheck={false} value={appId} placeholder="cli_…" onChange={(e) => set({ appId: e.target.value })} />
      <b className={sheetsCss.mFormLabel}>App Secret</b>
      <input className={listsCss.mField} data-mono type="password" autoComplete="off" spellCheck={false} value={appSecret} onChange={(e) => set({ appSecret: e.target.value })} />
      <button type="button" className={css.mSwitchRow} onClick={() => flow.edit({ feishu: { lark: !f.lark } })}>
        <span className={partsCss.mGrow}><b>{t("web-mobile.connects.feishu.lark")}</b><span>{t("web-mobile.connects.feishu.larkNote")}</span></span>
        <span className={css.mSwitch} data-on={f.lark || undefined} />
      </button>
      {f.verified && f.identity && <span className={`${css.mGreen} ${partsCss.mSmall}`}>{tenant ? t("web-mobile.connects.feishu.verified", { bot: f.identity.botName, tenant }) : t("web-mobile.connects.feishu.verifiedBot", { bot: f.identity.botName })}</span>}
      {f.errors.map((e) => <p key={e} className={partsCss.mError}>{e}</p>)}
      {f.error && <p className={partsCss.mError}>{f.error}</p>}
      {f.verified
        ? <Button label={t("web-mobile.connects.addConnect")} primary busy={busy || f.creating} onClick={() => flow.act("create")} />
        : <Button label={t("web-mobile.connects.feishu.verify")} primary busy={busy} enabled={f.canVerify} onClick={() => flow.act("verify")} />}
    </>
  );
}
