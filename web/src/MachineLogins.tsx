// Logging a station in to the command-line tools its agents use (docs/remote-login.md): the login runs on the station,
// in a terminal there, and is finished here, in this person's own browser. Drawn in three places: the station page's
// 登录 (a login command to run, the tool's own, and the logins done there through still.fail), the login panel (a dialog; the
// phone's sheet from the bottom) and a chat's login card. What each shows is the core's (`machineLogins`,
// `machineLogin`, `machineLoginScreen`); what is done goes through its calls, under way on its button (doing.ts), a
// failure said by a toast (useAct).
//
// The browser's step is opened here, by the person's click: a device code's page or a page to open goes straight to
// the browser (in the click, so a web page's browser lets it open); a loopback login's needs this device to take the
// browser's callback back to the station, which only the desktop app can (`canRelay`): the core listens, then answers
// what to open.
import { useContext, useEffect, useLayoutEffect, useRef, useState, type KeyboardEvent, type ReactNode } from "react";
import type { MachineLoginScreen, MachineLoginShown, MachineLoginsView } from "./core/shapes.ts";
import { useCall, useTopic } from "./core/react.ts";
import { Link } from "react-router";
import { stationBase } from "./station.tsx";
import { useDoing } from "./doing.ts";
import { useThisMachineAddress } from "./thisMachine.ts";
import { Button, Dialog, PanelButton, Section } from "./ui.tsx";
import { useAct, useToast } from "@stillfail/ui/toast.tsx";
import { ChevronRight, Key } from "@stillfail/ui/icons.tsx";
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

/** The panel as a dialog (the wide screen, the desktop app). */
export function LoginPanel({ station, id, terminal, onClose }: LoginOpen & { onClose(): void }) {
  const login = useLogin(station, id);
  const logins = useMachineLogins(station);
  return (
    <Dialog open title={login?.title ?? t("web-main.logins.title")} onClose={onClose}
      footer={<LoginFoot station={station} login={login} canLogin={logins?.canLogin ?? false} />}>
      <LoginBody station={station} login={login} logins={logins} terminal={terminal} />
    </Dialog>
  );
}

