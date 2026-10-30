// Logging a station in to the command-line tools its agents use (docs/remote-login.md): an agent starts the login and
// answers the command's questions; the person only does the step that needs them, in their own browser. The login card
// is all of it (no panel, no second layer): in the chat under the agent's message and on the station page's 登录
// while it is under way. What it shows is the core's (`machineLogins`, `machineLogin`); what is done goes through its
// calls, under way on its button (doing.ts), a failure said by a toast (useAct).
//
// The browser's step is opened by the person's press: a device code's page (the code copied as it opens) or a page to
// open goes straight to the browser (in the press, so a web page's browser lets it open); a loopback login's needs this
// device to take the browser's callback back to the station, which only an app can (`canRelay`: the desktop app; the
// Android app's card is its own, LoginCards.kt): the core listens, then answers what to open; this device's port taken,
// the card says so. Where the station has a browser of its own (`browser`), the same step can be done there: its page
// opened in a tab of the station's browser and that tab's view opened here (screen/InStation.tsx), a loopback's callback
// coming back to the command there. Seldom used, it is in a ⋯ at the end of the step's button (docs/ui-panels.md: what
// is used least goes into the row's ⋯); the step itself where this device cannot do it (a web page and a loopback) or
// its port was taken just now. A step this client cannot do at all is said in the card.
import { useEffect, useRef, useState, type ReactNode } from "react";
import type { MachineLoginShown, MachineLoginsView } from "./core/shapes.ts";
import { useCall, useTopic } from "./core/react.ts";
import { Link } from "react-router";
import { stationBase } from "./station.tsx";
import { useDoing } from "./doing.ts";
import { Menu, PanelIconButton, Section, Spinner } from "./ui.tsx";
import { useAct } from "@stillfail/ui/toast.tsx";
import { ArrowUpRight, Close, Key, More } from "@stillfail/ui/icons.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as css from "./MachineLogins.css.ts";
import { t } from "./i18n.ts";
import { useInStation } from "./screen/InStation.tsx";

const loginsTopic = (station: string) => ({ topic: "machineLogins", station }) as const;
const loginTopic = (station: string, id: string) => ({ topic: "machineLogin", station, id }) as const;

/** A station's logins as the core has them: undefined until it answers, null where it has nothing to say. */
export function useMachineLogins(station: string): MachineLoginsView | null | undefined {
  return useTopic<MachineLoginsView | null>(loginsTopic(station)).value;
}

/** One login as it stands: undefined until the core answers, null for one it does not know (ended long ago). */
function useLogin(station: string, id: string): MachineLoginShown | null | undefined {
  return useTopic<MachineLoginShown | null>(loginTopic(station, id)).value;
}

/** The browser's page, opened by the press itself (a web page's browser lets only that open one). */
function openPage(url: string | undefined): void {
  if (url) window.open(url, "_blank", "noopener");
}

/** Copying the code and opening its page, in one press: the code stays on show, for a clipboard that refused it. */
function copyAndOpen(login: MachineLoginShown): void {
  // Both in the press itself: the copy asked first (the page's window taking the focus could refuse it after), the page
  // opened whatever the clipboard says.
  if (login.code) void navigator.clipboard?.writeText(login.code).catch(() => {});
  openPage(login.codeUrl ?? login.url);
}

/**
 * A loopback login's browser, on this device: the core listens for the browser's callback, then the page opens.
 * `opened`: this device listens for it now (the core's `listening`).
 */
function useRelay(station: string, login: MachineLoginShown): { open(): void; busy: boolean; opened: boolean } {
  const call = useCall();
  const act = useAct();
  const busy = useDoing("machineLogin.open", { station, id: login.id });
  return {
    busy, opened: login.listening,
    // This device's port taken: said on the card (the core's `relayText`), nothing opened.
    open: () => act(call("machineLogin.open", { station, id: login.id }).then((answer) => {
      openPage((answer as { url?: string }).url);
    }, (e) => { if ((e as { code?: string }).code !== "port_taken") throw e; }), t("web-main.logins.openWhat")),
  };
}

// ── the card ──

/**
 * A login, as a card (in a chat under the agent's message, on the station page while under way): its title, then
 * what the person does now (a code with 复制并打开; 在浏览器里登录; a step this client cannot do, said), or how it stands
 * (its agent answering the command), and 取消. Ended, it is a line saying how (done, failed and why, cancelled and by whom). Pressing it elsewhere does
 * nothing. A login the core does not know (ended long ago) draws nothing: the message's words say it. `marked`: the one
 * a link pointed to, brought into view.
 */
