// What the share page has of web/src/ui.tsx (in its place: web/vite.share.config.ts): a tip says nothing more there
// (what it would say is on the page already, or a button's label), people's tiles are the chat's, and the preview's
// choice of how a file shows (FilePreview.tsx) is ui.tsx's Segmented as it is.
import { ToggleGroup } from "radix-ui";
import type { CSSProperties, ReactNode } from "react";
import * as css from "../../ui.css.ts";

export { Avatar } from "../../Avatar.tsx";

export function Tip({ children }: { label?: ReactNode; children: ReactNode; side?: string; shortcut?: unknown; cut?: boolean }) {
  return <>{children}</>;
}

/** A small set of exclusive options shown side by side (ui.tsx's, as it is there). */
export function Segmented<T extends string>({ options, value, onChange, label, className }:
  { options: { value: T; label: ReactNode; disabled?: boolean | undefined }[]; value: T; onChange(value: T): void; label: string; className?: string }) {
  const index = Math.max(0, options.findIndex((o) => o.value === value));
  return (
    <ToggleGroup.Root type="single" className={className ? `${css.segmented} ${className}` : css.segmented} aria-label={label} value={value}
      style={{ "--n": options.length, "--i": index } as CSSProperties}
      onValueChange={(v) => { if (v) onChange(v as T); }}>
      <span className={css.segmentedThumb} aria-hidden="true" />
      {options.map((o) => (
        <ToggleGroup.Item key={o.value} value={o.value} disabled={o.disabled ?? false} className={css.segmentedOption}>
          <span className={css.segmentedLabel}>{o.label}</span><span className={css.segmentedSizer} aria-hidden="true">{o.label}</span>
        </ToggleGroup.Item>
      ))}
    </ToggleGroup.Root>
  );
}
