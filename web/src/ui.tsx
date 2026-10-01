// Shared controls on Radix primitives (focus, keyboard, layering and
// dismissal come from Radix), styled with ember's tokens. Pages compose these
// instead of styling their own buttons, fields or menus.
import { Mark } from "./brand.tsx";
import { shortcutOf, useKeymap, type Action } from "./keymap.ts";
import { useBackClose } from "./backClose.ts";
import { setPrefs, usePrefs } from "./prefs.ts";
import type { Badge, Maker, Stamp } from "./api.ts";
import { Chat, Check, ChevronDown, ChevronLeft, Close, Copy, Info, More, Sliders } from "./icons.tsx";
import {
  AlertDialog as RAlert, Dialog as RDialog, DropdownMenu, Label, RadioGroup, Select as RSelect, Switch as RSwitch,
  ToggleGroup, Tooltip,
} from "radix-ui";
import { flushSync } from "react-dom";
import { Link, useNavigate } from "react-router";
import { forwardRef, useEffect, useId, useRef, useState, type ButtonHTMLAttributes, type ComponentType, type CSSProperties, type ReactNode } from "react";
import * as controlsCss from "./styles/controls.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as css from "./ui.css.ts";
import * as shellCss from "./styles/shell.css.ts";
import * as chatCss from "./styles/chat.css.ts";
import * as waitingCss from "./styles/waiting.css.ts";
import { failure, useToast } from "./toast.tsx";


export const ICON = { size: 16, strokeWidth: 1.7 } as const;

type IconType = ComponentType<{ size?: number; strokeWidth?: number }>;
type Variant = "primary" | "secondary" | "ghost" | "danger" | "danger-solid";
const VARIANT: Record<Variant, string> = { primary: controlsCss.btnPrimary, secondary: "", ghost: controlsCss.btnGhost, danger: controlsCss.btnDanger, "danger-solid": controlsCss.btnDangerSolid };

export const Button = forwardRef<HTMLButtonElement, ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant; icon?: IconType; busy?: boolean | undefined }>(
  function Button({ variant = "secondary", icon: Icon, busy, children, className, ...rest }, ref) {
    return (
      <button ref={ref} type="button" {...rest} aria-busy={busy || undefined} disabled={rest.disabled || busy}
        className={`${controlsCss.btn} ${VARIANT[variant]}${className ? ` ${className}` : ""}`}>
        {busy ? <span className={waitingCss.spinner} aria-hidden="true" /> : Icon && <Icon {...ICON} />}
        {children}
      </button>
    );
  },
);

/** An icon-only button; its label shows as a tooltip and names it for screen readers. `busy`: a spinner in its place, not pressed again. */
export const IconButton = forwardRef<HTMLButtonElement, ButtonHTMLAttributes<HTMLButtonElement> & { label: string; icon: IconType; shortcut?: Action; busy?: boolean | undefined }>(
  function IconButton({ label, icon: Icon, className, shortcut, busy, ...rest }, ref) {
    return (
      <Tip label={label} {...(shortcut ? { shortcut } : {})}>
        <button ref={ref} type="button" aria-label={label} {...rest} aria-busy={busy || undefined} disabled={rest.disabled || busy}
          className={`${pagesCss.iconBtn}${className ? ` ${className}` : ""}`}>
          {busy ? <span className={`${waitingCss.spinner} ${controlsCss.iconSpinner}`} aria-hidden="true" /> : <Icon {...ICON} />}
        </button>
      </Tip>
    );
  },
);

function TipKeys({ action }: { action: Action }) {
  useKeymap();
  const keys = shortcutOf(action);
  return keys ? <span className={css.tipKeys}>{keys}</span> : null;
}

/**
 * A tip over a control; with a `shortcut`, the keys that do the same follow what it says. The only way anything here
 * explains itself on hover: no native `title`. With no label it never opens, but keeps its place in the tree.
 */
export function Tip({ label, children, side = "bottom", shortcut, cut }: { label: ReactNode; children: ReactNode; side?: "top" | "bottom" | "left" | "right"; shortcut?: Action; /** Only says what the trigger already shows, so opens only while that is cut short. */ cut?: boolean }) {
  const trigger = useRef<HTMLButtonElement>(null);
  const [open, setOpen] = useState(false);
  const root = label == null || label === "" ? { open: false }
    : cut ? { open, onOpenChange: (o: boolean) => setOpen(o && trigger.current !== null && isCut(trigger.current)) } : {};
  return (
    <Tooltip.Root {...root}>
      {/* Focus the browser does not show (a click, or a popover focusing its first item or handing focus back) opens none. */}
      <Tooltip.Trigger ref={trigger} asChild onFocus={(e) => { if (!e.currentTarget.matches(":focus-visible")) e.preventDefault(); }}>{children}</Tooltip.Trigger>
      <Tooltip.Portal>
        <Tooltip.Content className={css.tooltip} side={side} sideOffset={6} collisionPadding={8}>{label}{shortcut && <TipKeys action={shortcut} />}</Tooltip.Content>
      </Tooltip.Portal>
    </Tooltip.Root>
  );
}

