// Logging a station in to the command-line tools its agents use (docs/remote-login.md): the login runs on the station,
// in a terminal there, and is finished here, in this person's own browser. Drawn in three places: the station page's
// 登录 list (each service it knows, how it stands, logging in; a command of one's own), the login panel (a dialog; the
// phone's sheet from the bottom) and a chat's login card. What each shows is the core's (`machineLogins`,
// `machineLogin`, `machineLoginScreen`); what is done goes through its calls, under way on its button (doing.ts), a
// failure said by a toast (useAct).
//
// The browser's step is opened here, by the person's click: a device code's page or a page to open goes straight to
// the browser (in the click, so a web page's browser lets it open); a loopback login's needs this device to take the
// browser's callback back to the station, which only the desktop app can (`canRelay`): the core listens, then answers
// what to open.
import { useContext, useEffect, useLayoutEffect, useRef, useState, type KeyboardEvent, type ReactNode } from "react";
import type { MachineLoginScreen, MachineLoginShown, MachineLoginsView, MachineService } from "./core/shapes.ts";
import { useCall, useTopic } from "./core/react.ts";
import { useDoing } from "./doing.ts";
import { useThisMachineAddress } from "./thisMachine.ts";
import { Button, Dialog, PanelButton, Section } from "./ui.tsx";
import { useAct, useToast } from "@stillfail/ui/toast.tsx";
import { ChevronRight, Key, Plus } from "@stillfail/ui/icons.tsx";
import { MobileContext } from "./mobile/narrow.ts";
import { SheetGrab, SheetHead, type MobileApp } from "./mobile/app.tsx";
import { Button as PhoneButton } from "./mobile/parts.tsx";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as spinnerCss from "@stillfail/ui/styles/spinner.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as sheetsCss from "./mobile/styles/sheets.css.ts";
import * as listsCss from "./mobile/styles/lists.css.ts";
import * as css from "./MachineLogins.css.ts";
import { t } from "./i18n.ts";

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

/** Starting a login (a service's, or a command of one's own): `then` with its id once the station has it. */
export function useStartLogin(station: string): (params: { service?: string; command?: string }, what: string, then: (id: string) => void) => void {
  const call = useCall();
  const act = useAct();
  return (params, what, then) => act(call("machineLogin.start", { station, ...params }).then((answer) => then((answer as { id: string }).id)), what);
}

// ── opening the panel ──

export interface LoginOpen { station: string; id: string; terminal?: boolean | undefined }

/**
 * Opening a login's panel: in the narrow app a sheet from the bottom, elsewhere a dialog (`panel`, to be drawn where the
 * opener is, outside anything pressed to open it). `terminal`: its terminal opened at once.
 */
export function useLoginPanel(): { open(login: LoginOpen): void; panel: ReactNode } {
  const app = useContext(MobileContext);
  const [shown, setShown] = useState<LoginOpen | null>(null);
  if (app) return { open: (login) => openLoginSheet(app, login), panel: null };
  return { open: setShown, panel: shown && <LoginPanel key={`${shown.station}/${shown.id}`} {...shown} onClose={() => setShown(null)} /> };
}

/** The phone's panel: a sheet as tall as it needs, dragged taller. */
export function openLoginSheet(app: MobileApp, login: LoginOpen): void {
  app.sheet({ height: 0.72, draggable: true, content: () => <LoginSheet {...login} /> });
}

/** The panel as a dialog (the wide screen, the desktop app). Retried, it goes on with the new login. */
export function LoginPanel({ station, id: first, terminal, onClose }: LoginOpen & { onClose(): void }) {
  const [id, setId] = useState(first);
  useEffect(() => setId(first), [first]);
  const login = useLogin(station, id);
  const logins = useMachineLogins(station);
  return (
    <Dialog open title={login?.title ?? t("web-main.logins.title")} onClose={onClose}
      footer={<LoginFoot station={station} login={login} canLogin={logins?.canLogin ?? false} onRetry={setId} />}>
      <LoginBody station={station} login={login} logins={logins} terminal={terminal} />
    </Dialog>
  );
}

