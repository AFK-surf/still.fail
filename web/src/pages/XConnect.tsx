// The X parts of the connect pages (docs/x.md): the wizard's X path, the core's (`connectFlow`): what it runs, then the
// account's keys and the people on its list; an X connect's account on its page, its keys and list to change. The views
// draw what the core says and name what changed.
import { useEffect, useRef, useState, type ReactNode } from "react";
import { Link, useNavigate } from "react-router";
import { CheckCircle } from "@stillfail/ui/icons.tsx";
import { useToast } from "@stillfail/ui/toast.tsx";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import { useAction, useApi, type Connect } from "../api.ts";
import type { useConnectFlow } from "../connect-flow.ts";
import type { ConnectFlowView } from "../core/shapes.ts";
import { t } from "../i18n.ts";
import { ModelTriple } from "../ModelTriple.tsx";
import { profilesPage, useLink, useStation } from "../station.tsx";
import { Button, Dialog, Field, ICON, Section, SwitchRow } from "../ui.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as chatCss from "../styles/chat.css.ts";
import * as css from "./FeishuConnect.css.ts";
import * as connectCss from "./Connect.css.ts";

type Flow = ReturnType<typeof useConnectFlow>;

/** The wizard's X steps. */
export const X_STEPS = ["xBind", "xApp"];

/** Where X's developer console makes an app's keys. */
export const X_CONSOLE = "https://developer.x.com/en/portal/dashboard";

const KEYS = [
  ["consumerKey", "Consumer Key (API Key)"],
  ["consumerSecret", "Consumer Secret (API Key Secret)"],
  ["accessToken", "Access Token"],
  ["accessSecret", "Access Token Secret"],
] as const;
type KeyName = (typeof KEYS)[number][0];

/** What is typed, echoed at once (the core has it a moment later). */
type Echo = Partial<Record<KeyName | "allow", string>>;

/** The body and footer of one of the X steps, in the new-connect dialog. Once its connect is added, the dialog closes onto its page. */
export function useXStep(view: ConnectFlowView | undefined, flow: Flow, close: () => void, mode: (view: ConnectFlowView) => ReactNode): { body: ReactNode; footer: ReactNode } | null {
  const station = useStation();
  const link = useLink();
  const navigate = useNavigate();
  const toast = useToast();
  const [echo, setEcho] = useState<Echo>({});
  const made = view?.step === "done" && view.platform === "x" ? (view.x?.connect ?? null) : null;
  const gone = useRef(false);
  useEffect(() => {
    if (!made || gone.current) return;
    gone.current = true;
    toast(t("web-pages.connect.x.added"));
    close();
    navigate(link(`/connects/${encodeURIComponent(made)}`));
  }, [made, close, navigate, link, toast]);
  if (!view || !view.x || !(X_STEPS.includes(view.step) || (view.step === "done" && view.platform === "x"))) return null;
  const x = view.x;
  const back = <Button variant="ghost" onClick={() => flow.go("back", close)}>{t("web-pages.connect.previous")}</Button>;
  if (view.step === "xBind") {
    const pick = flow.pick;
    const models = pick.view?.options ?? [];
    return {
      body: (
        <>
          <Field label={t("web-pages.profiles.models")} hint={(pick.view?.valueOption?.runtimes.length ?? 0) > 1 ? t("web-pages.connect.bothRuntimes") : undefined}>
            {models.length === 0
              ? <Link className={`${controlsCss.input} ${connectCss.inputLink}`} to={profilesPage(station)}>{t("web-pages.connect.noModels")}</Link>
              : <ModelTriple pick={pick} onConfirm={() => void pick.save().catch((e: Error) => toast(e.message))} />}
          </Field>
          <Field label={t("web-pages.connect.mode")}>{mode(view)}</Field>
        </>
      ),
      footer: <>{back}<Button variant="primary" disabled={!view.canCreate} onClick={() => flow.go("xApp")}>{t("web-pages.connect.next")}</Button></>,
    };
  }
  const value = (k: KeyName | "allow") => echo[k] ?? x[k];
  const set = (patch: Echo) => { setEcho({ ...echo, ...patch }); flow.edit({ x: patch }); };
  return {
    body: (
      <>
        <p className={shellCss.muted}>{t("web-pages.connect.x.appHint")} <a className={chatCss.inlineLink} href={X_CONSOLE} target="_blank" rel="noopener">{t("web-pages.connect.x.openConsole")}</a></p>
        {KEYS.map(([k, label], i) => (
          <Field key={k} label={label} htmlFor={`x-${k}`} error={i === KEYS.length - 1 && x.errors.length > 0 ? x.errors.join("；") : undefined}>
            <input id={`x-${k}`} className={controlsCss.input} data-mono="" type={k.endsWith("Secret") ? "password" : "text"} autoComplete="off" spellCheck={false} value={value(k)} onChange={(e) => set({ [k]: e.target.value })} />
          </Field>
        ))}
        {x.verified && x.identity && <span className={controlsCss.verifyOk} role="status"><CheckCircle {...ICON} />{t("web-pages.connect.x.verified", { bot: x.identity.botName, username: x.identity.username })}</span>}
        <Field label={t("web-pages.connect.x.allow")} htmlFor="x-allow" hint={t("web-pages.connect.x.allowHint")}>
          <input id="x-allow" className={controlsCss.input} autoComplete="off" spellCheck={false} value={value("allow")} placeholder="@ada @bob" onChange={(e) => set({ allow: e.target.value })} />
        </Field>
        {(x.error ?? flow.error) && <p className={controlsCss.fieldError} role="alert">{x.error ?? flow.error}</p>}
      </>
    ),
    footer: (
      <>
        {back}
        {x.verified
          ? <Button variant="primary" disabled={!x.canCreate} busy={flow.busy || x.creating} onClick={() => flow.act("create")}>{t("web-pages.connect.addConnect")}</Button>
          : <Button variant="primary" disabled={!x.canVerify} busy={flow.busy} onClick={() => flow.act("verify")}>{t("web-pages.connect.x.verify")}</Button>}
      </>
    ),
  };
}