/** Whether some text in an element is cut short (clipped, or ended with an ellipsis). */
function isCut(el: Element): boolean {
  return [el, ...el.querySelectorAll("*")].some((e) => e.scrollWidth > e.clientWidth + 1 && getComputedStyle(e).overflowX !== "visible");
}

/**
 * What a thing is, for whoever wants to know: a quiet mark beside it that says so on hover (or focus), in place of a
 * paragraph everyone has to read past.
 */
export function About({ children, side = "bottom" }: { children: ReactNode; side?: "top" | "bottom" | "left" | "right" }) {
  return (
    <Tip label={<span className={css.aboutText}>{children}</span>} side={side}>
      <button type="button" className={css.about} aria-label="说明"><Info size={14} strokeWidth={1.8} /></button>
    </Tip>
  );
}

export function Field({ label, hint, error, children, htmlFor, aside }:
  { label: ReactNode; hint?: ReactNode; error?: ReactNode; children: ReactNode; htmlFor?: string; aside?: ReactNode }) {
  return (
    <div className={css.field} data-invalid={Boolean(error) || undefined}>
      <div className={css.fieldTop}>
        <Label.Root className={css.fieldLabel} htmlFor={htmlFor}>{label}</Label.Root>
        {aside}
      </div>
      {children}
      {error ? <div className={controlsCss.fieldError} role="alert">{error}</div> : hint ? <div className={css.fieldHint}>{hint}</div> : null}
    </div>
  );
}

/** A small set of exclusive options shown side by side. */
export function Segmented<T extends string>({ options, value, onChange, label }:
  { options: { value: T; label: ReactNode; disabled?: boolean | undefined }[]; value: T; onChange(value: T): void; label: string }) {
  const index = Math.max(0, options.findIndex((o) => o.value === value));
  return (
    <ToggleGroup.Root type="single" className={css.segmented} aria-label={label} value={value}
      style={{ "--n": options.length, "--i": index } as CSSProperties}
      onValueChange={(v) => { if (v) onChange(v as T); }}>
      {/* The chosen option's ground is one piece that slides between options. */}
      <span className={css.segmentedThumb} aria-hidden="true" />
      {options.map((o) => (
        <ToggleGroup.Item key={o.value} value={o.value} disabled={o.disabled ?? false} className={css.segmentedOption}>{o.label}</ToggleGroup.Item>
      ))}
    </ToggleGroup.Root>
  );
}

/** Exclusive options that need a sentence each: bordered cards with a radio mark. */
export function Choices<T extends string>({ options, value, onChange, label }:
  { options: { value: T; title: ReactNode; description?: ReactNode; icon?: ReactNode; disabled?: boolean | undefined; extra?: ReactNode }[]; value: T; onChange(value: T): void; label: string }) {
  return (
    <RadioGroup.Root className={css.choices} aria-label={label} value={value} onValueChange={(v) => onChange(v as T)}>
      {options.map((o) => (
        <div key={o.value} className={css.choice} data-checked={o.value === value || undefined} data-disabled={o.disabled || undefined}>
          <RadioGroup.Item value={o.value} disabled={o.disabled ?? false} className={css.choiceHit} aria-label={typeof o.title === "string" ? o.title : undefined}>
            {o.icon}
            <span className={css.choiceText}>
              <strong>{o.title}</strong>
              {o.description && <span className={shellCss.muted}>{o.description}</span>}
            </span>
            <span className={css.radio} aria-hidden="true"><RadioGroup.Indicator className={css.radioDot} /></span>
          </RadioGroup.Item>
          {o.extra && o.value === value && <div className={css.choiceExtra}>{o.extra}</div>}
        </div>
      ))}
    </RadioGroup.Root>
  );
}

/** `small`: one to sit in a line of small text. */
/** `busy`: what it set is on its way, a small ring before it, not switched again meanwhile. */
export function Switch({ checked, onChange, label, disabled, id, small = false, busy }: { checked: boolean; onChange(checked: boolean): void; label?: string; disabled?: boolean | undefined; id?: string; small?: boolean; busy?: boolean | undefined }) {
  return (
    <>
      {busy && <span className={`${waitingCss.spinner} ${controlsCss.iconSpinner}`} role="status" aria-label="正在保存" />}
      <RSwitch.Root id={id} className={small ? `${css.switch_} ${css.switchSmall}` : css.switch_} checked={checked} onCheckedChange={onChange} disabled={(disabled || busy) ?? false} aria-busy={busy || undefined} aria-label={label}>
        <RSwitch.Thumb className={small ? `${css.switchThumb} ${css.switchThumbSmall}` : css.switchThumb} />
      </RSwitch.Root>
    </>
  );
}

