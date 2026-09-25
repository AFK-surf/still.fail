// Shared controls on Radix primitives (focus, keyboard, layering and
// dismissal come from Radix), styled with ember's tokens. Pages compose these
// instead of styling their own buttons, fields or menus.
import { Check, ChevronDown, ChevronLeft, Copy, MessageCircle, MoreHorizontal, Slack, X } from "lucide-react";
import {
  AlertDialog as RAlert, Dialog as RDialog, DropdownMenu, Label, RadioGroup, Select as RSelect, Switch as RSwitch,
  ToggleGroup, Tooltip,
} from "radix-ui";
import { Link } from "react-router";
import { forwardRef, useId, useState, type ButtonHTMLAttributes, type ComponentType, type ReactNode } from "react";

export const ICON = { size: 16, strokeWidth: 1.7 } as const;

type IconType = ComponentType<{ size?: number; strokeWidth?: number }>;
type Variant = "primary" | "secondary" | "ghost" | "danger" | "danger-solid";

export const Button = forwardRef<HTMLButtonElement, ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant; icon?: IconType; busy?: boolean | undefined }>(
  function Button({ variant = "secondary", icon: Icon, busy, children, className, ...rest }, ref) {
    return (
      <button ref={ref} type="button" {...rest} aria-busy={busy || undefined} disabled={rest.disabled || busy}
        className={`btn btn-${variant}${className ? ` ${className}` : ""}`}>
        {Icon && <Icon {...ICON} />}
        {children}
      </button>
    );
  },
);

/** An icon-only button; its label shows as a tooltip and names it for screen readers. */
export const IconButton = forwardRef<HTMLButtonElement, ButtonHTMLAttributes<HTMLButtonElement> & { label: string; icon: IconType }>(
  function IconButton({ label, icon: Icon, className, ...rest }, ref) {
    return (
      <Tip label={label}>
        <button ref={ref} type="button" aria-label={label} {...rest} className={`icon-btn${className ? ` ${className}` : ""}`}>
          <Icon {...ICON} />
        </button>
      </Tip>
    );
  },
);

export function Tip({ label, children, side = "bottom" }: { label: ReactNode; children: ReactNode; side?: "top" | "bottom" | "left" | "right" }) {
  return (
    <Tooltip.Root>
      <Tooltip.Trigger asChild>{children}</Tooltip.Trigger>
      <Tooltip.Portal>
        <Tooltip.Content className="tooltip" side={side} sideOffset={6} collisionPadding={8}>{label}</Tooltip.Content>
      </Tooltip.Portal>
    </Tooltip.Root>
  );
}

export function Field({ label, hint, error, children, htmlFor, aside }:
  { label: ReactNode; hint?: ReactNode; error?: ReactNode; children: ReactNode; htmlFor?: string; aside?: ReactNode }) {
  return (
    <div className="field" data-invalid={Boolean(error) || undefined}>
      <div className="field-top">
        <Label.Root className="field-label" htmlFor={htmlFor}>{label}</Label.Root>
        {aside}
      </div>
      {children}
      {error ? <div className="field-error" role="alert">{error}</div> : hint ? <div className="field-hint">{hint}</div> : null}
    </div>
  );
}

/** A small set of exclusive options shown side by side. */
export function Segmented<T extends string>({ options, value, onChange, label }:
  { options: { value: T; label: ReactNode; disabled?: boolean | undefined }[]; value: T; onChange(value: T): void; label: string }) {
  return (
    <ToggleGroup.Root type="single" className="segmented" aria-label={label} value={value}
      onValueChange={(v) => { if (v) onChange(v as T); }}>
      {options.map((o) => (
        <ToggleGroup.Item key={o.value} value={o.value} disabled={o.disabled ?? false} className="segmented-option">{o.label}</ToggleGroup.Item>
      ))}
    </ToggleGroup.Root>
  );
}

/** Exclusive options that need a sentence each: bordered cards with a radio mark. */
export function Choices<T extends string>({ options, value, onChange, label }:
  { options: { value: T; title: ReactNode; description?: ReactNode; icon?: ReactNode; disabled?: boolean | undefined; extra?: ReactNode }[]; value: T; onChange(value: T): void; label: string }) {
  return (
    <RadioGroup.Root className="choices" aria-label={label} value={value} onValueChange={(v) => onChange(v as T)}>
      {options.map((o) => (
        <div key={o.value} className="choice" data-checked={o.value === value || undefined} data-disabled={o.disabled || undefined}>
          <RadioGroup.Item value={o.value} disabled={o.disabled ?? false} className="choice-hit" aria-label={typeof o.title === "string" ? o.title : undefined}>
            {o.icon}
            <span className="choice-text">
              <strong>{o.title}</strong>
              {o.description && <span className="muted">{o.description}</span>}
            </span>
            <span className="radio" aria-hidden="true"><RadioGroup.Indicator className="radio-dot" /></span>
          </RadioGroup.Item>
          {o.extra && o.value === value && <div className="choice-extra">{o.extra}</div>}
        </div>
      ))}
    </RadioGroup.Root>
  );
}

export function Switch({ checked, onChange, label, disabled, id }: { checked: boolean; onChange(checked: boolean): void; label?: string; disabled?: boolean | undefined; id?: string }) {
  return (
    <RSwitch.Root id={id} className="switch" checked={checked} onCheckedChange={onChange} disabled={disabled ?? false} aria-label={label}>
      <RSwitch.Thumb className="switch-thumb" />
    </RSwitch.Root>
  );
}

