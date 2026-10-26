// A new connect's X path on a narrow screen, a step a screen, as the desktop's ../pages/XConnect.tsx draws the same
// wizard of the core's (`connectFlow`); and an X connect's account on its page, its keys and list changed in sheets
// (docs/x.md).
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { stationApi, useStationCall, type Connect } from "../api.ts";
import type { useConnectFlow } from "../connect-flow.ts";
import type { ConnectFlowView } from "../core/shapes.ts";
import { useDoing } from "../doing.ts";
import { RUNTIME_LABEL } from "../format.ts";
import { t } from "../i18n.ts";
import { X_CONSOLE } from "../pages/XConnect.tsx";
import { stationBase, useStation } from "../station.tsx";
import { SheetGrab, SheetHead, useApp, type MobileApp } from "./app.tsx";
import { Button, GroupLabel, ListCard, ListRow, MakerIcon, PickRow, SectionHeader, Seg } from "./parts.tsx";
import * as css from "./Connects.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as listsCss from "./styles/lists.css.ts";
import * as settingsCss from "./styles/settings.css.ts";
import * as sheetsCss from "./styles/sheets.css.ts";

type Flow = ReturnType<typeof useConnectFlow>;

/** The steps drawn here. */
export const X_STEPS = ["xBind", "xApp"];

const KEYS = [
  ["consumerKey", "Consumer Key (API Key)"],
  ["consumerSecret", "Consumer Secret (API Key Secret)"],
  ["accessToken", "Access Token"],
  ["accessSecret", "Access Token Secret"],
] as const;
type KeyName = (typeof KEYS)[number][0];

/** The station's API in context. */
function useApi() {
  const station = useStation();
  const call = useStationCall(station.address);
  return useMemo(() => stationApi(call), [call]);
}

/** One of the X steps; `mode`: the mode picker, as the Slack path has it. Its connect added, its page replaces this one. */
export function XSteps({ view, flow, mode }: { view: ConnectFlowView; flow: Flow; mode: ReactNode }) {
  const app = useApp();
  const station = useStation();
  const [echo, setEcho] = useState<Partial<Record<KeyName | "allow", string>>>({});
  const made = view.step === "done" && view.platform === "x" ? (view.x?.connect ?? null) : null;
  const gone = useRef(false);
  useEffect(() => {
    if (!made || gone.current) return;
    gone.current = true;
    app.toast(t("web-mobile.connects.x.added"));
    app.replace(`${stationBase(station.address)}/connects/${encodeURIComponent(made)}`);
  }, [made, app, station.address]);
  const x = view.x!;
  const busy = flow.busy;
  if (view.step === "xBind") {
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
        <Button label={t("web-mobile.connects.next")} primary enabled={view.canCreate} onClick={() => flow.go("xApp")} />
      </>
    );
  }
  const value = (k: KeyName | "allow") => echo[k] ?? x[k];
  const set = (patch: Partial<Record<KeyName | "allow", string>>) => { setEcho({ ...echo, ...patch }); flow.edit({ x: patch }); };
  return (
    <>
      <p className={`${partsCss.mSmall} ${partsCss.mMuted}`}>{t("web-mobile.connects.x.appHint")} <a className={partsCss.mLink} href={X_CONSOLE} target="_blank" rel="noopener">{t("web-mobile.connects.x.openConsole")}</a></p>
      {KEYS.map(([k, label]) => (
        <span key={k} style={{ display: "contents" }}>
          <b className={sheetsCss.mFormLabel}>{label}</b>
          <input className={listsCss.mField} data-mono type={k.endsWith("Secret") ? "password" : "text"} autoComplete="off" spellCheck={false} value={value(k)} onChange={(e) => set({ [k]: e.target.value })} />
        </span>
      ))}
      {x.verified && x.identity && <span className={`${css.mGreen} ${partsCss.mSmall}`}>{t("web-mobile.connects.x.verified", { bot: x.identity.botName, username: x.identity.username })}</span>}
      {x.errors.map((e) => <p key={e} className={partsCss.mError}>{e}</p>)}
      <b className={sheetsCss.mFormLabel}>{t("web-mobile.connects.x.allow")}</b>
      <input className={listsCss.mField} autoComplete="off" spellCheck={false} value={value("allow")} placeholder="@ada @bob" onChange={(e) => set({ allow: e.target.value })} />
      <p className={`${partsCss.mSmall} ${partsCss.mMuted}`}>{t("web-mobile.connects.x.allowHint")}</p>
      {x.error && <p className={partsCss.mError}>{x.error}</p>}
      {x.verified
        ? <Button label={t("web-mobile.connects.addConnect")} primary busy={busy || x.creating} enabled={x.canCreate} onClick={() => flow.act("create")} />
        : <Button label={t("web-mobile.connects.x.verify")} primary busy={busy} enabled={x.canVerify} onClick={() => flow.act("verify")} />}
    </>
  );
}