/** An X connect's account on its page: whose it is, its keys (masked) to replace, its list to change, whether it links. */
export function XSection({ connect, onKeys, onAllow }: { connect: Connect; onKeys(): void; onAllow(): void }) {
  const api = useApi();
  const toast = useToast();
  const save = useAction((links: boolean) => api.putConnect(connect.id, { x: { links } }), () => toast(t("web-pages.connect.x.linksSaved")));
  const account = connect.x;
  if (!account) return null;
  return (
    <Section title={t("web-pages.connect.x.section")}>
      <div className={`${pagesCss.card} ${connectCss.runCard}`}>
        <div className={connectCss.runCardRow}>
          <span className={`${connectCss.runCardLabel} ${css.appLabel}`}>{t("web-pages.connect.x.account")}</span>
          <span className={connectCss.runCardText}>{account.username ? `@${account.username}` : connect.name}</span>
          {account.profile && <a className={chatCss.textButton} href={account.profile} target="_blank" rel="noopener">{t("web-pages.connect.x.openProfile")}</a>}
        </div>
        <div className={connectCss.runCardRow}>
          <span className={`${connectCss.runCardLabel} ${css.appLabel}`}>{t("web-pages.connect.x.allow")}</span>
          <span className={`${connectCss.runCardText} ${css.mono}`}>{account.allowText || t("web-pages.connect.x.allowEmpty")}</span>
          <button type="button" className={chatCss.textButton} onClick={onAllow}>{t("web-pages.connect.x.editAllow")}</button>
        </div>
        <div className={connectCss.runCardRow}>
          <span className={`${connectCss.runCardLabel} ${css.appLabel}`}>Keys</span>
          <span className={`${connectCss.runCardText} ${css.mono}`}>{account.consumerKey || "••••"} · {account.accessToken || "••••"}</span>
          <button type="button" className={chatCss.textButton} onClick={onKeys}>{t("web-pages.connect.x.replaceKeys")}</button>
        </div>
      </div>
      <SwitchRow title={t("web-pages.connect.x.links")} description={t("web-pages.connect.x.linksNote")} checked={account.links} disabled={save.busy}
        onChange={(links) => void save.run(links)} />
    </Section>
  );
}

/** Replaces an X connect's keys (those left blank kept): verified by its station as the same account first, then it reconnects. */
export function XKeysDialog({ connect, onClose }: { connect: Connect; onClose(): void }) {
  const api = useApi();
  const toast = useToast();
  const [keys, setKeys] = useState<Partial<Record<KeyName, string>>>({});
  const given = Object.fromEntries(Object.entries(keys).map(([k, v]) => [k, (v ?? "").trim()]).filter(([, v]) => v !== ""));
  const save = useAction(() => api.putXKeys(connect.id, given), () => { toast(t("web-pages.connect.x.keysSaved")); onClose(); });
  return (
    <Dialog open onClose={onClose} title={t("web-pages.connect.x.replaceKeys")} description={t("web-pages.connect.x.replaceLead")}
      footer={<>
        <Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button>
        <Button variant="primary" disabled={Object.keys(given).length === 0} busy={save.busy} onClick={() => void save.run()}>{t("web-pages.connect.saveReconnect")}</Button>
      </>}>
      {KEYS.map(([k, label], i) => (
        <Field key={k} label={label} htmlFor={`x-replace-${k}`} error={i === KEYS.length - 1 ? save.error?.message : undefined}>
          <input id={`x-replace-${k}`} className={controlsCss.input} data-mono="" type={k.endsWith("Secret") ? "password" : "text"} autoComplete="off" spellCheck={false}
            value={keys[k] ?? ""} placeholder={connect.x?.[k] ?? ""} onChange={(e) => setKeys({ ...keys, [k]: e.target.value })} />
        </Field>
      ))}
    </Dialog>
  );
}

/** Changes an X connect's list: its handles, each looked up on X by its station before the whole list is kept. */
export function XAllowDialog({ connect, onClose }: { connect: Connect; onClose(): void }) {
  const api = useApi();
  const toast = useToast();
  const [allow, setAllow] = useState(connect.x?.allowText ?? "");
  const save = useAction(() => api.putXAllow(connect.id, allow), () => { toast(t("web-pages.connect.x.allowSaved")); onClose(); });
  return (
    <Dialog open onClose={onClose} title={t("web-pages.connect.x.editAllow")} description={t("web-pages.connect.x.allowHint")}
      footer={<>
        <Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button>
        <Button variant="primary" busy={save.busy} onClick={() => void save.run()}>{t("common.save")}</Button>
      </>}>
      <Field label={t("web-pages.connect.x.allow")} htmlFor="x-allow-edit" error={save.error?.message}>
        <input id="x-allow-edit" className={controlsCss.input} autoComplete="off" spellCheck={false} value={allow} placeholder="@ada @bob" onChange={(e) => setAllow(e.target.value)} />
      </Field>
    </Dialog>
  );
}