export function LoginCard({ station, id, marked = false }: { station: string; id: string; marked?: boolean }) {
  const login = useLogin(station, id);
  const logins = useMachineLogins(station);
  const box = useRef<HTMLDivElement>(null);
  useEffect(() => { if (marked && login) box.current?.scrollIntoView({ block: "center" }); }, [marked, login === undefined]); // eslint-disable-line react-hooks/exhaustive-deps
  if (!login) return null;
  const canLogin = logins?.canLogin ?? false;
  // Ended: one quiet line, as an answered decision's (已在 studio 上登录 gh), failed in red; no card.
  if (!login.active) {
    return (
      <div ref={box} className={login.state === "failed" ? css.endedFailed : css.ended} data-login-card="" data-login-ended={login.state}
        data-marked={marked || undefined}>
        {login.endedText ?? `${login.title} · ${login.statusText}`}
      </div>
    );
  }
  return (
    <div ref={box} className={css.card} data-login-card="" data-marked={marked || undefined}>
      {canLogin ? <>
        <span className={css.cardHead}><span className={css.cardTitle}>{login.title}</span><CancelLogin station={station} id={login.id} /></span>
        <ActiveCard station={station} login={login} canRelay={logins?.canRelay ?? false} />
      </> : <>
        <span className={css.cardTitle}>{login.title}</span>
        <span className={css.cardStatus}>{login.statusText}</span>
      </>}
    </div>
  );
}

/**
 * A login under way, for one who may finish it: what the person does now, by its step (or, while its agent answers the
 * command or it is starting, how it stands), then the step's own button (filled). 取消 is the card's ×, beside its title.
 * One whose page gives a code to paste back is its own (PasteSteps).
 */
function ActiveCard({ station, login, canRelay }: { station: string; login: MachineLoginShown; canRelay: boolean }) {
  const relay = useRelay(station, login);
  // Checking what came back (the browser's callback): nothing left for the person but to wait.
  const step = login.waiting || login.state === "verifying" ? undefined : login.step;
  const waiting = (words: string) => <span className={css.cardStatus}><Spinner inline />{words}</span>;
  const domain = login.domain ? <span className={css.cardStatus}>{t("web-main.logins.domain", { domain: login.domain })}</span> : null;
  // Its one button solid while it is the thing to do, a plain grey one once pressed here (as a pasted code's steps).
  const [pressed, setPressed] = useState(false);
  // The same step in the station's own browser, for the step's ⋯ (or as the step).
  const elsewhere = useStationWay(station, login);
  if (login.paste && login.url) return <PasteSteps station={station} login={login} />;
  const more = elsewhere ? [elsewhere] : [];
  let said: ReactNode = waiting(login.statusText);
  let main: ReactNode = null;
  if (step === "device" && login.code) {
    said = <><span className={css.cardStatus}>{t("web-main.logins.device", { domain: login.domain ?? "" })}</span><CardCode code={login.code} /></>;
    main = <StepButton label={t("web-main.logins.copyOpen")} solid={!pressed} more={more} onClick={() => { setPressed(true); copyAndOpen(login); }} />;
  } else if (step === "loopback" && elsewhere && (!canRelay || login.relayText)) {
    // This device cannot take the browser's callback (a web page), or its port was taken just now: the station's
    // browser, which can, is the step (this device's again in its ⋯).
    said = canRelay && login.relayText ? <><span className={css.cardStatusFailed}>{login.relayText}</span>{domain}</> : domain;
    main = <StepButton label={elsewhere.label} solid busy={elsewhere.busy} data-login-station="" onClick={elsewhere.onSelect}
      more={canRelay ? [{ label: t("web-main.logins.signIn"), onSelect: relay.open, busy: relay.busy }] : []} />;
  } else if (step === "loopback") {
    // A web page cannot take the browser's callback: said here, the page's host all the same.
    if (!canRelay) said = <><span className={css.cardStatus}>{t("web-main.logins.needsDesktop")}</span>{domain}</>;
    else {
      said = relay.opened ? waiting(t("web-main.logins.waitingBrowser"))
        : login.relayText ? <><span className={css.cardStatusFailed}>{login.relayText}</span>{domain}</> : domain;
      main = <StepButton label={relay.opened ? t("web-main.logins.openAgain") : t("web-main.logins.signIn")} solid={!relay.opened} busy={relay.busy} more={more} onClick={relay.open} />;
    }
  } else if (step === "open" && login.url) {
    said = domain;
    main = <StepButton label={t("web-main.logins.signIn")} solid={!pressed} more={more} onClick={() => { setPressed(true); openPage(login.url); }} />;
  }
  return (
    <>
      {said}
      {main}
    </>
  );
}

/** Another way of doing a step, as its ⋯ has it. */
type Way = { label: string; onSelect(): void; busy: boolean };

