// The Feishu (Lark) parts of the connect pages (docs/feishu.md): the wizard's platform step and its Feishu path, the
// core's (`connectFlow`); a Feishu connect's app on its page. The views draw what the core says and name what changed.
import { useEffect, useRef, useState, type ReactNode } from "react";
import { useNavigate } from "react-router";
import { CheckCircle, External, Refresh } from "@stillfail/ui/icons.tsx";
import { useToast } from "@stillfail/ui/toast.tsx";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import { useAction, useApi, type Connect } from "../api.ts";
import type { useConnectFlow } from "../connect-flow.ts";
import type { ConnectFlowView } from "../core/shapes.ts";
import { t } from "../i18n.ts";
import { ModelTriple } from "../ModelTriple.tsx";
import { QrCode } from "../QrCode.tsx";
import { profilesPage, useLink, useStation } from "../station.tsx";
import { Button, Choices, Dialog, FeishuLogo, Field, ICON, Section, SlackLogo, Spinner, SwitchRow } from "../ui.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as chatCss from "../styles/chat.css.ts";
import { Link } from "react-router";
import * as css from "./FeishuConnect.css.ts";
import * as connectCss from "./Connect.css.ts";

type Flow = ReturnType<typeof useConnectFlow>;

/** The wizard's steps that are not Slack's: the platform, then Feishu's. */
export const FEISHU_STEPS = ["platform", "feishuBind", "feishuWay", "feishuScan", "feishuApp", "done"];

/** Where a Feishu app's own fields stand, echoed as typed (the core has them a moment later). */
type Echo = { appId?: string; appSecret?: string };

/**
 * The body and footer of one of those steps, in the new-connect dialog. `mode`: the mode picker, as the Slack path has
 * it. Once its connect is added, the dialog closes onto its page.
 */