/** A setting row: what it is on the left, its switch on the right. */
export function SwitchRow({ title, description, checked, onChange, disabled }:
  { title: ReactNode; description?: ReactNode; checked: boolean; onChange(checked: boolean): void; disabled?: boolean | undefined }) {
  const id = useId();
  return (
    <div className="switch-row">
      <Label.Root htmlFor={id} className="switch-row-text">
        <span>{title}</span>
        {description && <span className="muted">{description}</span>}
      </Label.Root>
      <Switch id={id} checked={checked} onChange={onChange} disabled={disabled ?? false} />
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
      <RSelect.Trigger id={id} className="select" aria-label={label}>
        <RSelect.Value placeholder={placeholder} />
        <RSelect.Icon className="select-icon"><ChevronDown {...ICON} size={14} /></RSelect.Icon>
      </RSelect.Trigger>
      <RSelect.Portal>
        <RSelect.Content className="popover select-content" position="popper" sideOffset={4} collisionPadding={8}>
          <RSelect.Viewport className="select-viewport">
            {options.map((o) => (
              <RSelect.Item key={o.value} value={encode(o.value)} className="menu-item select-item">
                <RSelect.ItemText>{o.label}</RSelect.ItemText>
                {o.hint && <span className="select-hint">{o.hint}</span>}
                <RSelect.ItemIndicator className="select-check"><Check {...ICON} size={14} /></RSelect.ItemIndicator>
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
  // "ember-gpt" → G: the distinguishing last word, since connects often share a prefix.
  const word = name.trim().split(/[\s\-_./]+/).filter(Boolean).at(-1) ?? name;
  const letter = ([...word][0] ?? "?").toUpperCase();
  return (
    <span className="avatar" aria-hidden="true"
      style={{ width: size, height: size, fontSize: Math.round(size * .52), background: AVATAR_TONES[hash % AVATAR_TONES.length], borderRadius: Math.min(size * .375, 12) }}>
      {letter}
    </span>
  );
}

export function Dialog({ open, title, description, onClose, children, footer, wide }:
  { open: boolean; title: ReactNode; description?: ReactNode; onClose(): void; children: ReactNode; footer?: ReactNode; wide?: boolean }) {
  return (
    <RDialog.Root open={open} onOpenChange={(next) => { if (!next) onClose(); }}>
      <RDialog.Portal>
        <RDialog.Overlay className="overlay" />
        {/* Focus the dialog itself rather than its first button, so the close button's tooltip does not pop up on open. */}
        <RDialog.Content className={`dialog${wide ? " dialog-wide" : ""}`} tabIndex={-1}
          onOpenAutoFocus={(e) => { e.preventDefault(); (e.currentTarget as HTMLElement).focus(); }}>
          <div className="dialog-head">
            <RDialog.Title className="dialog-title">{title}</RDialog.Title>
            <RDialog.Close asChild><IconButton label="关闭" icon={X} /></RDialog.Close>
          </div>
          {description ? <RDialog.Description className="dialog-lead">{description}</RDialog.Description> : <RDialog.Description className="sr-only">{title}</RDialog.Description>}
          <div className="dialog-body">{children}</div>
          {footer && <div className="dialog-foot">{footer}</div>}
        </RDialog.Content>
      </RDialog.Portal>
    </RDialog.Root>
  );
}

/** Asks before something that cannot be undone. `action` names what happens, e.g. "删除连接". */
export function Confirm({ open, title, description, action, onConfirm, onClose, busy }:
  { open: boolean; title: ReactNode; description: ReactNode; action: string; onConfirm(): void; onClose(): void; busy?: boolean | undefined }) {
  return (
    <RAlert.Root open={open} onOpenChange={(next) => { if (!next) onClose(); }}>
      <RAlert.Portal>
        <RAlert.Overlay className="overlay" />
        <RAlert.Content className="dialog dialog-alert">
          <RAlert.Title className="dialog-title">{title}</RAlert.Title>
          <RAlert.Description className="dialog-lead">{description}</RAlert.Description>
          <div className="dialog-foot">
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
      <DropdownMenu.Trigger asChild><IconButton label={label} icon={MoreHorizontal} /></DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content className="popover menu-list" align="end" sideOffset={4} collisionPadding={8}>
          {items.map((item, i) => item === "separator" ? <DropdownMenu.Separator key={i} className="menu-sep" /> : (
            <DropdownMenu.Item key={item.label} className="menu-item" data-danger={item.danger || undefined}
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

/** A titled block of a detail page. */
export function Section({ title, actions, children, description }: { title: ReactNode; actions?: ReactNode; description?: ReactNode; children: ReactNode }) {
  const id = useId();
  return (
    <section className="section" aria-labelledby={id}>
      <div className="section-head">
        <div>
          <h2 id={id}>{title}</h2>
          {description && <p className="section-sub">{description}</p>}
        </div>
        {actions && <div className="section-actions">{actions}</div>}
      </div>
      {children}
    </section>
  );
}

const KIND_ICON = { slack: Slack, wechat: MessageCircle } as const;

/** What a connect connects to, as an icon: its kind, not its identity. */
export function ConnectKindIcon({ kind, size = 16, tile }: { kind: string; size?: number; tile?: boolean }) {
  const Icon = KIND_ICON[kind as keyof typeof KIND_ICON] ?? MessageCircle;
  const icon = <Icon size={size} strokeWidth={1.7} aria-hidden="true" />;
  return tile ? <span className="mark kind-mark" style={{ width: size * 2.4, height: size * 2.4 }}>{icon}</span> : <span className="kind-icon">{icon}</span>;
}