/**
 * The step in the station's own browser, where the station has one (none where it has not): its page opened in a tab
 * there (the one open, if it is) and the tab's view opened here, gone back from once the login ends; called 回到 … 的浏览器
 * while its tab is open.
 */
function useStationWay(station: string, login: MachineLoginShown): Way | null {
  const call = useCall();
  const open = useInStation(station);
  const busy = useDoing("machineLogin.browser", { station, id: login.id });
  if (!login.browser || !login.browserText) return null;
  const label = login.browserText;
  return { label, busy, onSelect: () => open(() => call("machineLogin.browser", { station, id: login.id }), label) };
}

/** 取消, as the card's ×: in its corner, concentric with it. */
function CancelLogin({ station, id }: { station: string; id: string }) {
  const call = useCall();
  const act = useAct();
  const cancelling = useDoing("machineLogin.cancel", { station, id });
  return (
    <PanelIconButton label={t("web-main.logins.cancelWhat")} disabled={cancelling} aria-busy={cancelling || undefined} data-login-cancel=""
      onClick={() => act(call("machineLogin.cancel", { station, id }), t("web-main.logins.cancelWhat"))}>
      <Close size={14} />
    </PanelIconButton>
  );
}

/**
 * A login whose page gives a code to paste back (Devin's, gcloud --no-launch-browser's): one line saying where to sign in
 * and what to bring back, then its two steps in the order they are done, each a row of its own (用户定: B, the page's
 * button not in the field), the eye led by which is next: 打开登录页 solid until it has been pressed here (or a code is
 * in), then the card's pill tint; the field under it, 完成 in its end once a code is in (Enter too). Sent, the code
 * stays and 完成 turns while it is checked (正在确认登录), nothing moving, until the login ends.
 */
function PasteSteps({ station, login }: { station: string; login: MachineLoginShown }) {
  const call = useCall();
  const act = useAct();
  const sending = useDoing("machineLogin.answer", { station, id: login.id });
  const elsewhere = useStationWay(station, login);
  const [opened, setOpened] = useState(false);
  const [typed, setTyped] = useState(false);
  const checking = login.state === "verifying";
  const busy = sending || checking;
  return (
    <>
      {/* Checked: said here, its spinner where 完成 was pressed. */}
      <span className={css.cardStatus}>{checking || !login.domain ? login.statusText : t("web-main.logins.pasteLead", { domain: login.domain })}</span>
      <StepButton label={t("web-main.logins.openPage")} solid={!opened && !typed && !busy} external data-login-paste-open="" more={elsewhere ? [elsewhere] : []}
        onClick={() => { setOpened(true); openPage(login.url); }} />
      <CodeField busy={busy} onTyped={setTyped}
        send={(code) => act(call("machineLogin.answer", { station, id: login.id, text: code }), t("web-main.logins.answerWhat"))} />
    </>
  );
}

/**
 * What a sign-in's page gave (a code), pasted back: a field the card's width, 完成 in its end once a code is in (solid:
 * the next thing to do then; Enter too). `busy`: sent and being checked, the code kept (read-only) and 完成 turning in
 * place, nothing moving. `onTyped`: whether a code is in, for the step above it to step back.
 */
function CodeField({ busy, send, onTyped }: { busy: boolean; send(code: string): void; onTyped?(typed: boolean): void }) {
  const placeholder = t("web-main.logins.pasteCode");
  const [code, setCode] = useState("");
  const typed = code.trim() !== "";
  const go = () => { if (typed && !busy) send(code.trim()); };
  return (
    <span className={css.cardPaste}>
      <input className={css.cardPasteInput} spellCheck={false} autoComplete="off" autoCapitalize="off" autoCorrect="off" value={code}
        placeholder={placeholder} aria-label={placeholder} data-login-paste="" readOnly={busy}
        onChange={(e) => { setCode(e.target.value); onTyped?.(e.target.value.trim() !== ""); }}
        onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing) go(); }} />
      {/* In the field's end once a code is in; busy, a spinner over its word (as wide as before). */}
      {(typed || busy) && (
        <button type="button" className={css.cardPasteDone} aria-busy={busy || undefined} data-login-paste-go="" onClick={go}>
          <span className={css.cardPasteDoneWord}>{t("web-main.logins.finish")}</span>
          {busy && <span className={css.cardPasteDoneSpin}><Spinner inline /></span>}
        </button>
      )}
    </span>
  );
}

