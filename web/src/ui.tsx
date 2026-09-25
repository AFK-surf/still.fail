// Shared controls. Pages compose these instead of styling their own buttons,
// fields or menus, the way Zork's pages compose zork-ui.
import { Check, ChevronLeft, Copy, MoreHorizontal, X } from "lucide-react";
import { Link } from "react-router";
import {
  useEffect, useId, useRef, useState, type ButtonHTMLAttributes, type ComponentType, type ReactNode,
} from "react";

export const ICON = { size: 16, strokeWidth: 1.7 } as const;

type Variant = "primary" | "secondary" | "ghost" | "danger";

export function Button({ variant = "secondary", icon: Icon, busy, children, className, ...rest }:
  ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant; icon?: ComponentType<{ size?: number; strokeWidth?: number }>; busy?: boolean }) {
  return (
    <button type="button" {...rest} aria-busy={busy || undefined} disabled={rest.disabled || busy}
      className={`btn btn-${variant}${className ? ` ${className}` : ""}`}>
      {Icon && <Icon {...ICON} />}
      {children}
    </button>
  );
}

export function IconButton({ label, icon: Icon, className, ...rest }:
  ButtonHTMLAttributes<HTMLButtonElement> & { label: string; icon: ComponentType<{ size?: number; strokeWidth?: number }> }) {
  return (
    <button type="button" aria-label={label} title={label} {...rest} className={`icon-btn${className ? ` ${className}` : ""}`}>
      <Icon {...ICON} />
    </button>
  );
}

export function Field({ label, hint, error, children, htmlFor }: { label: ReactNode; hint?: ReactNode; error?: ReactNode; children: ReactNode; htmlFor?: string }) {
  return (
    <div className="field" data-invalid={Boolean(error) || undefined}>
      <label className="field-label" htmlFor={htmlFor}>{label}</label>
      {children}
      {error ? <div className="field-error" role="alert">{error}</div> : hint ? <div className="field-hint">{hint}</div> : null}
    </div>
  );
}

export function Segmented<T extends string>({ options, value, onChange, label }:
  { options: { value: T; label: ReactNode; disabled?: boolean }[]; value: T; onChange(value: T): void; label: string }) {
  return (
    <div className="segmented" role="radiogroup" aria-label={label}>
      {options.map((o) => (
        <button key={o.value} type="button" role="radio" aria-checked={o.value === value} disabled={o.disabled}
          className="segmented-option" onClick={() => onChange(o.value)}>{o.label}</button>
      ))}
    </div>
  );
}

export function Switch({ checked, onChange, label, disabled }: { checked: boolean; onChange(checked: boolean): void; label: string; disabled?: boolean }) {
  return (
    <button type="button" role="switch" aria-checked={checked} aria-label={label} disabled={disabled}
      className="switch" onClick={() => onChange(!checked)}><span className="switch-thumb" /></button>
  );
}

export type Tone = "neutral" | "green" | "blue" | "amber" | "red" | "accent";

export function Pill({ tone = "neutral", children }: { tone?: Tone; children: ReactNode }) {
  return <span className="pill" data-tone={tone}>{children}</span>;
}

export type Presence = "online" | "offline" | "busy" | "error";

export function StatusDot({ state, label }: { state: Presence; label?: string }) {
  return <span className="status-dot" data-state={state} role={label ? "img" : undefined} aria-label={label} />;
}

const AVATAR_TONES = ["#c9954c", "#6f8fbf", "#7d9a6f", "#b07a9c", "#8c83c7", "#c77d6a"];

/** A lettered tile, coloured by id, like Zork's device avatars. */
export function Avatar({ id, name, size = 20 }: { id: string; name: string; size?: number }) {
  let hash = 0;
  for (const c of id) hash = (hash * 31 + c.charCodeAt(0)) >>> 0;
  // "ember-gpt" → G: the distinguishing last word, since bots often share a prefix.
  const word = name.trim().split(/[\s\-_./]+/).filter(Boolean).at(-1) ?? name;
  const letter = ([...word][0] ?? "?").toUpperCase();
  return (
    <span className="avatar" aria-hidden="true"
      style={{ width: size, height: size, fontSize: Math.round(size * .52), background: AVATAR_TONES[hash % AVATAR_TONES.length], borderRadius: Math.min(size * .375, 12) }}>
      {letter}
    </span>
  );
}

export function Dialog({ open, title, onClose, children, footer, wide }:
  { open: boolean; title: ReactNode; onClose(): void; children: ReactNode; footer?: ReactNode; wide?: boolean }) {
  const ref = useRef<HTMLDialogElement>(null);
  const titleId = useId();
  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    if (open && !dialog.open) dialog.showModal();
    if (!open && dialog.open) dialog.close();
  }, [open]);
  return (
    <dialog ref={ref} className={`dialog${wide ? " dialog-wide" : ""}`} aria-labelledby={titleId}
      onCancel={(e) => { e.preventDefault(); onClose(); }}
      onClick={(e) => { if (e.target === ref.current) onClose(); }}>
      {open && (
        <div className="dialog-body">
          <div className="dialog-head">
            <h2 id={titleId}>{title}</h2>
            <IconButton label="关闭" icon={X} onClick={onClose} />
          </div>
          {children}
          {footer && <div className="dialog-foot">{footer}</div>}
        </div>
      )}
    </dialog>
  );
}

/** "…" menu anchored to its trigger; closes on choice, outside click or Esc. */
export function Menu({ label = "更多操作", items }: { label?: string; items: { label: string; danger?: boolean; disabled?: boolean; onSelect(): void }[] }) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    const close = (e: MouseEvent | KeyboardEvent) => {
      if (e instanceof KeyboardEvent ? e.key === "Escape" : !ref.current?.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", close);
    document.addEventListener("keydown", close);
    return () => {
      document.removeEventListener("mousedown", close);
      document.removeEventListener("keydown", close);
    };
  }, [open]);
  return (
    <div className="menu" ref={ref}>
      <IconButton label={label} icon={MoreHorizontal} aria-expanded={open} aria-haspopup="menu" onClick={() => setOpen(!open)} />
      {open && (
        <div className="menu-list" role="menu">
          {items.map((item) => (
            <button key={item.label} type="button" role="menuitem" className="menu-item" data-danger={item.danger || undefined}
              disabled={item.disabled} onClick={() => { setOpen(false); item.onSelect(); }}>{item.label}</button>
          ))}
        </div>
      )}
    </div>
  );
}

export function CopyCommand({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <div className="command">
      <code>{text}</code>
      <IconButton label={copied ? "已复制" : "复制"} icon={copied ? Check : Copy}
        onClick={() => void navigator.clipboard.writeText(text).then(() => { setCopied(true); setTimeout(() => setCopied(false), 1600); })} />
    </div>
  );
}

/** A back link that only phones show, where an opened page hides the sidebar. */
export function MobileBack({ to, label }: { to: string; label: string }) {
  return <Link className="mobile-back" to={to}><ChevronLeft {...ICON} />{label}</Link>;
}

export function Empty({ children }: { children: ReactNode }) {
  return <div className="empty">{children}</div>;
}