/** A setting row: what it is on the left, its switch on the right. */
export function SwitchRow({ title, description, checked, onChange, disabled, busy }:
  { title: ReactNode; description?: ReactNode; checked: boolean; onChange(checked: boolean): void; disabled?: boolean | undefined; busy?: boolean | undefined }) {
  const id = useId();
  return (
    <div className={css.switchRow}>
      <Label.Root htmlFor={id} className={css.switchRowText}>
        <span>{title}</span>
        {description && <span className={shellCss.muted}>{description}</span>}
      </Label.Root>
      <Switch id={id} checked={checked} onChange={onChange} disabled={disabled ?? false} busy={busy} />
    </div>
  );
}

const NONE = "__none__";

/** A dropdown of choices. An option with value "" is allowed and stands for "not set". */
export function Select({ value, onChange, options, id, placeholder, disabled, label }: {
  value: string; onChange(value: string): void; id?: string; placeholder?: string; disabled?: boolean | undefined; label?: string;
  options: { value: string; label: ReactNode; hint?: ReactNode }[];
}) {
  // Radix reserves "" for "no selection", so an empty option travels under a stand-in value.
  const encode = (v: string) => (v === "" ? NONE : v);
  return (
    <RSelect.Root value={encode(value)} onValueChange={(v) => onChange(v === NONE ? "" : v)} disabled={disabled ?? false}>
      <RSelect.Trigger id={id} className={css.select} aria-label={label}>
        <RSelect.Value placeholder={placeholder} />
        <RSelect.Icon className={css.selectIcon}><ChevronDown {...ICON} size={14} /></RSelect.Icon>
      </RSelect.Trigger>
      <RSelect.Portal>
        <RSelect.Content className={`${controlsCss.popover} ${css.selectContent}`} position="popper" sideOffset={4} collisionPadding={8}>
          <RSelect.Viewport className={css.selectViewport}>
            {options.map((o) => (
              <RSelect.Item key={o.value} value={encode(o.value)} className={`${controlsCss.menuItem} ${css.selectItem}`}>
                <RSelect.ItemText>{o.label}</RSelect.ItemText>
                {o.hint && <span className={css.selectHint}>{o.hint}</span>}
                <RSelect.ItemIndicator className={css.selectCheck}><Check {...ICON} size={14} /></RSelect.ItemIndicator>
              </RSelect.Item>
            ))}
          </RSelect.Viewport>
        </RSelect.Content>
      </RSelect.Portal>
    </RSelect.Root>
  );
}

export type Tone = "neutral" | "green" | "blue" | "amber" | "red" | "accent";

export function Pill({ tone = "neutral", children }: { tone?: Tone; children: ReactNode }) {
  return <span className={css.pill} data-tone={tone}>{children}</span>;
}

export type Presence = "online" | "offline" | "busy" | "error";

export function StatusDot({ state, label }: { state: Presence; label?: string }) {
  return <span className={css.statusDot} data-state={state} role={label ? "img" : undefined} aria-label={label} />;
}

const AVATAR_TONES = ["#c9954c", "#6f8fbf", "#7d9a6f", "#b07a9c", "#8c83c7", "#c77d6a"];

/** A lettered tile, coloured by id, like Zork's device avatars. */
export function Avatar({ id, name, size = 20 }: { id: string; name: string; size?: number }) {
  let hash = 0;
  for (const c of id) hash = (hash * 31 + c.charCodeAt(0)) >>> 0;
  // "ember-gpt" → G: the distinguishing last word, since connects often share a prefix.
  const word = name.trim().split(/[\s\-_./]+/).filter(Boolean).at(-1) ?? name;
  const letter = ([...word][0] ?? "?").toUpperCase();
  return (
    <span className={css.avatar} aria-hidden="true"
      style={{ width: size, height: size, fontSize: Math.round(size * .52), background: AVATAR_TONES[hash % AVATAR_TONES.length], borderRadius: Math.min(size * .375, 12) }}>
      {letter}
    </span>
  );
}

