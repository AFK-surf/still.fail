// The shared parts on Radix primitives (focus, keyboard, layering and dismissal come from Radix), drawn with the
// tokens: buttons, tips, fields, choices, switches, selects, dialogs, menus, a small panel's parts, a list's first one,
// a column's edge. Pages compose these instead of styling their own. What they say comes from the words the page gave
// (i18n.ts); the keys a tip names, from the page's shortcuts (shortcuts.ts).
import {
  AlertDialog as RAlert, Dialog as RDialog, DropdownMenu, Label, RadioGroup, Select as RSelect, Switch as RSwitch,
  ToggleGroup, Tooltip,
} from "radix-ui";
import { createPortal } from "react-dom";
import { forwardRef, Fragment, useEffect, useId, useRef, useState, type ButtonHTMLAttributes, type ComponentType, type CSSProperties, type PointerEvent as ReactPointerEvent, type ReactNode } from "react";
import { useBackClose } from "./backClose.ts";
import { Check, ChevronDown, Close, Copy, Info, More } from "./icons.tsx";
import { t } from "./i18n.ts";
import { shortcutKeys, useShortcuts, type Shortcut } from "./shortcuts.ts";
import { failure, useToast } from "./toast.tsx";
import * as controlsCss from "./styles/controls.css.ts";
import * as pageCss from "./styles/page.css.ts";
import { Spinner } from "./waiting.tsx";
import * as partsCss from "./parts.css.ts";

export const ICON = { size: 16, strokeWidth: 1.7 } as const;

type IconType = ComponentType<{ size?: number; strokeWidth?: number }>;
type Variant = "primary" | "secondary" | "ghost" | "danger" | "danger-solid";
const VARIANT: Record<Variant, string> = { primary: controlsCss.btnPrimary, secondary: "", ghost: controlsCss.btnGhost, danger: controlsCss.btnDanger, "danger-solid": controlsCss.btnDangerSolid };

export const Button = forwardRef<HTMLButtonElement, ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant; icon?: IconType; busy?: boolean | undefined }>(
  function Button({ variant = "secondary", icon: Icon, busy, children, className, ...rest }, ref) {
    return (
      <button ref={ref} type="button" {...rest} aria-busy={busy || undefined} disabled={rest.disabled || busy}
        className={`${controlsCss.btn} ${VARIANT[variant]}${className ? ` ${className}` : ""}`}>
        {busy ? <Spinner /> : Icon && <Icon {...ICON} />}
        {children}
      </button>
    );
  },
);

/**
 * An icon-only button; its label shows as a tooltip and names it for screen readers. `busy`: a spinner in its place, not
 * pressed again; `failed`: why what it set going failed a moment ago (useDoingFailed), a red mark in its place and the
 * tip saying so (as DoingMark.tsx does).
 */
export const IconButton = forwardRef<HTMLButtonElement, ButtonHTMLAttributes<HTMLButtonElement> & { label: string; icon: IconType; shortcut?: Shortcut; busy?: boolean | undefined; failed?: string | undefined }>(
  function IconButton({ label, icon: Icon, className, shortcut, busy, failed, ...rest }, ref) {
    return (
      <Tip label={!busy && failed !== undefined ? failed : label} {...(shortcut ? { shortcut } : {})}>
        <button ref={ref} type="button" aria-label={label} {...rest} aria-busy={busy || undefined} disabled={rest.disabled || busy}
          className={`${pageCss.iconBtn}${className ? ` ${className}` : ""}`}>
          {busy ? <Spinner />
            : failed !== undefined ? <span className={partsCss.failedMark} style={{ width: 14, height: 14, fontSize: 10 }} role="img" aria-label={t("web-main.doing.failedWhy", { error: failed })}>!</span>
            : <Icon {...ICON} />}
        </button>
      </Tip>
    );
  },
);