function LoginSheet({ station, id, terminal }: LoginOpen) {
  const login = useLogin(station, id);
  const logins = useMachineLogins(station);
  return (
    <>
      <SheetGrab />
      <SheetHead title={login?.title ?? t("web-main.logins.title")} />
      <div className={sheetsCss.mSheetScroll}>
        <div className={css.sheetBody}>
          <LoginBody station={station} login={login} logins={logins} terminal={terminal} />
          <div className={sheetsCss.mFormActions}><LoginEnd station={station} login={login} canLogin={logins?.canLogin ?? false} /></div>
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
function LoginFoot({ station, login, canLogin }: { station: string; login: MachineLoginShown | null | undefined; canLogin: boolean }) {
  return (
    <>
      {login && <p className={css.foot}>{t("web-main.logins.footer", { station: login.stationName })}</p>}
      <LoginEnd station={station} login={login} canLogin={canLogin} />
    </>
  );
}

/** Cancelling a login under way (starting one again is its agent's). */
function LoginEnd({ station, login, canLogin }: { station: string; login: MachineLoginShown | null | undefined; canLogin: boolean }) {
  const call = useCall();
  const act = useAct();
  const cancelling = useDoing("machineLogin.cancel", { station, id: login?.id });
  if (!login || !canLogin || !login.active) return null;
  return <Act label={t("common.cancel")} busy={cancelling} onClick={() => act(call("machineLogin.cancel", { station, id: login.id }), t("web-main.logins.cancelWhat"))} />;
}

/**
 * What the login asks of the person now: its command, then by its step the browser's (loopback, device code, a page
 * to open) and the terminal; ended, how (logged in, or why not).
 */
function LoginBody({ station, login, logins, terminal }: {
  station: string; login: MachineLoginShown | null | undefined; logins: MachineLoginsView | null | undefined; terminal?: boolean | undefined;
}) {
  if (login === undefined) return <p className={css.waitingLine}><span className={spinnerCss.spinner} aria-hidden="true" />{t("common.loading")}</p>;
  if (login === null) return <p className={css.quiet}>{t("web-main.logins.gone")}</p>;
  const canLogin = logins?.canLogin ?? false;
  const step = login.active ? login.step : undefined;
  return (
    <div className={css.body}>
      <p className={css.commandLine}>{login.command}</p>
      {!login.active ? <Ended login={login} />
        // Nothing asked yet, or the viewer may only look: how it stands.
        // Nothing for the person yet (starting, or its agent answering the command's questions), or the viewer may only look.
        : !canLogin || !step || step === "terminal" || login.waiting ? <p className={css.waitingLine}>{login.active && canLogin && <span className={spinnerCss.spinner} aria-hidden="true" />}{login.statusText}</p>
        : step === "loopback" ? <Loopback station={station} login={login} canRelay={logins?.canRelay ?? false} />
        : step === "device" ? <Device login={login} />
        : <OpenPage login={login} />}
      {login.active && <Terminal station={station} login={login} first={terminal === true} />}
    </div>
  );
}

/** How it ended: logged in (as whom), or why not (the command's last lines) for trying again. */
function Ended({ login }: { login: MachineLoginShown }) {
  if (login.state === "done") return <p className={css.done}>{login.statusText}</p>;
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

/** Copying the code and opening its page, in one press: the code stays on show, for a clipboard that refused it. */
function copyAndOpen(login: MachineLoginShown): void {
  // Both in the press itself: the copy asked first (the page's window taking the focus could refuse it after), the page
  // opened whatever the clipboard says (a web page's browser lets only a press open one).
  if (login.code) void navigator.clipboard?.writeText(login.code).catch(() => {});
  openPage(login.codeUrl ?? login.url);
}

function Device({ login }: { login: MachineLoginShown }) {
  return (
    <div className={css.step}>
      <p className={css.line}>{t("web-main.logins.device", { domain: login.domain ?? "" })}</p>
      {login.code && <span className={css.code}>{login.code}</span>}
      <div className={css.actions}><Act label={t("web-main.logins.copyOpen")} primary onClick={() => copyAndOpen(login)} /></div>
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

/**
 * What the command shows, folded (its agent answers what it asks; the person only looks, if they like): its screen,
 * read only while open.
 */
function Terminal({ station, login, first }: { station: string; login: MachineLoginShown; first: boolean }) {
  const [open, setOpen] = useState(first);
  const screen = useTopic<MachineLoginScreen | null>(open ? { topic: "machineLoginScreen", station, id: login.id } : null).value;
  return (
    <div className={css.terminal}>
      <button type="button" className={css.terminalToggle} aria-expanded={open} onClick={() => setOpen(!open)}>
        <ChevronRight size={14} strokeWidth={1.7} className={css.chevron} data-open={open || undefined} />
        {t("web-main.logins.terminal")}
      </button>
      {open && <Screen screen={screen} />}
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
 * A station page's 登录 (docs/remote-login.md): only the logins done there through still.fail. Agents start them (用户定:
 * nobody types a command); those under way open their panel, those ended say how, which chat's agent started them and
 * who finished them. Nothing at all when there are none (or the station is from before them).
 */
export function LoginsSection({ station }: { station: string }) {
  const view = useMachineLogins(station);
  const panel = useLoginPanel();
  if (!view || !view.supported || view.logins.length === 0) return null;
  return (
    <Section title={t("web-main.logins.title")} description={t("web-main.logins.lead")}>
      <div className={pagesCss.list}>
        {view.logins.map((l) => <LoginRow key={l.id} station={station} login={l} onOpen={panel.open} />)}
      </div>
      {panel.panel}
    </Section>
  );
}

/** Which chat's agent started a login: its title, a link to it (a login ended), or as words (one under way, pressed whole). */
function StartedIn({ station, login, link }: { station: string; login: MachineLoginShown; link: boolean }) {
  if (!login.chat) return null;
  const title = login.chatTitle || t("web-main.logins.aChat");
  const words = t("web-main.logins.startedIn", { chat: "\u0000" }).split("\u0000");
  return <>{words[0]}{link ? <Link className={css.chatLink} to={`${stationBase(station)}/chats/${encodeURIComponent(login.chat)}`}>{title}</Link> : title}{words[1]}</>;
}

/** A login done here: its command, then which chat's agent started it, who finished it, when, how it stands or ended. */
function LoginRow({ station, login, onOpen }: { station: string; login: MachineLoginShown; onOpen(login: LoginOpen): void }) {
  // Who ended it says how it ended (张三 取消): the status then says nothing more.
  const rest = [login.doneByText, login.whenText, login.doneByText ? null : login.statusText].filter(Boolean).join(" · ");
  const said = (link: boolean) => (
    <span className={login.active ? css.stateActive : login.state === "failed" ? css.stateFailed : css.state}>
      {login.chat && <><StartedIn station={station} login={login} link={link} />{" · "}</>}{rest}
    </span>
  );
  const text = (link: boolean) => (
    <span className={pagesCss.cardRowText}>
      <strong className={css.name}>{login.command}</strong>
      {said(link)}
    </span>
  );
  const mark = <span className={`${pagesCss.mark} ${css.mark}`}><Key size={18} strokeWidth={1.7} /></span>;
  // Under way: pressed, its panel opens. Ended: what it says is all there is (its chat a link).
  if (login.active) {
    return (
      <button type="button" className={`${pagesCss.listRow} ${css.loginRow}`} onClick={() => onOpen({ station, id: login.id })}>
        {mark}{text(false)}<ChevronRight size={16} strokeWidth={1.7} className={css.rowChevron} />
      </button>
    );
  }
  return <div className={`${pagesCss.listRow} ${css.pastRow}`}>{mark}{text(true)}</div>;
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
        {login.active && logins?.canLogin && <CardActions station={station} login={login} canRelay={logins.canRelay} />}
      </div>
      {panel.panel}
    </>
  );
}

function CardActions({ station, login, canRelay }: { station: string; login: MachineLoginShown; canRelay: boolean }) {
  const relay = useRelay(station, login);
  const step = login.waiting ? undefined : login.step;
  const buttons: ReactNode[] = [];
  const button = (key: string, label: string, onClick: () => void, busy = false) => buttons.push(
    <PanelButton key={key} tone="filled" disabled={busy} aria-busy={busy || undefined} onClick={(e) => { e.stopPropagation(); onClick(); }}>
      <span className={css.cardButtonText}>{label}</span>
    </PanelButton>,
  );
  // A loopback login on a page that cannot take its callback: the card opens the panel, which says so.
  if (step === "loopback" && canRelay) button("open", t("web-main.logins.openBrowser"), relay.open, relay.busy);
  if (step === "device" && login.code) button("open", t("web-main.logins.copyOpen"), () => copyAndOpen(login));
  if (step === "open" && login.url) button("open", t("web-main.logins.openBrowser"), () => openPage(login.url));
  return buttons.length ? <span className={css.cardActions}>{buttons}</span> : null;
}