function LoginSheet({ station, id: first, terminal }: LoginOpen) {
  const [id, setId] = useState(first);
  const login = useLogin(station, id);
  const logins = useMachineLogins(station);
  return (
    <>
      <SheetGrab />
      <SheetHead title={login?.title ?? t("web-main.logins.title")} />
      <div className={sheetsCss.mSheetScroll}>
        <div className={css.sheetBody}>
          <LoginBody station={station} login={login} logins={logins} terminal={terminal} />
          <div className={sheetsCss.mFormActions}><LoginEnd station={station} login={login} canLogin={logins?.canLogin ?? false} onRetry={setId} /></div>
          {login && <p className={css.sheetFoot}>{t("web-main.logins.footer", { station: login.stationName })}</p>}
        </div>
      </div>
    </>
  );
}

/** A button of the panel, as the screen it is on draws them: the phone's, or the app's pill. */
function Act({ label, primary = false, busy = false, onClick }: { label: string; primary?: boolean; busy?: boolean; onClick(): void }) {
  const phone = useContext(MobileContext) !== null;
  return phone ? <PhoneButton label={label} primary={primary} busy={busy} onClick={onClick} />
    : <Button variant={primary ? "primary" : "secondary"} busy={busy} onClick={onClick}>{label}</Button>;
}

/** The dialog's foot: where the login is and that every chat there uses it, then cancelling it or trying it again. */
function LoginFoot({ station, login, canLogin, onRetry }: { station: string; login: MachineLoginShown | null | undefined; canLogin: boolean; onRetry(id: string): void }) {
  return (
    <>
      {login && <p className={css.foot}>{t("web-main.logins.footer", { station: login.stationName })}</p>}
      <LoginEnd station={station} login={login} canLogin={canLogin} onRetry={onRetry} />
    </>
  );
}

/** Cancelling a login under way, or one that ended without logging in started again as it was (its service, its command). */
function LoginEnd({ station, login, canLogin, onRetry }: { station: string; login: MachineLoginShown | null | undefined; canLogin: boolean; onRetry(id: string): void }) {
  const call = useCall();
  const act = useAct();
  const start = useStartLogin(station);
  const again = login?.service ? { service: login.service } : { command: login?.command ?? "" };
  const cancelling = useDoing("machineLogin.cancel", { station, id: login?.id });
  const starting = useDoing("machineLogin.start", { station, ...again });
  if (!login || !canLogin) return null;
  if (login.active) return <Act label={t("common.cancel")} busy={cancelling} onClick={() => act(call("machineLogin.cancel", { station, id: login.id }), t("web-main.logins.cancelWhat"))} />;
  if (login.state === "done") return null;
  return <Act label={t("common.retry")} primary busy={starting} onClick={() => start(again, t("web-main.logins.startWhat", { name: login.name }), onRetry)} />;
}

/**
 * What the login asks of the person now: who is logged in before it goes further; then by its step the browser's
 * (loopback, device code, a page to open) and the terminal; ended, how (logged in, or why not).
 */
function LoginBody({ station, login, logins, terminal }: {
  station: string; login: MachineLoginShown | null | undefined; logins: MachineLoginsView | null | undefined; terminal?: boolean | undefined;
}) {
  if (login === undefined) return <p className={css.waitingLine}><span className={spinnerCss.spinner} aria-hidden="true" />{t("common.loading")}</p>;
  if (login === null) return <p className={css.quiet}>{t("web-main.logins.gone")}</p>;
  const canLogin = logins?.canLogin ?? false;
  const step = login.active ? login.step : undefined;
  const known = step === "loopback" || step === "device" || step === "open" || step === "terminal";
  return (
    <div className={css.body}>
      {login.before && login.active && login.state !== "verifying" && (
        <div className={css.step}>
          <p className={css.line}>{login.before}</p>
          <p className={css.quiet}>{t("web-main.logins.beforeNote")}</p>
        </div>
      )}
      {!login.active ? <Ended login={login} />
        // Nothing asked yet, or the viewer may only look: how it stands.
        : !canLogin || !step ? <p className={css.waitingLine}>{login.active && canLogin && <span className={spinnerCss.spinner} aria-hidden="true" />}{login.statusText}</p>
        : step === "loopback" ? <Loopback station={station} login={login} canRelay={logins?.canRelay ?? false} />
        : step === "device" ? <Device login={login} />
        : step === "open" || !known ? <OpenPage login={login} /> : null}
      {login.active && canLogin && <Terminal station={station} login={login} first={terminal || login.waiting || step === "terminal" || !known} />}
    </div>
  );
}

