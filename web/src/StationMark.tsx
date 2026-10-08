// A station where it is named: the emoji its workspace gave it (the settings' stations), else the server icon.
import { Server } from "./icons.tsx";
import * as css from "./StationMark.css.ts";

export function StationMark({ emoji, size = 14, className }: { emoji?: string | null | undefined; size?: number; className?: string | undefined }) {
  if (!emoji) return <Server size={size} className={className} />;
  return (
    <span className={`${css.emoji}${className ? ` ${className}` : ""}`} style={{ width: size, height: size, fontSize: Math.round(size * 0.9) }} aria-hidden="true">{emoji}</span>
  );
}