/** An X connect's account on its page: its handle, its list, its keys (masked), whether its posts keep links. */
export function XSection({ connect }: { connect: Connect }) {
  const app = useApp();
  const api = useApi();
  const account = connect.x;
  if (!account) return null;
  return (
    <>
      <SectionHeader title={t("web-mobile.connects.x.section")} start={24} />
      <ListCard>
        <ListRow onClick={account.profile ? () => window.open(account.profile!, "_blank", "noopener") : undefined}>
          <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
            <span className={listsCss.mRowTitle}>{t("web-mobile.connects.x.account")}</span>
            <span className={listsCss.mRowNote}>{account.username ? `@${account.username}` : connect.name}</span>
          </span>
        </ListRow>
        <ListRow onClick={() => openAllow(app, connect)}>
          <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
            <span className={listsCss.mRowTitle}>{t("web-mobile.connects.x.allow")}</span>
            <span className={`${listsCss.mRowNote} ${settingsCss.mWrap}`}>{account.allowText || t("web-mobile.connects.x.allowEmpty")}</span>
          </span>
          <span className={partsCss.mLink}>{t("web-mobile.connects.x.editShort")}</span>
        </ListRow>
        <ListRow onClick={() => openKeys(app, connect)}>
          <span className={`${partsCss.mGrow} ${listsCss.mRowText}`}>
            <span className={listsCss.mRowTitle}>Keys</span>
            <span className={listsCss.mRowNote}>{account.consumerKey || "••••"} · {account.accessToken || "••••"}</span>
          </span>
          <span className={partsCss.mLink}>{t("web-mobile.connects.x.replaceShort")}</span>
        </ListRow>
      </ListCard>
      <button type="button" className={css.mSwitchRow} onClick={() => api.putConnect(connect.id, { x: { links: !account.links } }).then(() => app.toast(t("web-mobile.connects.x.linksSaved")), (e: Error) => app.toast(e.message))}>
        <span className={partsCss.mGrow}><b>{t("web-mobile.connects.x.links")}</b><span>{t("web-mobile.connects.x.linksNote")}</span></span>
        <span className={css.mSwitch} data-on={account.links || undefined} />
      </button>
    </>
  );
}

export function openKeys(app: MobileApp, connect: Connect) {
  app.sheet({ height: 0.8, draggable: true, content: () => <KeysSheet connect={connect} /> });
}

function openAllow(app: MobileApp, connect: Connect) {
  app.sheet({ height: 0.5, draggable: true, content: () => <AllowSheet connect={connect} /> });
}

/** Replaces an X connect's keys (those left blank kept): verified by its station as the same account first (so the sheet waits), then it reconnects. */
function KeysSheet({ connect }: { connect: Connect }) {
  const app = useApp();
  const api = useApi();
  const [keys, setKeys] = useState<Partial<Record<KeyName, string>>>({});
  const busy = useDoing("x.putKeys", { station: useStation().address, id: connect.id });
  const [error, setError] = useState<string | null>(null);
  const given = Object.fromEntries(Object.entries(keys).map(([k, v]) => [k, (v ?? "").trim()]).filter(([, v]) => v !== ""));
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-mobile.connects.x.replaceKeys")} />
      <div className={`${sheetsCss.mSheetScroll} ${sheetsCss.mForm}`}>
        <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{t("web-mobile.connects.x.replaceNote")}</p>
        {KEYS.map(([k, label]) => (
          <span key={k} style={{ display: "contents" }}>
            <b className={sheetsCss.mFormLabel}>{label}</b>
            <input className={listsCss.mField} data-mono type={k.endsWith("Secret") ? "password" : "text"} autoComplete="off" spellCheck={false} value={keys[k] ?? ""} placeholder={connect.x?.[k] ?? ""}
              onChange={(e) => { setKeys({ ...keys, [k]: e.target.value }); setError(null); }} />
          </span>
        ))}
        {error && <p className={partsCss.mError}>{error}</p>}
        <div className={sheetsCss.mFormActions}>
          <Button label={t("common.cancel")} primary={false} onClick={() => app.sheet(null)} />
          <Button label={t("web-mobile.connects.saveConnect")} primary busy={busy} enabled={Object.keys(given).length > 0}
            onClick={() => { api.putXKeys(connect.id, given).then(() => { app.toast(t("web-mobile.connects.x.keysSaved")); app.sheet(null); }, (e: Error) => setError(e.message)); }} />
        </div>
      </div>
    </>
  );
}

/** Changes an X connect's list: its handles, each looked up on X by its station before the whole list is kept. */
function AllowSheet({ connect }: { connect: Connect }) {
  const app = useApp();
  const api = useApi();
  const [allow, setAllow] = useState(connect.x?.allowText ?? "");
  const busy = useDoing("x.putAllow", { station: useStation().address, id: connect.id });
  const [error, setError] = useState<string | null>(null);
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-mobile.connects.x.editAllow")} />
      <div className={`${sheetsCss.mSheetScroll} ${sheetsCss.mForm}`}>
        <p className={`${partsCss.mMuted} ${partsCss.mSmall}`}>{t("web-mobile.connects.x.allowHint")}</p>
        <input className={listsCss.mField} autoComplete="off" spellCheck={false} value={allow} placeholder="@ada @bob" onChange={(e) => { setAllow(e.target.value); setError(null); }} />
        {error && <p className={partsCss.mError}>{error}</p>}
        <div className={sheetsCss.mFormActions}>
          <Button label={t("common.cancel")} primary={false} onClick={() => app.sheet(null)} />
          <Button label={t("common.save")} primary busy={busy}
            onClick={() => { api.putXAllow(connect.id, allow).then(() => { app.toast(t("web-mobile.connects.x.allowSaved")); app.sheet(null); }, (e: Error) => setError(e.message)); }} />
        </div>
      </div>
    </>
  );
}