function TipKeys({ action }: { action: Shortcut }) {
  useShortcuts();
  const keys = shortcutKeys(action);
  return keys ? <span className={partsCss.tipKeys}>{keys}</span> : null;
}

/** A binding as shown (⌘⇧H, Ctrl+Shift+H) split into its keys: each mark of a Mac's modifiers one, the rest by its +s. */
export function capsOf(label: string): string[] {
  return label.match(/[⌃⌥⇧⌘]|[^⌃⌥⇧⌘+]+/g) ?? [];
}

/** Keys that do something, each as a cap. */
export function Keys({ caps, className }: { caps: string[]; className?: string }) {
  return <span className={className ? `${partsCss.keys} ${className}` : partsCss.keys}>{caps.map((k, i) => <kbd key={i} className={partsCss.cap}>{k}</kbd>)}</span>;
}

/**
 * A tip over a control; with a `shortcut`, the keys that do the same follow what it says. The only way anything here
 * explains itself on hover: no native `title`. With no label it never opens, but keeps its place in the tree.
 */
export function Tip({ label, children, side = "bottom", shortcut, cut }: { label: ReactNode; children: ReactNode; side?: "top" | "bottom" | "left" | "right"; shortcut?: Shortcut; /** Only says what the trigger already shows, so opens only while that is cut short. */ cut?: boolean }) {
  const trigger = useRef<HTMLButtonElement>(null);
  const [open, setOpen] = useState(false);
  const root = label == null || label === "" ? { open: false }
    : cut ? { open, onOpenChange: (o: boolean) => setOpen(o && trigger.current !== null && isCut(trigger.current)) } : {};
  return (
    <Tooltip.Root {...root}>
      {/* Focus the browser does not show (a click, or a popover focusing its first item or handing focus back) opens none. */}
      <Tooltip.Trigger ref={trigger} asChild onFocus={(e) => { if (!e.currentTarget.matches(":focus-visible")) e.preventDefault(); }}>{children}</Tooltip.Trigger>
      <Tooltip.Portal>
        <Tooltip.Content className={partsCss.tooltip} side={side} sideOffset={6} collisionPadding={8}>{label}{shortcut && <TipKeys action={shortcut} />}</Tooltip.Content>
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
    <Tip label={<span className={partsCss.aboutText}>{children}</span>} side={side}>
      <button type="button" className={partsCss.about} aria-label={t("web-main.about")}><Info size={14} strokeWidth={1.8} /></button>
    </Tip>
  );
}

export function Field({ label, hint, error, children, htmlFor, aside }:
  { label: ReactNode; hint?: ReactNode; error?: ReactNode; children: ReactNode; htmlFor?: string; aside?: ReactNode }) {
  return (
    <div className={partsCss.field} data-invalid={Boolean(error) || undefined}>
      <div className={partsCss.fieldTop}>
        <Label.Root className={partsCss.fieldLabel} htmlFor={htmlFor}>{label}</Label.Root>
        {aside}
      </div>
      {children}
      {error ? <div className={controlsCss.fieldError} role="alert">{error}</div> : hint ? <div className={partsCss.fieldHint}>{hint}</div> : null}
    </div>
  );
}

/** A small set of exclusive options shown side by side. */
export function Segmented<T extends string>({ options, value, onChange, label, className }:
  { options: { value: T; label: ReactNode; disabled?: boolean | undefined }[]; value: T; onChange(value: T): void; label: string; className?: string }) {
  const index = Math.max(0, options.findIndex((o) => o.value === value));
  return (
    <ToggleGroup.Root type="single" className={className ? `${partsCss.segmented} ${className}` : partsCss.segmented} aria-label={label} value={value}
      style={{ "--n": options.length, "--i": index } as CSSProperties}
      onValueChange={(v) => { if (v) onChange(v as T); }}>
      {/* The chosen option's ground is one piece that slides between options. */}
      <span className={partsCss.segmentedThumb} aria-hidden="true" />
      {options.map((o) => (
        <ToggleGroup.Item key={o.value} value={o.value} disabled={o.disabled ?? false} className={partsCss.segmentedOption}>
          <span className={partsCss.segmentedLabel}>{o.label}</span><span className={partsCss.segmentedSizer} aria-hidden="true">{o.label}</span>
        </ToggleGroup.Item>
      ))}
    </ToggleGroup.Root>
  );
}