/** How it ended: logged in (as whom), or why not (the command's last lines) for trying again. */
function Ended({ login }: { login: MachineLoginShown }) {
  if (login.state === "done") return <p className={css.done}>{login.account ? t("web-main.logins.done", { account: login.account }) : login.statusText}</p>;
  return (
    <div className={css.step}>
      <p className={login.state === "cancelled" ? css.quiet : css.failed}>{login.statusText}</p>
      {login.error && <pre className={css.lastLines}>{lastLines(login.error)}</pre>}
    </div>
  );
}

/** A failure's last few lines: what the command said last is why. */
function lastLines(text: string): string {
  return text.trimEnd().split("\n").slice(-8).join("\n");
}

/** The browser's page, opened by the click itself (a web page's browser lets only that open one). */
function openPage(url: string | undefined): void {
  if (url) window.open(url, "_blank", "noopener");
}

/** Copying a device code, said for a moment on its button. */
function useCopy(text: string | undefined): [boolean, () => void] {
  const [copied, setCopied] = useState(false);
  const toast = useToast();
  useEffect(() => {
    if (!copied) return;
    const timer = setTimeout(() => setCopied(false), 1600);
    return () => clearTimeout(timer);
  }, [copied]);
  return [copied, () => { if (text) void navigator.clipboard.writeText(text).then(() => setCopied(true), (e: unknown) => toast(t("web-main.copyFailed", { error: e instanceof Error ? e.message : String(e) }))); }];
}

/**
 * A loopback login's browser, on this device: the core listens for the browser's callback (not on the station's own
 * machine: the browser comes back there by itself), then the page opens. `opened`: this device listens for it now (the
 * core's `listening`, wherever the panel was opened from), or the page was opened here on the station's own machine.
 */
function useRelay(station: string, login: MachineLoginShown): { open(): void; busy: boolean; opened: boolean } {
  const call = useCall();
  const act = useAct();
  const here = useThisMachineAddress() === station;
  const busy = useDoing("machineLogin.open", { station, id: login.id });
  const [openedHere, setOpenedHere] = useState(false);
  return {
    busy, opened: login.listening || openedHere,
    open: () => act(call("machineLogin.open", { station, id: login.id, here }).then((answer) => {
      if (here) setOpenedHere(true);
      openPage((answer as { url?: string }).url);
    }), t("web-main.logins.openWhat")),
  };
}

function Loopback({ station, login, canRelay }: { station: string; login: MachineLoginShown; canRelay: boolean }) {
  const relay = useRelay(station, login);
  const domain = login.domain ?? "";
  // A web page cannot listen for the callback: it says so, the page's domain all the same.
  if (!canRelay) {
    return (
      <div className={css.step}>
        <p className={css.line}>{t("web-main.logins.needsDesktop")}</p>
        {domain && <p className={css.quiet}>{t("web-main.logins.domain", { domain })}</p>}
      </div>
    );
  }
  return (
    <div className={css.step}>
      <p className={css.line}>{t("web-main.logins.loopback", { domain })}</p>
      <div className={css.actions}><Act label={relay.opened ? t("web-main.logins.openAgain") : t("web-main.logins.openBrowser")} primary={!relay.opened} busy={relay.busy} onClick={relay.open} /></div>
      {relay.opened && <p className={css.waitingLine}><span className={spinnerCss.spinner} aria-hidden="true" />{t("web-main.logins.waitingBrowser")}</p>}
    </div>
  );
}

