// A QR code the core made (qr.ts): its dark modules as one path, four modules of quiet zone around.
import type { QrCode as Code } from "./core/shapes.ts";
import * as css from "./QrCode.css.ts";

const QUIET = 4;

/** `dim`: one no longer to be scanned (expired), drawn faint under what says so. */
export function QrCode({ code, size, label, dim = false }: { code: Code; size: number; label: string; dim?: boolean }) {
  let d = "";
  code.rows.forEach((row, y) => {
    for (let x = 0; x < row.length; x++) {
      if (row[x] !== "1") continue;
      let end = x;
      while (end + 1 < row.length && row[end + 1] === "1") end++;
      d += `M${x + QUIET} ${y + QUIET}h${end - x + 1}v1h-${end - x + 1}z`;
      x = end;
    }
  });
  const n = code.size + QUIET * 2;
  return (
    <svg className={dim ? `${css.qr} ${css.dim}` : css.qr} width={size} height={size} viewBox={`0 0 ${n} ${n}`} role="img" aria-label={label} shapeRendering="crispEdges">
      <path fill="#000" d={d} />
    </svg>
  );
}