export function useFeishuStep(view: ConnectFlowView | undefined, flow: Flow, close: () => void, mode: (view: ConnectFlowView) => ReactNode): { body: ReactNode; footer: ReactNode } | null {
  const station = useStation();
  const link = useLink();
  const navigate = useNavigate();
  const toast = useToast();
  const [echo, setEcho] = useState<Echo>({});
  const made = view?.step === "done" ? (view.feishu?.connect ?? null) : null;
  const gone = useRef(false);
  // Added (by its button, or on its own once its bot was made by scanning): its page, once.
  useEffect(() => {
    if (!made || gone.current) return;
    gone.current = true;
    toast(t("web-pages.connect.feishu.added"));
    close();
    navigate(link(`/connects/${encodeURIComponent(made)}`));
  }, [made, close, navigate, link, toast]);
  if (!view || !FEISHU_STEPS.includes(view.step) || (view.step === "done" && view.platform !== "feishu")) return null;
  const f = view.feishu!;
  const step = view.step;
  const back = <Button variant="ghost" onClick={() => flow.go("back", close)}>{view.back === "close" ? t("common.cancel") : t("web-pages.connect.previous")}</Button>;
  if (step === "platform") {
    const platform = view.platform ?? "slack";
    const feishu = view.platforms.includes("feishu");
    return {
      body: (
        <Choices label={t("web-pages.connect.feishu.platform")} value={platform} onChange={(p) => flow.edit({ platform: p })} options={[
          { value: "slack", title: "Slack", description: t("web-pages.connect.feishu.slackNote"), icon: <span className={css.platformMark}><SlackLogo size={22} /></span> },
          { value: "feishu", title: t("web-pages.connect.feishu.name"), description: feishu ? t("web-pages.connect.feishu.feishuNote") : t("web-pages.connect.feishu.update"), disabled: !feishu, icon: <span className={css.platformMark}><FeishuLogo size={22} /></span> },
        ]} />
      ),
      footer: <>{back}<Button variant="primary" onClick={() => flow.go(platform === "feishu" && feishu ? "feishuBind" : "team")}>{t("web-pages.connect.next")}</Button></>,
    };
  }
  if (step === "feishuBind") {
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
      footer: <>{back}<Button variant="primary" disabled={!view.canCreate} onClick={() => flow.go("feishuWay")}>{t("web-pages.connect.next")}</Button></>,
    };
  }
  if (step === "feishuWay") {
    return {
      body: (
        <>
          <Choices label={t("web-pages.connect.feishu.way")} value={f.way} onChange={(way) => flow.edit({ feishu: { way } })} options={[
            { value: "scan", title: t("web-pages.connect.feishu.scan"), description: t("web-pages.connect.feishu.scanNote") },
            { value: "app", title: t("web-pages.connect.feishu.app"), description: t("web-pages.connect.feishu.appNote") },
          ]} />
          {flow.error && <p className={controlsCss.fieldError} role="alert">{flow.error}</p>}
        </>
      ),
      footer: <>{back}<Button variant="primary" busy={flow.busy} onClick={() => (f.way === "app" ? flow.go("feishuApp") : flow.act("register"))}>{t("web-pages.connect.next")}</Button></>,
    };
  }
  if (step === "feishuScan" || (step === "done" && f.registration)) {
    const r = f.registration;
    const waiting = r?.state === "waiting";
    return {
      body: (
        <div className={css.scan}>
          {f.qr ? <QrCode code={f.qr} size={196} label={t("web-pages.connect.feishu.qr")} />
            : <div className={css.qrPlace} aria-hidden="true">{(f.creating || r?.state === "done") && !f.error ? <Spinner /> : <FeishuLogo size={40} />}</div>}
          <div className={css.scanText}>
            <p className={f.failed || f.error ? css.scanBad : undefined} role="status">
              {(f.creating || (r?.state === "done" && !f.error && !f.connect)) && <Spinner inline />}{f.stateText}
            </p>
            {f.error && <p className={controlsCss.fieldError} role="alert">{f.error}</p>}
            {waiting && r && (
              <>
                <p className={shellCss.muted}>{t("web-pages.connect.feishu.scanHint")}</p>
                <a className={`${controlsCss.btn} btn-secondary ${css.scanOpen}`} href={r.url} target="_blank" rel="noopener"><External {...ICON} />{t("web-pages.connect.feishu.openInFeishu")}</a>
              </>
            )}
          </div>
        </div>
      ),
      footer: (
        <>
          {back}
          {f.failed ? <Button variant="primary" icon={Refresh} busy={flow.busy} onClick={() => flow.act("register")}>{t("web-pages.connect.feishu.newQr")}</Button>
            : f.error ? <Button variant="primary" busy={flow.busy || f.creating} onClick={() => flow.act("create")}>{t("web-pages.connect.feishu.retry")}</Button>
            : null}
        </>
      ),
    };
  }
  if (step === "feishuApp" || step === "done") {
    const appId = echo.appId ?? f.appId;
    const appSecret = echo.appSecret ?? f.appSecret;
    const set = (patch: Echo) => { setEcho({ ...echo, ...patch }); flow.edit({ feishu: patch }); };
    const tenant = f.identity?.tenant?.name;
    return {
      body: (
        <>
          <p className={shellCss.muted}>{t("web-pages.connect.feishu.appHint")} <a className={chatCss.inlineLink} href={f.lark ? "https://open.larksuite.com/app" : "https://open.feishu.cn/app"} target="_blank" rel="noopener">{t("web-pages.connect.feishu.openConsole")}</a></p>
          <Field label="App ID" htmlFor="feishu-app-id">
            <input id="feishu-app-id" className={controlsCss.input} data-mono="" autoComplete="off" spellCheck={false} value={appId} placeholder="cli_…" onChange={(e) => set({ appId: e.target.value })} />
          </Field>
          <Field label="App Secret" htmlFor="feishu-app-secret" error={f.errors.length > 0 ? f.errors.join("；") : undefined}>
            <input id="feishu-app-secret" className={controlsCss.input} data-mono="" type="password" autoComplete="off" spellCheck={false} value={appSecret} onChange={(e) => set({ appSecret: e.target.value })} />
          </Field>
          <SwitchRow title={t("web-pages.connect.feishu.lark")} description={t("web-pages.connect.feishu.larkNote")} checked={f.lark} onChange={(lark) => flow.edit({ feishu: { lark } })} />
          {f.verified && f.identity && (
            <span className={controlsCss.verifyOk} role="status"><CheckCircle {...ICON} />{tenant ? t("web-pages.connect.feishu.verified", { bot: f.identity.botName, tenant }) : t("web-pages.connect.feishu.verifiedBot", { bot: f.identity.botName })}</span>
          )}
          {(f.error ?? flow.error) && <p className={controlsCss.fieldError} role="alert">{f.error ?? flow.error}</p>}
        </>
      ),
      footer: (
        <>
          {back}
          {f.verified
            ? <Button variant="primary" busy={flow.busy || f.creating} onClick={() => flow.act("create")}>{t("web-pages.connect.addConnect")}</Button>
            : <Button variant="primary" disabled={!f.canVerify} busy={flow.busy} onClick={() => flow.act("verify")}>{t("web-pages.connect.feishu.verify")}</Button>}
        </>
      ),
    };
  }
  return null;
}