export function Dialog({ open, title, description, onClose, children, footer, wide }:
  { open: boolean; title: ReactNode; description?: ReactNode; onClose(): void; children: ReactNode; footer?: ReactNode; wide?: boolean }) {
  useBackClose(open, onClose);
  return (
    <RDialog.Root open={open} onOpenChange={(next) => { if (!next) onClose(); }}>
      <RDialog.Portal>
        <RDialog.Overlay className={css.overlay} />
        {/* Focus the dialog itself rather than its first button, so the close button's tooltip does not pop up on open. */}
        <RDialog.Content className={`${css.dialog}${wide ? ` ${css.dialogWide}` : ""}`} tabIndex={-1}
          onOpenAutoFocus={(e) => { e.preventDefault(); (e.currentTarget as HTMLElement).focus(); }}>
          <div className={css.dialogHead}>
            <RDialog.Title className={css.dialogTitle}>{title}</RDialog.Title>
            <RDialog.Close asChild><IconButton label="关闭" icon={Close} /></RDialog.Close>
          </div>
          {description ? <RDialog.Description className={css.dialogLead}>{description}</RDialog.Description> : <RDialog.Description className={css.srOnly}>{title}</RDialog.Description>}
          <div className={css.dialogBody}>{children}</div>
          {footer && <div className={css.dialogFoot}>{footer}</div>}
        </RDialog.Content>
      </RDialog.Portal>
    </RDialog.Root>
  );
}

/** Asks before something that cannot be undone. `action` names what happens, e.g. "删除连接". */
/** Asks before something that cannot be undone. `error`: why it did not work, said where it was asked (it stays open). */
export function Confirm({ open, title, description, action, onConfirm, onClose, busy, error }:
  { open: boolean; title: ReactNode; description: ReactNode; action: string; onConfirm(): void; onClose(): void; busy?: boolean | undefined; error?: string | null | undefined }) {
  useBackClose(open, onClose);
  return (
    <RAlert.Root open={open} onOpenChange={(next) => { if (!next) onClose(); }}>
      <RAlert.Portal>
        <RAlert.Overlay className={css.overlay} />
        <RAlert.Content className={`${css.dialog} ${css.dialogAlert}`}>
          <RAlert.Title className={css.dialogTitle}>{title}</RAlert.Title>
          <RAlert.Description className={css.dialogLead}>{description}</RAlert.Description>
          {error && <p className={css.dialogError} role="alert">{error}</p>}
          <div className={css.dialogFoot}>
            <RAlert.Cancel asChild><Button variant="ghost">取消</Button></RAlert.Cancel>
            <Button variant="danger-solid" busy={busy ?? false} onClick={onConfirm}>{action}</Button>
          </div>
        </RAlert.Content>
      </RAlert.Portal>
    </RAlert.Root>
  );
}

export interface MenuItem { label: string; icon?: IconType; danger?: boolean; disabled?: boolean | undefined; onSelect(): void }