function Device({ login }: { login: MachineLoginShown }) {
  const [copied, copy] = useCopy(login.code);
  return (
    <div className={css.step}>
      <p className={css.line}>{t("web-main.logins.device", { domain: login.domain ?? "" })}</p>
      {login.code && <span className={css.code}>{login.code}</span>}
      <div className={css.actions}>
        <Act label={copied ? t("common.copied") : t("common.copy")} onClick={copy} />
        <Act label={t("web-main.logins.open")} primary onClick={() => openPage(login.codeUrl ?? login.url)} />
      </div>
      <p className={css.quiet}>{t("web-main.logins.deviceNote")}</p>
    </div>
  );
}

function OpenPage({ login }: { login: MachineLoginShown }) {
  return (
    <div className={css.step}>
      <p className={css.line}>{t("web-main.logins.openStep")}</p>
      {login.domain && <p className={css.quiet}>{t("web-main.logins.domain", { domain: login.domain })}</p>}
      {login.url && <div className={css.actions}><Act label={t("web-main.logins.openBrowser")} primary onClick={() => openPage(login.url)} /></div>}
    </div>
  );
}

const KEYS = [
  { key: "Enter", label: () => t("web-main.logins.key.enter") },
  { key: "Up", label: () => "↑", name: () => t("web-main.logins.key.up") },
  { key: "Down", label: () => "↓", name: () => t("web-main.logins.key.down") },
  { key: "Tab", label: () => "Tab" },
  { key: "Ctrl-C", label: () => "Ctrl-C" },
] as const;

/**
 * The command's terminal, folded under a line that says when it waits for typing (opened by itself then): its screen
 * (read only while open), a field that sends what is typed with Enter (a password field while the command does not echo),
 * and the keys a field cannot send.
 */
function Terminal({ station, login, first }: { station: string; login: MachineLoginShown; first: boolean }) {
  const [chosen, setChosen] = useState<boolean | null>(null);
  const open = chosen ?? first;
  const screen = useTopic<MachineLoginScreen | null>(open ? { topic: "machineLoginScreen", station, id: login.id } : null).value;
  const call = useCall();
  const act = useAct();
  const [text, setText] = useState("");
  const send = (what: { text?: string; key?: string }) => call("machineLogin.input", { station, id: login.id, ...what });
  const enter = () => {
    const typed = text;
    setText("");
    // What was typed, then Enter: one after the other, in that order.
    act((typed ? send({ text: typed }) : Promise.resolve()).then(() => send({ key: "Enter" })), t("web-main.logins.sendWhat"));
  };
  const onKey = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "Enter" && !e.nativeEvent.isComposing) { e.preventDefault(); enter(); }
  };
  const phone = useContext(MobileContext) !== null;
  return (
    <div className={css.terminal}>
      <button type="button" className={css.terminalToggle} aria-expanded={open} onClick={() => setChosen(!open)}>
        <ChevronRight size={14} strokeWidth={1.7} className={css.chevron} data-open={open || undefined} />
        {t("web-main.logins.terminal")}
        {login.waiting && <span className={css.terminalWaits}>{t("web-main.logins.waitingInput")}</span>}
      </button>
      {open && (
        <>
          <Screen screen={screen} />
          <div className={css.typing}>
            <input className={`${phone ? listsCss.mField : controlsCss.input} ${css.typingField}`} type={screen && !screen.echo ? "password" : "text"}
              value={text} onChange={(e) => setText(e.target.value)} onKeyDown={onKey} autoComplete="off" autoCapitalize="off" spellCheck={false}
              placeholder={screen && !screen.echo ? t("web-main.logins.passwordHere") : t("web-main.logins.typeHere")} aria-label={t("web-main.logins.terminal")} />
          </div>
          <div className={css.keys} role="group" aria-label={t("web-main.logins.keys")}>
            {KEYS.map((k) => (
              <Button key={k.key} aria-label={"name" in k ? k.name() : undefined} onClick={() => act(send({ key: k.key }), t("web-main.logins.sendWhat"))}>{k.label()}</Button>
            ))}
          </div>
        </>
      )}
    </div>
  );
}