/** Exclusive options that need a sentence each: bordered cards with a radio mark. */
export function Choices<T extends string>({ options, value, onChange, label }:
  { options: { value: T; title: ReactNode; description?: ReactNode; icon?: ReactNode; disabled?: boolean | undefined; extra?: ReactNode }[]; value: T; onChange(value: T): void; label: string }) {
  return (
    <RadioGroup.Root className={partsCss.choices} aria-label={label} value={value} onValueChange={(v) => onChange(v as T)}>
      {options.map((o) => (
        <div key={o.value} className={partsCss.choice} data-checked={o.value === value || undefined} data-disabled={o.disabled || undefined}>
          <RadioGroup.Item value={o.value} disabled={o.disabled ?? false} className={partsCss.choiceHit} aria-label={typeof o.title === "string" ? o.title : undefined}>
            {o.icon}
            <span className={partsCss.choiceText}>
              <strong>{o.title}</strong>
              {o.description && <span className={partsCss.note}>{o.description}</span>}
            </span>
            <span className={partsCss.radio} aria-hidden="true"><RadioGroup.Indicator className={partsCss.radioDot} /></span>
          </RadioGroup.Item>
          {o.extra && o.value === value && <div className={partsCss.choiceExtra}>{o.extra}</div>}
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
      {busy && <Spinner inline={small} label={t("common.saving")} />}
      <RSwitch.Root id={id} className={small ? `${partsCss.switch_} ${partsCss.switchSmall}` : partsCss.switch_} checked={checked} onCheckedChange={onChange} disabled={(disabled || busy) ?? false} aria-busy={busy || undefined} aria-label={label}>
        <RSwitch.Thumb className={small ? `${partsCss.switchThumb} ${partsCss.switchThumbSmall}` : partsCss.switchThumb} />
      </RSwitch.Root>
    </>
  );
}

/** A setting row: what it is on the left, its switch on the right. */
export function SwitchRow({ title, description, checked, onChange, disabled, busy }:
  { title: ReactNode; description?: ReactNode; checked: boolean; onChange(checked: boolean): void; disabled?: boolean | undefined; busy?: boolean | undefined }) {
  const id = useId();
  return (
    <div className={partsCss.switchRow}>
      <Label.Root htmlFor={id} className={partsCss.switchRowText}>
        <span>{title}</span>
        {description && <span className={partsCss.note}>{description}</span>}
      </Label.Root>
      <Switch id={id} checked={checked} onChange={onChange} disabled={disabled ?? false} busy={busy} />
    </div>
  );
}

const NONE = "__none__";

/** A dropdown of choices. An option with value "" is allowed and stands for "not set". */
export function Select({ value, onChange, options, id, placeholder, disabled, label }: {
  value: string; onChange(value: string): void; id?: string; placeholder?: string; disabled?: boolean | undefined; label?: string;
  /** `group`: a heading over the run of options that share it. */
  options: { value: string; label: ReactNode; hint?: ReactNode; group?: string }[];
}) {
  // Radix reserves "" for "no selection", so an empty option travels under a stand-in value.
  const encode = (v: string) => (v === "" ? NONE : v);
  const runs = options.reduce<{ group: string | undefined; items: typeof options }[]>((acc, o) => {
    const last = acc[acc.length - 1];
    if (last && last.group === o.group) last.items.push(o); else acc.push({ group: o.group, items: [o] });
    return acc;
  }, []);
  return (
    <RSelect.Root value={encode(value)} onValueChange={(v) => onChange(v === NONE ? "" : v)} disabled={disabled ?? false}>
      <RSelect.Trigger id={id} className={partsCss.select} aria-label={label}>
        <RSelect.Value placeholder={placeholder} />
        <RSelect.Icon className={partsCss.selectIcon}><ChevronDown {...ICON} size={14} /></RSelect.Icon>
      </RSelect.Trigger>
      <RSelect.Portal>
        <RSelect.Content className={`${controlsCss.popover} ${partsCss.selectContent}`} position="popper" sideOffset={4} collisionPadding={8}>
          <RSelect.Viewport className={partsCss.selectViewport}>
            {runs.map((run, i) => {
              const items = run.items.map((o) => (
                <RSelect.Item key={o.value} value={encode(o.value)} className={`${controlsCss.menuItem} ${partsCss.selectItem}`}>
                  <RSelect.ItemText>{o.label}</RSelect.ItemText>
                  {o.hint && <span className={partsCss.selectHint}>{o.hint}</span>}
                  <RSelect.ItemIndicator className={partsCss.selectCheck}><Check {...ICON} size={14} /></RSelect.ItemIndicator>
                </RSelect.Item>
              ));
              return run.group ? <RSelect.Group key={i}><RSelect.Label className={controlsCss.menuLabel}>{run.group}</RSelect.Label>{items}</RSelect.Group> : <Fragment key={i}>{items}</Fragment>;
            })}
          </RSelect.Viewport>
        </RSelect.Content>
      </RSelect.Portal>
    </RSelect.Root>
  );
}

export type Tone = "neutral" | "green" | "blue" | "amber" | "red" | "accent";

export function Pill({ tone = "neutral", children }: { tone?: Tone; children: ReactNode }) {
  return <span className={partsCss.pill} data-tone={tone}>{children}</span>;
}

export type Presence = "online" | "offline" | "busy" | "error";

export function StatusDot({ state, label }: { state: Presence; label?: string }) {
  return <span className={partsCss.statusDot} data-state={state} role={label ? "img" : undefined} aria-label={label} />;
}

// A lettered tile (Avatar.tsx).
export { Avatar } from "./Avatar.tsx";

export function Dialog({ open, title, description, onClose, children, footer, wide }:
  { open: boolean; title: ReactNode; description?: ReactNode; onClose(): void; children: ReactNode; footer?: ReactNode; wide?: boolean }) {
  useBackClose(open, onClose);
  return (
    <RDialog.Root open={open} onOpenChange={(next) => { if (!next) onClose(); }}>
      <RDialog.Portal>
        <RDialog.Overlay className={partsCss.overlay} />
        {/* Focus the dialog itself rather than its first button, so the close button's tooltip does not pop up on open. */}
        <RDialog.Content className={`${partsCss.dialog}${wide ? ` ${partsCss.dialogWide}` : ""}`} tabIndex={-1}
          onOpenAutoFocus={(e) => { e.preventDefault(); (e.currentTarget as HTMLElement).focus(); }}>
          <div className={partsCss.dialogHead}>
            <RDialog.Title className={partsCss.dialogTitle}>{title}</RDialog.Title>
            <RDialog.Close asChild><IconButton label={t("common.close")} icon={Close} /></RDialog.Close>
          </div>
          {description ? <RDialog.Description className={partsCss.dialogLead}>{description}</RDialog.Description> : <RDialog.Description className={partsCss.srOnly}>{title}</RDialog.Description>}
          <div className={partsCss.dialogBody}>{children}</div>
          {footer && <div className={partsCss.dialogFoot}>{footer}</div>}
        </RDialog.Content>
      </RDialog.Portal>
    </RDialog.Root>
  );
}

/** Asks before something that cannot be undone. `action` names what happens, e.g. "删除连接". */
/** Asks before something that cannot be undone. `error`: why it did not work, said where it was asked (it stays open). */
/** `tone` "primary": what is asked is no harm (the demo's 打开 still.fail), its action solid but not red; `cancel`: what
 * turning it down is called, where 取消 says it wrongly (知道了). No `description`: the title says it all. */
export function Confirm({ open, title, description, action, onConfirm, onClose, busy, error, tone = "danger", cancel }:
  { open: boolean; title: ReactNode; description?: ReactNode; action: string; onConfirm(): void; onClose(): void; busy?: boolean | undefined; error?: string | null | undefined; tone?: "danger" | "primary"; cancel?: string }) {
  useBackClose(open, onClose);
  return (
    <RAlert.Root open={open} onOpenChange={(next) => { if (!next) onClose(); }}>
      <RAlert.Portal>
        <RAlert.Overlay className={partsCss.overlay} />
        <RAlert.Content className={`${partsCss.dialog} ${partsCss.dialogAlert}`}>
          <RAlert.Title className={partsCss.dialogTitle}>{title}</RAlert.Title>
          {description ? <RAlert.Description className={partsCss.dialogLead}>{description}</RAlert.Description> : <RAlert.Description className={partsCss.srOnly}>{title}</RAlert.Description>}
          {error && <p className={partsCss.dialogError} role="alert">{error}</p>}
          <div className={partsCss.dialogFoot}>
            <RAlert.Cancel asChild><Button variant="ghost">{cancel ?? t("common.cancel")}</Button></RAlert.Cancel>
            <Button variant={tone === "danger" ? "danger-solid" : "primary"} busy={busy ?? false} onClick={onConfirm}>{action}</Button>
          </div>
        </RAlert.Content>
      </RAlert.Portal>
    </RAlert.Root>
  );
}

/** A menu's item. `checked`: one of a choice's (a member's role), the one now chosen with a check at its end. */
/** `note`: what it means, quieter after its words (a choice's: 默认最长授权's each). */
export interface MenuItem { label: string; note?: string; icon?: IconType; danger?: boolean; disabled?: boolean | undefined; checked?: boolean; onSelect(): void }

/**
 * A small panel's parts (docs/ui-panels.md), for what is put in styles/controls.css.ts `popover`: its head (a title, a
 * line under it), groups under a small label, rows (an icon, the words, something at the end), blocks of words
 * (PanelText), a foot of buttons, and its buttons (PanelButton, a small pill; PanelIconButton, a small circle). The
 * panel is padded 6; rows sit there, their words in by a row's padding, as a block of words' are; corners are the
 * panel's inner one (`--panel-in`), so a panel made of them is right whoever makes it.
 */
export function PanelHead({ title, note }: { title: ReactNode; note?: ReactNode }) {
  return <div className={partsCss.panelHead}><div className={partsCss.panelTitle}>{title}</div>{note && <p className={partsCss.panelNote}>{note}</p>}</div>;
}
export function PanelGroup({ label, children }: { label?: ReactNode; children: ReactNode }) {
  return <div className={partsCss.panelGroup}>{label && <div className={partsCss.panelLabel}>{label}</div>}{children}</div>;
}
/** A row to press; without `onClick` one only to read (as for a read-only member), the same but for the pointer. */
export function PanelRow({ icon, label, end, onClick }: { icon?: ReactNode; label: ReactNode; end?: ReactNode; onClick?: (() => void) | undefined }) {
  const body = (
    <>
      {icon && <span className={partsCss.panelRowIcon}>{icon}</span>}
      <span className={partsCss.panelRowLabel}>{label}</span>
      {end && <span className={partsCss.panelRowEnd}>{end}</span>}
    </>
  );
  return onClick ? <button type="button" className={partsCss.panelRow} onClick={onClick}>{body}</button> : <div className={partsCss.panelRow}>{body}</div>;
}
export function PanelNote({ children }: { children: ReactNode }) {
  return <p className={partsCss.panelNote}>{children}</p>;
}
export function PanelFoot({ children }: { children: ReactNode }) {
  return <div className={partsCss.panelFoot}>{children}</div>;
}
/** A block of words in a small panel: in by a row's padding, on the line its rows' words are. */
export function PanelText({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={className ? `${partsCss.panelText} ${className}` : partsCss.panelText}>{children}</div>;
}
/** Words to press in a small panel: a small pill. `tone`: accent (the one thing to do), quiet, filled (always seen). */
export const PanelButton = forwardRef<HTMLButtonElement, ButtonHTMLAttributes<HTMLButtonElement> & { tone?: "accent" | "quiet" | "filled" }>(
  function PanelButton({ tone, className, type = "button", ...rest }, ref) {
    return <button ref={ref} type={type} className={className ? `${partsCss.panelButton} ${className}` : partsCss.panelButton} data-tone={tone} {...rest} />;
  },
);
/** An icon to press in a small panel (close, stop, step): a small circle, named on hover. */
export function PanelIconButton({ label, children, className, ...rest }: ButtonHTMLAttributes<HTMLButtonElement> & { label: string; children: ReactNode }) {
  return <Tip label={label}><button type="button" aria-label={label} className={className ? `${partsCss.panelIcon} ${className}` : partsCss.panelIcon} {...rest}>{children}</button></Tip>;
}

/** "…" menu: a list of actions on the thing it sits beside. `trigger`: what opens it in place of "…" (words in a line of words). */
export function Menu({ label = t("web-main.menu.more"), items, trigger }: { label?: string; items: (MenuItem | "separator")[]; trigger?: ReactNode }) {
  return (
    <DropdownMenu.Root modal={false}>
      <DropdownMenu.Trigger asChild>{trigger ?? <IconButton label={label} icon={More} />}</DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content className={`${controlsCss.popover} ${controlsCss.menuList}`} align="end" sideOffset={4} collisionPadding={8}>
          {items.map((item, i) => item === "separator" ? <DropdownMenu.Separator key={i} className={controlsCss.menuSep} /> : (
            <DropdownMenu.Item key={item.label} className={controlsCss.menuItem} data-danger={item.danger || undefined}
              disabled={item.disabled ?? false} onSelect={item.onSelect}>
              {item.icon && <item.icon {...ICON} />}
              {item.label}
              {item.note && <span className={controlsCss.menuNote}>{item.note}</span>}
              {item.checked !== undefined && <span className={controlsCss.menuCheck}>{item.checked && <Check {...ICON} size={14} />}</span>}
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
    <div className={partsCss.command}>
      <code>{text}</code>
      <IconButton label={copied ? t("common.copied") : t("common.copy")} icon={copied ? Check : Copy}
        onClick={() => void navigator.clipboard.writeText(text).then(() => { setCopied(true); setTimeout(() => setCopied(false), 1600); }, (e: unknown) => toast(t("web-main.copyFailed", { error: failure(e) })))} />
    </div>
  );
}

/**
 * A choice that opens a menu of what it can be (a model, an account): not the browser's own select, so each option can
 * show what matters about it. `trigger` draws the chosen one; the class is the look of the button.
 */
export function Chooser({ label, children, side = "bottom", className = controlsCss.chooser }: { label: ReactNode; children: ReactNode; side?: "top" | "bottom"; className?: string }) {
  return (
    <DropdownMenu.Root modal={false}>
      <DropdownMenu.Trigger className={className}>{label}<ChevronDown size={12} className={controlsCss.chooserChevron} /></DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content className={`${controlsCss.popover} ${controlsCss.menuList} ${controlsCss.chooserMenu}`} side={side} align="start" sideOffset={6} collisionPadding={8}>{children}</DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}

/** `stays`: the menu stays open as it is chosen (one of several ticked in turn). `checkEnd`: its check at the row's end. */
export function ChooserItem({ checked, onSelect, stays = false, checkEnd = false, children }: { checked: boolean; onSelect(): void; stays?: boolean; checkEnd?: boolean; children: ReactNode }) {
  const check = <span className={checkEnd ? `${controlsCss.chooserCheck} ${controlsCss.chooserCheckEnd}` : controlsCss.chooserCheck}>{checked && <Check size={14} />}</span>;
  return (
    <DropdownMenu.Item className={`${controlsCss.menuItem} ${controlsCss.chooserItem}`} onSelect={(e) => { if (stays) e.preventDefault(); onSelect(); }}>
      {!checkEnd && check}{children}{checkEnd && check}
    </DropdownMenu.Item>
  );
}

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

export function Empty({ children }: { children: ReactNode }) {
  return <div className={partsCss.empty}>{children}</div>;
}

/**
 * A list with nothing in it yet, or a page whose first step is still to take: what that first one is, in a line, and
 * the one thing to do about it. Where it shows, the page's other actions stand back (its add button, its filters), so
 * the eye goes here.
 */
export function FirstOne({ art, title, lead, children }: { art: ReactNode; title: ReactNode; lead?: ReactNode; children: ReactNode }) {
  return (
    <div className={partsCss.firstOne}>
      {/* One of the project's scenes (brand.tsx's Illustration), not an icon on a tinted tile. */}
      {art}
      <h2 className={partsCss.firstOneTitle}>{title}</h2>
      {lead && <p className={partsCss.firstOneLead}>{lead}</p>}
      <div className={partsCss.firstOneAction}>{children}</div>
    </div>
  );
}

/** A titled block of a detail page. */
export function Section({ title, actions, children, description }: { title: ReactNode; actions?: ReactNode; description?: ReactNode; children: ReactNode }) {
  const id = useId();
  return (
    <section className={pageCss.section} aria-labelledby={id}>
      <div className={partsCss.sectionHead}>
        <div>
          <h2 id={id}>{title}</h2>
          {description && <p className={partsCss.sectionSub}>{description}</p>}
        </div>
        {actions && <div className={partsCss.sectionActions}>{actions}</div>}
      </div>
      {children}
    </section>
  );
}

/**
 * A strip on a column's edge that drags its width. The width lives in a CSS
 * variable on the document (so every layout using it follows) and in
 * localStorage; a double click goes back to the default.
 */
/**
 * The width dragged for a column (`variable`, ResizeHandle), as it is kept: put on the root if it is not there yet (a
 * page just loaded), and answered in pixels; null with none kept. What lays the column out by its own reckoning asks
 * here first, so the styles and it go by the same width from the column's first frame.
 */
export function keptWidth(variable: string, min: number, max: number, key = variable): number | null {
  const saved = Number(localStorage.getItem(`stillfail.width.${key}`));
  if (!saved) return null;
  const px = Math.min(max, Math.max(min, saved));
  // Only when it differs: set, even the same, the page's every element is styled anew (the variable is on the root
  // and inherited).
  if (document.documentElement.style.getPropertyValue(variable) !== `${px}px`) document.documentElement.style.setProperty(variable, `${px}px`);
  return px;
}

/**
 * A column's edge, as the sidebar's (Rail.tsx SidebarEdge, Cue's rail handle): a short bar at its middle, shown as the
 * pointer is over the column and longer on the edge, and a hairline fading toward both ends on hover or while dragged
 * (that edge alone, not every edge of the page), with a tip that follows the pointer along it. Dragged, the column takes
 * the width; pressed without moving, `press` (a panel closing); else double-clicked, its own width again.
 */
/** Sets a column's width (null: its own again) and keeps it on this device (under `key`, one column's of several
 * drawn by the same variable), as keptWidth reads it. */
export function setKeptWidth(variable: string, px: number | null, key = variable): void {
  const storage = `stillfail.width.${key}`;
  if (px === null) {
    document.documentElement.style.removeProperty(variable);
    localStorage.removeItem(storage);
  } else {
    document.documentElement.style.setProperty(variable, `${px}px`);
    localStorage.setItem(storage, String(px));
  }
}

export function ResizeHandle({ variable, edge, min, max, label, press }: {
  variable: string; edge: "left" | "right"; min: number; max: number; label: string;
  /** What a press without moving does (a panel closing), said after the label. */
  press?: { label: string; run(): void };
}) {
  const set = (px: number | null) => setKeptWidth(variable, px);
  // Each time its column comes (a chat's side panel opening).
  useEffect(() => { keptWidth(variable, min, max); }, [variable, min, max]);
  const tip = usePointerTip();
  const [dragging, setDragging] = useState(false);
  const words = press ? `${label} · ${press.label}` : label;
  return (
    <>
      <div className={partsCss.resizeHandle} data-edge={edge} data-active={dragging || undefined} role="separator" aria-orientation="vertical" aria-label={words}
        {...tip.on}
        onDoubleClick={() => { if (!press) set(null); }}
        onPointerDown={(e) => {
          if (e.button !== 0) return;
          tip.hide();
          const column = e.currentTarget.parentElement!.getBoundingClientRect();
          const handle = e.currentTarget;
          const from = e.clientX;
          let moved = false;
          handle.setPointerCapture(e.pointerId);
          const move = (ev: PointerEvent) => {
            if (!moved && Math.abs(ev.clientX - from) < 3) return;
            if (!moved) { moved = true; setDragging(true); document.body.dataset.resizing = "true"; }
            const width = edge === "right" ? ev.clientX - column.left : column.right - ev.clientX;
            set(Math.round(Math.min(max, Math.max(min, width))));
          };
          const up = () => {
            handle.removeEventListener("pointermove", move);
            handle.removeEventListener("pointerup", up);
            delete document.body.dataset.resizing;
            setDragging(false);
            if (!moved) press?.run();
          };
          handle.addEventListener("pointermove", move);
          handle.addEventListener("pointerup", up);
          e.preventDefault();
        }} />
      {!dragging && tip.draw(words, edge === "right" ? "right" : "left")}
    </>
  );
}

/**
 * A tip that follows the pointer along a tall thin thing (an edge): shown a moment after the pointer comes, beside it,
 * its middle level with the pointer; `on` goes on the thing, `draw` where the tip is drawn.
 */
export function usePointerTip(): { on: { onPointerEnter(e: ReactPointerEvent): void; onPointerMove(e: ReactPointerEvent): void; onPointerLeave(): void }; hide(): void; draw(words: ReactNode, side: "left" | "right"): ReactNode } {
  const [at, setAt] = useState<{ x: number; y: number } | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined);
  useEffect(() => () => clearTimeout(timer.current), []);
  const hide = () => { clearTimeout(timer.current); setAt(null); };
  return {
    on: {
      onPointerEnter: (e) => {
        if (e.pointerType !== "mouse" || e.buttons !== 0) return;
        const where = { x: e.clientX, y: e.clientY };
        clearTimeout(timer.current);
        timer.current = setTimeout(() => setAt(where), 300);
      },
      onPointerMove: (e) => { if (at) setAt({ x: e.clientX, y: e.clientY }); },
      onPointerLeave: hide,
    },
    hide,
    draw: (words, side) => at && onPage(
      <div className={partsCss.edgeTip} style={{ transform: `translate3d(${side === "right" ? at.x + 14 : at.x - 14}px, ${at.y}px, 0)` }} data-edge={side} aria-hidden="true">
        <div className={partsCss.tooltip}>{words}</div>
      </div>,
    ),
  };
}

/** Put on the page itself (a column cuts what is in it). */
function onPage(node: ReactNode): ReactNode {
  return typeof document === "undefined" ? null : createPortal(node, document.body);
}