/** "…" menu: a list of actions on the thing it sits beside. */
export function Menu({ label = "更多操作", items }: { label?: string; items: (MenuItem | "separator")[] }) {
  return (
    <DropdownMenu.Root modal={false}>
      <DropdownMenu.Trigger asChild><IconButton label={label} icon={More} /></DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content className={`${controlsCss.popover} ${controlsCss.menuList}`} align="end" sideOffset={4} collisionPadding={8}>
          {items.map((item, i) => item === "separator" ? <DropdownMenu.Separator key={i} className={controlsCss.menuSep} /> : (
            <DropdownMenu.Item key={item.label} className={controlsCss.menuItem} data-danger={item.danger || undefined}
              disabled={item.disabled ?? false} onSelect={item.onSelect}>
              {item.icon && <item.icon {...ICON} />}
              {item.label}
            </DropdownMenu.Item>
          ))}
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}

export function CopyCommand({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);
  const toast = useToast();
  return (
    <div className={css.command}>
      <code>{text}</code>
      <IconButton label={copied ? "已复制" : "复制"} icon={copied ? Check : Copy}
        onClick={() => void navigator.clipboard.writeText(text).then(() => { setCopied(true); setTimeout(() => setCopied(false), 1600); }, (e: unknown) => toast(`没能复制：${failure(e)}`))} />
    </div>
  );
}

/**
 * A choice that opens a menu of what it can be (a model, an account): not the browser's own select, so each option can
 * show what matters about it. `trigger` draws the chosen one; the class is the look of the button.
 */
export function Chooser({ label, children, side = "bottom", className = chatCss.chooser }: { label: ReactNode; children: ReactNode; side?: "top" | "bottom"; className?: string }) {
  return (
    <DropdownMenu.Root modal={false}>
      <DropdownMenu.Trigger className={className}>{label}<ChevronDown size={12} className={chatCss.chooserChevron} /></DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content className={`${controlsCss.popover} ${controlsCss.menuList} ${chatCss.chooserMenu}`} side={side} align="start" sideOffset={6} collisionPadding={8}>{children}</DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}

export function ChooserItem({ checked, onSelect, children }: { checked: boolean; onSelect(): void; children: ReactNode }) {
  return (
    <DropdownMenu.Item className={`${controlsCss.menuItem} ${chatCss.chooserItem}`} onSelect={onSelect}>
      <span className={chatCss.chooserCheck}>{checked && <Check size={14} />}</span>{children}
    </DropdownMenu.Item>
  );
}

/** A back link that only phones show, where an opened page hides the sidebar. */
/**
 * A phone's screen, where the app is the phone's (mobile/): one column, the list or what is opened from it. Taller than
 * wide and narrow both: a small laptop's window, however narrow, stays the desktop app (whose own narrow widths only
 * fold its side panels over the page: the styles' `max-width: 1100px` blocks). Or a finger's screen no bigger than
 * 1024 either way: a phone on its side, a foldable opened (700–900 wide, some wider than tall); a tablet is bigger.
 */
export const NARROW = "(orientation: portrait) and (max-width: 700px), (pointer: coarse) and (max-width: 1024px) and (max-height: 1024px)";

/** Whether the screen is narrow (NARROW), following the window as it changes. */
export function useNarrow(): boolean {
  const [narrow, setNarrow] = useState(() => window.matchMedia(NARROW).matches);
  useEffect(() => {
    const query = window.matchMedia(NARROW);
    const update = () => setNarrow(query.matches);
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, []);
  return narrow;
}

export function MobileBack({ to, label }: { to: string; label: string }) {
  return <Link className={css.mobileBack} to={to}><ChevronLeft {...ICON} />{label}</Link>;
}

/**
 * A detail page's way back, on every screen: to the page it was opened from (a step back in history), or when it was
 * opened directly, to `to`.
 */
export function BackLink({ to, label }: { to: string; label: string }) {
  const navigate = useNavigate();
  return (
    // In a row of its own, which takes the page's column (the link alone would not line up with it).
    <div className={css.pageBackRow}>
      <Link className={css.pageBack} to={to} onClick={(e) => {
        if (((window.history.state as { idx?: number } | null)?.idx ?? 0) > 0) { e.preventDefault(); navigate(-1); }
      }}><ChevronLeft {...ICON} />{label}</Link>
    </div>
  );
}

export function Empty({ children }: { children: ReactNode }) {
  return <div className={css.empty}>{children}</div>;
}

/**
 * A list with nothing in it yet, or a page whose first step is still to take: what that first one is, in a line, and
 * the one thing to do about it. Where it shows, the page's other actions stand back (its add button, its filters), so
 * the eye goes here.
 */
export function FirstOne({ art, title, lead, children }: { art: ReactNode; title: ReactNode; lead?: ReactNode; children: ReactNode }) {
  return (
    <div className={css.firstOne}>
      {/* One of the project's scenes (brand.tsx's Illustration), not an icon on a tinted tile. */}
      {art}
      <h2 className={css.firstOneTitle}>{title}</h2>
      {lead && <p className={css.firstOneLead}>{lead}</p>}
      <div className={css.firstOneAction}>{children}</div>
    </div>
  );
}

/** A titled block of a detail page. */
export function Section({ title, actions, children, description }: { title: ReactNode; actions?: ReactNode; description?: ReactNode; children: ReactNode }) {
  const id = useId();
  return (
    <section className={pagesCss.section} aria-labelledby={id}>
      <div className={css.sectionHead}>
        <div>
          <h2 id={id}>{title}</h2>
          {description && <p className={css.sectionSub}>{description}</p>}
        </div>
        {actions && <div className={css.sectionActions}>{actions}</div>}
      </div>
      {children}
    </section>
  );
}

const KIND_ICON = { slack: SlackLogo, wechat: Chat } as const;

/** What a connect connects to, as an icon: its kind, not its identity. */
export function ConnectKindIcon({ kind, size = 16, tile }: { kind: string; size?: number; tile?: boolean }) {
  const Icon = KIND_ICON[kind as keyof typeof KIND_ICON] ?? Chat;
  const icon = <Icon size={size} strokeWidth={1.7} aria-hidden="true" />;
  return tile ? <span className={`${pagesCss.mark} ${css.kindMark}`} style={{ width: size * 2.4, height: size * 2.4 }}>{icon}</span> : <span className={css.kindIcon}>{icon}</span>;
}

/** A connect as its people see it in Slack: its bot's picture; its kind's icon until Slack has said what that is. */
export function ConnectAvatar({ connect, size = 28 }: { connect: { kind: string; botImage?: string | null | undefined }; size?: number }) {
  if (!connect.botImage) return <ConnectKindIcon kind={connect.kind} size={Math.round(size * 0.6)} tile={size > 32} />;
  return <img className={chatCss.botAvatar} src={connect.botImage} width={size} height={size} alt="" loading="lazy" referrerPolicy="no-referrer" />;
}

/** Slack's mark in its own colours, sized like the line icons around it. */
export function SlackLogo({ size = 16 }: { size?: number; strokeWidth?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 54 54" aria-hidden="true" className="slack-logo">
      <path fill="#36C5F0" d="M19.712.133a5.381 5.381 0 0 0-5.376 5.387 5.381 5.381 0 0 0 5.376 5.386h5.376V5.52A5.381 5.381 0 0 0 19.712.133m0 14.365H5.376A5.381 5.381 0 0 0 0 19.884a5.381 5.381 0 0 0 5.376 5.387h14.336a5.381 5.381 0 0 0 5.376-5.387 5.381 5.381 0 0 0-5.376-5.386" />
      <path fill="#2EB67D" d="M53.76 19.884a5.381 5.381 0 0 0-5.376-5.386 5.381 5.381 0 0 0-5.376 5.386v5.387h5.376a5.381 5.381 0 0 0 5.376-5.387m-14.336 0V5.52A5.381 5.381 0 0 0 34.048.133a5.381 5.381 0 0 0-5.376 5.387v14.364a5.381 5.381 0 0 0 5.376 5.387 5.381 5.381 0 0 0 5.376-5.387" />
      <path fill="#ECB22E" d="M34.048 54a5.381 5.381 0 0 0 5.376-5.387 5.381 5.381 0 0 0-5.376-5.386h-5.376v5.386A5.381 5.381 0 0 0 34.048 54m0-14.365h14.336a5.381 5.381 0 0 0 5.376-5.386 5.381 5.381 0 0 0-5.376-5.387H34.048a5.381 5.381 0 0 0-5.376 5.387 5.381 5.381 0 0 0 5.376 5.386" />
      <path fill="#E01E5A" d="M0 34.249a5.381 5.381 0 0 0 5.376 5.386 5.381 5.381 0 0 0 5.376-5.386v-5.387H5.376A5.381 5.381 0 0 0 0 34.249m14.336 0v14.364A5.381 5.381 0 0 0 19.712 54a5.381 5.381 0 0 0 5.376-5.387V34.249a5.381 5.381 0 0 0-5.376-5.387 5.381 5.381 0 0 0-5.376 5.387" />
    </svg>
  );
}

/**
 * Waiting on something, said in words. Appears after a short delay, so fast
 * answers do not flash it; `fill` centres it in the page.
 */
export function Loading({ label = "正在加载…", fill = true, detail }: { label?: string; fill?: boolean; detail?: ReactNode }) {
  return (
    <div className={fill ? `${css.loading} ${css.loadingFill}` : css.loading} role="status" aria-live="polite">
      <span className={waitingCss.spinner} aria-hidden="true" />
      <span>{label}{detail}</span>
    </div>
  );
}

/**
 * The app starting (or waiting for what every page needs): the buddy, floating. What it waits for is said only when
 * it takes a while (after a second), or at once when `now` (a failure).
 */
export function Splash({ label, now = false, children }: { label?: string; now?: boolean; children?: ReactNode }) {
  return (
    <div className="splash" role="status" aria-live="polite">
      <Mark size={56} className="splash-mark" />
      {label && <p className={css.splashLabel} data-now={now || undefined}>{label}</p>}
      {children}
    </div>
  );
}

/** Placeholder rows for a list that is still arriving. */
export function SkeletonRows({ count = 4 }: { count?: number }) {
  return <>{Array.from({ length: count }, (_, i) => <div key={i} className={css.skeletonRow} aria-hidden="true"><span /><span /></div>)}</>;
}

/** The agent runtimes' marks: Claude's in its orange, OpenAI's (Codex) in the text colour. Paths from simple-icons (CC0). */
export function RuntimeLogo({ runtime, size = 16 }: { runtime: "claude" | "codex"; size?: number }) {
  return runtime === "claude" ? (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-label="Claude Code" role="img" className={css.runtimeLogo}><path fill="#D97757" d="m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z" /></svg>
  ) : (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-label="Codex" role="img" className={css.runtimeLogo}><path fill="currentColor" d="M22.2819 9.8211a5.9847 5.9847 0 0 0-.5157-4.9108 6.0462 6.0462 0 0 0-6.5098-2.9A6.0651 6.0651 0 0 0 4.9807 4.1818a5.9847 5.9847 0 0 0-3.9977 2.9 6.0462 6.0462 0 0 0 .7427 7.0966 5.98 5.98 0 0 0 .511 4.9107 6.051 6.051 0 0 0 6.5146 2.9001A5.9847 5.9847 0 0 0 13.2599 24a6.0557 6.0557 0 0 0 5.7718-4.2058 5.9894 5.9894 0 0 0 3.9977-2.9001 6.0557 6.0557 0 0 0-.7475-7.0729zm-9.022 12.6081a4.4755 4.4755 0 0 1-2.8764-1.0408l.1419-.0804 4.7783-2.7582a.7948.7948 0 0 0 .3927-.6813v-6.7369l2.02 1.1686a.071.071 0 0 1 .038.052v5.5826a4.504 4.504 0 0 1-4.4945 4.4944zm-9.6607-4.1254a4.4708 4.4708 0 0 1-.5346-3.0137l.142.0852 4.783 2.7582a.7712.7712 0 0 0 .7806 0l5.8428-3.3685v2.3324a.0804.0804 0 0 1-.0332.0615L9.74 19.9502a4.4992 4.4992 0 0 1-6.1408-1.6464zM2.3408 7.8956a4.485 4.485 0 0 1 2.3655-1.9728V11.6a.7664.7664 0 0 0 .3879.6765l5.8144 3.3543-2.0201 1.1685a.0757.0757 0 0 1-.071 0l-4.8303-2.7865A4.504 4.504 0 0 1 2.3408 7.872zm16.5963 3.8558L13.1038 8.364 15.1192 7.2a.0757.0757 0 0 1 .071 0l4.8303 2.7913a4.4944 4.4944 0 0 1-.6765 8.1042v-5.6772a.79.79 0 0 0-.407-.667zm2.0107-3.0231l-.142-.0852-4.7735-2.7818a.7759.7759 0 0 0-.7854 0L9.409 9.2297V6.8974a.0662.0662 0 0 1 .0284-.0615l4.8303-2.7866a4.4992 4.4992 0 0 1 6.6802 4.66zM8.3065 12.863l-2.02-1.1638a.0804.0804 0 0 1-.038-.0567V6.0742a4.4992 4.4992 0 0 1 7.3757-3.4537l-.142.0805L8.704 5.459a.7948.7948 0 0 0-.3927.6813zm1.0976-2.3654l2.602-1.4998 2.6069 1.4998v2.9994l-2.5974 1.4997-2.6067-1.4997Z" /></svg>
  );
}

/**
 * A strip on a column's edge that drags its width. The width lives in a CSS
 * variable on the document (so every layout using it follows) and in
 * localStorage; a double click goes back to the default.
 */
export function ResizeHandle({ variable, edge, min, max, label }: { variable: string; edge: "left" | "right"; min: number; max: number; label: string }) {
  const storage = `stillfail.width.${variable}`;
  const set = (px: number | null) => {
    if (px === null) {
      document.documentElement.style.removeProperty(variable);
      localStorage.removeItem(storage);
    } else {
      document.documentElement.style.setProperty(variable, `${px}px`);
      localStorage.setItem(storage, String(px));
    }
  };
  useEffect(() => {
    const saved = Number(localStorage.getItem(storage));
    if (saved) document.documentElement.style.setProperty(variable, `${Math.min(max, Math.max(min, saved))}px`);
  }, [storage]);
  return (
    <div className={css.resizeHandle} data-edge={edge} role="separator" aria-orientation="vertical" aria-label={label}
      onDoubleClick={() => set(null)}
      onPointerDown={(e) => {
        const column = e.currentTarget.parentElement!.getBoundingClientRect();
        const handle = e.currentTarget;
        handle.setPointerCapture(e.pointerId);
        document.body.dataset.resizing = "true";
        const move = (ev: PointerEvent) => {
          const width = edge === "right" ? ev.clientX - column.left : column.right - ev.clientX;
          set(Math.round(Math.min(max, Math.max(min, width))));
        };
        const up = () => {
          handle.removeEventListener("pointermove", move);
          handle.removeEventListener("pointerup", up);
          delete document.body.dataset.resizing;
        };
        handle.addEventListener("pointermove", move);
        handle.addEventListener("pointerup", up);
        e.preventDefault();
      }} />
  );
}

/** Makers whose marks are one colour (drawn in the text's). Marks from Zork's provider set and lobehub icons (MIT). */
const MONO = new Set(["anthropic", "openai", "kimi", "xai"]);

/**
 * The mark of the company that made a model (the core says which); the runtime's mark when it does not know. No tip of
 * its own: it sits in tabs, rows and buttons that have theirs, and one thing shows one tip.
 */
export function ModelLogo({ maker, runtime, size = 14 }: { maker: Maker | null | undefined; runtime: "claude" | "codex"; size?: number }) {
  if (!maker) return <RuntimeLogo runtime={runtime} size={size} />;
  return <img className={css.modelLogo} src={`${import.meta.env.BASE_URL}models/${maker.id}.svg`} alt={maker.name} width={size} height={size} data-mono={MONO.has(maker.id) || undefined} />;
}

/** OpenCode's mark: a hollow square, drawn to match the 1.7 stroke icons. */
function OpenCodeMark({ size = 16 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} aria-hidden="true">
      <rect x="6" y="4" width="12" height="16" />
    </svg>
  );
}

/** Whose service a profile runs on: Anthropic or OpenAI for a subscription or an API key, OpenCode for OpenCode Go. */
export function ProviderLogo({ runtime, kind, size = 16 }: { runtime: "claude" | "codex"; kind: string; size?: number }) {
  if (kind === "opencode-go") return <OpenCodeMark size={size} />;
  if (kind === "env") return <Sliders size={size} strokeWidth={1.7} aria-hidden="true" />;
  return <ModelLogo maker={runtime === "claude" || kind === "anthropic-api" ? { id: "anthropic", name: "Anthropic" } : { id: "openai", name: "OpenAI" }} runtime={runtime} size={size} />;
}

/** The runtimes a profile runs, as small marks after its name: CC for Claude Code, Codex. */
export function RuntimeTags({ runtimes }: { runtimes: ("claude" | "codex")[] }) {
  return (
    <span className={waitingCss.runtimeTags}>
      {runtimes.map((r) => <Tip key={r} label={r === "claude" ? "Claude Code" : "Codex"}><span className={waitingCss.runtimeTag}><RuntimeLogo runtime={r} size={12} />{r === "claude" ? "CC" : "Codex"}</span></Tip>)}
    </span>
  );
}

/** An agent as the phone shows it: its model's maker on a tile, and where it stands as a badge. */
export function AgentMark({ maker, runtime, badge, badgeText, size = 20 }: { maker: Maker | null | undefined; runtime: "claude" | "codex"; badge: Badge | undefined; badgeText?: string | undefined; size?: number }) {
  return (
    <span className={css.agentMark} style={{ "--mark": `${size}px` } as CSSProperties} data-badge={badge ?? undefined} role="img" aria-label={badgeText ?? undefined}>
      <ModelLogo maker={maker} runtime={runtime} size={Math.round(size * 0.62)} />
    </span>
  );
}

/** Every relative time on the page follows one switch, kept on this device (prefs.ts): a click on any of them flips all between "3 分钟前" and the date. */
function useAbsoluteTime(): [boolean, () => void] {
  const absolute = usePrefs().absoluteTime;
  return [absolute, () => setPrefs({ absoluteTime: !absolute })];
}

/** A time as the core says it (fresh each minute): relative by default; clicking flips every time on the page to absolute and back. `fixed`: always relative, not a switch (the sidebar's), the date on hover. */
export function Time({ stamp, className, fixed = false }: { stamp: Stamp | undefined; className?: string; fixed?: boolean }) {
  const [switched, flip] = useAbsoluteTime();
  if (!stamp) return null;
  const absolute = switched && !fixed;
  return (
    <Tip label={absolute ? stamp.ago : stamp.full}><time className={`${fixed ? "" : css.timeToggle}${className ? ` ${className}` : ""}`.trim()} dateTime={new Date(stamp.at).toISOString()}
      onClick={fixed ? undefined : (e) => { e.preventDefault(); e.stopPropagation(); flip(); }}>
      {absolute ? stamp.full : stamp.ago}
    </time></Tip>
  );
}

let changing: { settle: (() => void)[]; moving: Promise<void>; done: Promise<void> } | null = null;
/**
 * While a page change (transitionTo) is under way: `settle` is run once the next page is there, as its picture is about
 * to be taken; `moving` is when the change starts to move, `done` when it is over. Else null.
 */
export function pageChanging(): { settle: (() => void)[]; moving: Promise<void>; done: Promise<void> } | null {
  return changing;
}

/**
 * One page becoming another in a view transition (what both have and name moves between them; the rest crossfades):
 * `go` navigates, rendered at once; with `ready`, the new page is waited for (a little) until it shows what the
 * transition lands on. `patience`: how long (ms) the new page is waited for at most. Plainly without the API or motion.
 * Resolves when it is over.
 */
export function transitionTo(go: () => void, ready?: () => boolean, patience = 800): Promise<void> {
  if (!document.startViewTransition || window.matchMedia("(prefers-reduced-motion: reduce)").matches) { go(); return Promise.resolve(); }
  // What is named for it only while it runs (its styles): a named element blurs nothing behind it (the composer's glass).
  document.documentElement.dataset.transitioning = "";
  const transition = document.startViewTransition(async () => {
    flushSync(go);
    const until = performance.now() + patience;
    while (ready && !ready() && performance.now() < until) await new Promise((r) => setTimeout(r, 16));
    for (const settle of now.settle.splice(0)) settle();
  });
  const now = { settle: [] as (() => void)[], moving: transition.ready.catch(() => {}), done: transition.finished.catch(() => {}) };
  changing = now;
  return transition.finished.catch(() => {}).finally(() => { if (changing === now) changing = null; delete document.documentElement.dataset.transitioning; });
}