/** The terminal's lines, its cursor where it is; kept scrolled to its foot as lines come. */
function Screen({ screen }: { screen: MachineLoginScreen | null | undefined }) {
  const box = useRef<HTMLPreElement>(null);
  const rows = screen?.rows ?? [];
  useLayoutEffect(() => { if (box.current) box.current.scrollTop = box.current.scrollHeight; }, [rows]);
  // Lines past the cursor that hold nothing are not drawn: the station keeps a whole screen.
  let end = rows.length;
  while (end > (screen?.cursorY ?? 0) + 1 && !rows[end - 1]!.trim()) end -= 1;
  return (
    <pre ref={box} className={css.screen} aria-live="polite">
      {rows.slice(0, end).map((raw, y) => {
        const row = raw.trimEnd();
        if (!screen?.live || y !== screen.cursorY) return <div key={y} className={css.screenRow}>{row}</div>;
        const x = screen.cursorX;
        const padded = row.padEnd(x + 1, " ");
        return <div key={y} className={css.screenRow}>{padded.slice(0, x)}<span className={css.cursor}>{padded[x]}</span>{padded.slice(x + 1).trimEnd()}</div>;
      })}
    </pre>
  );
}

// ── the station page ──

/**
 * A station page's 登录 (docs/remote-login.md): the services the station knows, each with how it stands and logging in
 * (again), then a command of one's own to run. A read-only member sees how they stand only; an older station says to
 * update it.
 */
export function LoginsSection({ station }: { station: string }) {
  const view = useMachineLogins(station);
  const panel = useLoginPanel();
  if (!view) return null;
  return (
    <Section title={t("web-main.logins.title")} description={view.supported ? t("web-main.logins.lead") : undefined}>
      {!view.supported ? <p className={css.note}>{t("web-main.logins.update")}</p> : (
        <div className={pagesCss.list}>
          {view.services.map((s) => <ServiceRow key={s.id} station={station} s={s} canLogin={view.canLogin} onOpen={panel.open} />)}
          {view.canLogin && <CommandRow station={station} onOpen={panel.open} />}
        </div>
      )}
      {panel.panel}
    </Section>
  );
}

/** A service: its name and how it stands; logging in (again: its login under way goes on), where it is installed. */
function ServiceRow({ station, s, canLogin, onOpen }: { station: string; s: MachineService; canLogin: boolean; onOpen(login: LoginOpen): void }) {
  const start = useStartLogin(station);
  const busy = useDoing("machineLogin.start", { station, service: s.id });
  const label = s.login ? t("web-main.logins.continue") : s.state === "in" ? t("web-main.logins.relogin") : t("web-main.logins.login");
  const go = () => s.login ? onOpen({ station, id: s.login }) : start({ service: s.id }, t("web-main.logins.startWhat", { name: s.name }), (id) => onOpen({ station, id }));
  return (
    <div className={`${pagesCss.listRow} ${css.row}`}>
      <span className={`${pagesCss.mark} ${css.mark}`}><Key size={18} strokeWidth={1.7} /></span>
      <span className={pagesCss.cardRowText}>
        <strong className={css.name}>{s.name}</strong>
        <span className={css.state}>{s.stateText}</span>
      </span>
      {canLogin && s.installed && <Button busy={busy} onClick={go}>{label}</Button>}
    </div>
  );
}