/** The device code, pressed to copy it (and nothing opened): a toast says it is copied, or why not. */
function CardCode({ code }: { code: string }) {
  const act = useAct();
  const copy = () => act(navigator.clipboard ? navigator.clipboard.writeText(code) : Promise.reject(new Error("no clipboard")),
    t("web-main.logins.copyCodeWhat"), t("web-main.logins.codeCopied"));
  return (
    <button type="button" className={css.cardCode} aria-label={`${t("web-main.logins.copyCode")} ${code}`} title={t("web-main.logins.copyCode")}
      data-login-code="" onClick={copy}>
      <span className={css.cardCodeText}>{code}</span>
    </button>
  );
}

/**
 * A sign-in's step to press (its page, a code copied and its page): the card's width, solid while it is the next thing to
 * do, a plain grey one once it has been (the eye on to what follows). Android's profile sign-in has the same (Profiles.kt).
 * `more`: the other ways of doing it, seldom used, in a ⋯ at its end.
 */
function StepButton({ label, solid, busy = false, external = false, more = [], onClick, ...rest }: {
  label: string; solid: boolean; busy?: boolean; external?: boolean; more?: Way[]; onClick(): void; [data: `data-${string}`]: string;
}) {
  const button = (
    <button type="button" className={css.cardStep} data-next={solid || undefined} disabled={busy} aria-busy={busy || undefined} onClick={onClick} {...rest}>
      {busy && <Spinner inline />}{label}{external && <ArrowUpRight size={14} />}
    </button>
  );
  if (more.length === 0) return button;
  const otherWays = t("common.login.otherWays");
  return (
    <span className={css.cardStepRow}>
      {button}
      <Menu label={otherWays} items={more.map((w) => ({ label: w.label, onSelect: w.onSelect, disabled: w.busy }))}
        trigger={<button type="button" className={css.cardStepMore} aria-label={otherWays} title={otherWays} data-login-more=""><More size={14} /></button>} />
    </span>
  );
}

// ── the station page ──

/**
 * A station page's 登录 (docs/remote-login.md): only the logins done there through still.fail. Agents start them (用户定:
 * nobody types a command); one under way is its card, as in its chat; one ended a row saying how it ended, which chat's
 * agent started it (a link) and who ended it. Nothing at all when there are none (or the station is from before them).
 * `marked`: the login a link pointed to (`?login=`), brought into view.
 */
export function LoginsSection({ station, marked }: { station: string; marked?: string | null }) {
  const view = useMachineLogins(station);
  if (!view || !view.supported || view.logins.length === 0) return null;
  const active = view.logins.filter((l) => l.active);
  const past = view.logins.filter((l) => !l.active);
  return (
    <Section title={t("web-main.logins.title")} description={t("web-main.logins.lead")}>
      {active.length > 0 && <div className={css.cards}>{active.map((l) => <LoginCard key={l.id} station={station} id={l.id} marked={l.id === marked} />)}</div>}
      {past.length > 0 && <div className={pagesCss.list}>{past.map((l) => <PastRow key={l.id} station={station} login={l} marked={l.id === marked} />)}</div>}
    </Section>
  );
}

/** Which chat's agent started a login: its title, a link to it. */
function StartedIn({ station, login }: { station: string; login: MachineLoginShown }) {
  if (!login.chat) return null;
  const title = login.chatTitle || t("web-main.logins.aChat");
  const words = t("web-main.logins.startedIn", { chat: "\u0000" }).split("\u0000");
  return <>{words[0]}<Link className={css.chatLink} to={`${stationBase(station)}/chats/${encodeURIComponent(login.chat)}`}>{title}</Link>{words[1]}</>;
}

/**
 * A login that ended: its program (devin, as its card names it: its command line is the agent's way, not what was
 * logged in to), which chat's agent started it, how it ended, when (pressed: nothing).
 */
function PastRow({ station, login, marked }: { station: string; login: MachineLoginShown; marked: boolean }) {
  const box = useRef<HTMLDivElement>(null);
  useEffect(() => { if (marked) box.current?.scrollIntoView({ block: "center" }); }, [marked]);
  // Who ended it says how it ended (张三 取消), else the status does (已取消); then when.
  const rest = [login.doneByText || login.statusText, login.whenText].filter(Boolean).join(" · ");
  return (
    <div ref={box} className={`${pagesCss.listRow} ${css.pastRow}`} data-marked={marked || undefined}>
      <span className={`${pagesCss.mark} ${css.mark}`}><Key size={18} strokeWidth={1.7} /></span>
      <span className={pagesCss.cardRowText}>
        <strong className={css.name}>{login.name}</strong>
        <span className={login.state === "failed" ? css.stateFailed : css.state}>
          {login.chat && <><StartedIn station={station} login={login} />{" · "}</>}{rest}
        </span>
      </span>
    </div>
  );
}