/** A Feishu connect's app on its page: its App ID, where it was made, its secret (masked) to replace. */
export function FeishuSection({ connect, onReplace }: { connect: Connect; onReplace(): void }) {
  const app = connect.feishu;
  if (!app) return null;
  return (
    <Section title={t("web-pages.connect.feishu.section")}>
      <div className={`${pagesCss.card} ${connectCss.runCard}`}>
        <div className={connectCss.runCardRow}>
          <span className={`${connectCss.runCardLabel} ${css.appLabel}`}>App ID</span>
          <span className={`${connectCss.runCardText} ${css.mono}`}>{app.appId}</span>
          {app.console && <a className={chatCss.textButton} href={app.console} target="_blank" rel="noopener">{t("web-pages.connect.feishu.openConsole")}</a>}
        </div>
        <div className={connectCss.runCardRow}>
          <span className={`${connectCss.runCardLabel} ${css.appLabel}`}>App Secret</span>
          <span className={`${connectCss.runCardText} ${css.mono}`}>{app.appSecret || "••••••••"}</span>
          <button type="button" className={chatCss.textButton} onClick={onReplace}>{t("web-pages.connect.feishu.replace")}</button>
        </div>
        <div className={connectCss.runCardRow}>
          <span className={`${connectCss.runCardLabel} ${css.appLabel}`}>{t("web-pages.connect.feishu.version")}</span>
          <span className={connectCss.runCardText}>{app.domain === "lark" ? "Lark" : t("web-pages.connect.feishu.name")}</span>
        </div>
      </div>
    </Section>
  );
}

/** Replaces a Feishu connect's App Secret: verified by its station before it is kept, then it reconnects. */
export function SecretDialog({ connect, onClose }: { connect: Connect; onClose(): void }) {
  const api = useApi();
  const toast = useToast();
  const [secret, setSecret] = useState("");
  const save = useAction(() => api.putFeishuSecret(connect.id, secret.trim()), () => { toast(t("web-pages.connect.feishu.secretSaved")); onClose(); });
  return (
    <Dialog open onClose={onClose} title={t("web-pages.connect.feishu.replace")} description={t("web-pages.connect.feishu.replaceLead")}
      footer={<>
        <Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button>
        <Button variant="primary" disabled={!secret.trim()} busy={save.busy} onClick={() => void save.run()}>{t("web-pages.connect.saveReconnect")}</Button>
      </>}>
      <Field label="App Secret" htmlFor="feishu-secret" error={save.error?.message}>
        <input id="feishu-secret" className={controlsCss.input} data-mono="" type="password" autoComplete="off" spellCheck={false} value={secret} placeholder={connect.feishu?.appSecret ?? ""} onChange={(e) => setSecret(e.target.value)} />
      </Field>
    </Dialog>
  );
}