/** 运行登录命令…: opened into a field, a command run as a login (`vercel login`), its panel opened once it is. */
function CommandRow({ station, onOpen }: { station: string; onOpen(login: LoginOpen): void }) {
  const [open, setOpen] = useState(false);
  const [command, setCommand] = useState("");
  const start = useStartLogin(station);
  const typed = command.trim();
  const busy = useDoing("machineLogin.start", { station, command: typed });
  const run = () => {
    if (!typed || busy) return;
    start({ command: typed }, t("web-main.logins.runWhat", { command: typed }), (id) => { setOpen(false); setCommand(""); onOpen({ station, id }); });
  };
  const mark = <span className={`${pagesCss.mark} ${css.mark}`}><Plus size={18} strokeWidth={1.7} /></span>;
  if (!open) {
    return <button type="button" className={`${pagesCss.listRow} ${css.commandRow}`} onClick={() => setOpen(true)}>{mark}<span className={css.commandLabel}>{t("web-main.logins.command")}</span></button>;
  }
  return (
    <div className={`${pagesCss.listRow} ${css.row}`}>
      {mark}
      <span className={css.commandForm}>
        <input className={`${controlsCss.input} ${css.commandField}`} autoFocus value={command} disabled={busy} spellCheck={false} autoCapitalize="off"
          placeholder={t("web-main.logins.commandPlaceholder")} aria-label={t("web-main.logins.command")} onChange={(e) => setCommand(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.nativeEvent.isComposing) run();
            if (e.key === "Escape") { setOpen(false); setCommand(""); }
          }} />
        <Button variant="ghost" onClick={() => { setOpen(false); setCommand(""); }}>{t("common.cancel")}</Button>
        <Button variant="primary" busy={busy} disabled={!typed} onClick={run}>{t("web-main.logins.run")}</Button>
      </span>
    </div>
  );
}

// ── a chat's card ──

/**
 * A login an agent started, in its chat (a `login` card; also on 奏): its title, how it stands, and what to do now by
 * its step (open the browser, copy the code and open its page, the terminal). Pressed anywhere else, the panel opens.
 * A login the core does not know (ended long ago) draws nothing: the message's words say it.
 */
export function LoginCard({ station, id }: { station: string; id: string }) {
  const login = useLogin(station, id);
  const logins = useMachineLogins(station);
  const panel = useLoginPanel();
  if (!login) return null;
  const open = (terminal?: boolean) => panel.open({ station, id: login.id, terminal });
  return (
    <>
      <div className={css.card} role="button" tabIndex={0} data-login-card="" onClick={() => open()}
        onKeyDown={(e) => { if (e.target === e.currentTarget && (e.key === "Enter" || e.key === " ")) { e.preventDefault(); open(); } }}>
        <span className={css.cardTitle}>{login.title}</span>
        <span className={css.cardStatus}>{login.statusText}</span>
        {login.active && logins?.canLogin && <CardActions station={station} login={login} canRelay={logins.canRelay} onTerminal={() => open(true)} />}
      </div>
      {panel.panel}
    </>
  );
}

function CardActions({ station, login, canRelay, onTerminal }: { station: string; login: MachineLoginShown; canRelay: boolean; onTerminal(): void }) {
  const relay = useRelay(station, login);
  const [copied, copy] = useCopy(login.code);
  const step = login.step;
  const known = step === "loopback" || step === "device" || step === "open" || step === "terminal";
  const buttons: ReactNode[] = [];
  const button = (key: string, label: string, onClick: () => void, filled = false, busy = false) => buttons.push(
    <PanelButton key={key} {...(filled ? { tone: "filled" as const } : {})} disabled={busy} aria-busy={busy || undefined} onClick={(e) => { e.stopPropagation(); onClick(); }}>
      <span className={css.cardButtonText}>{label}</span>
    </PanelButton>,
  );
  // A loopback login on a page that cannot take its callback: the card opens the panel, which says so.
  if (step === "loopback" && canRelay) button("open", t("web-main.logins.openBrowser"), relay.open, true, relay.busy);
  if (step === "device" && login.code) {
    button("copy", copied ? t("common.copied") : t("web-main.logins.copyCode"), copy, true);
    button("open", t("web-main.logins.open"), () => openPage(login.codeUrl ?? login.url));
  }
  if ((step === "open" || (step && !known)) && login.url) button("open", t("web-main.logins.openBrowser"), () => openPage(login.url), true);
  if (step === "terminal" || login.waiting || (step && !known)) button("terminal", t("web-main.logins.openTerminal"), onTerminal, buttons.length === 0);
  return buttons.length ? <span className={css.cardActions}>{buttons}</span> : null;
}
