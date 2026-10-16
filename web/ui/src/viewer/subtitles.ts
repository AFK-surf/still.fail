// A video's subtitle beside it (E01.srt for E01.mp4), as WebVTT for the <track> the player gives it: SubRip's commas
// in times become dots; an ASS/SSA file's dialogue lines become cues, their styling dropped.

/** "00:01:02,500" (or "0:01:02.50") as WebVTT's "00:01:02.500". */
function vttTime(time: string): string {
  const m = /^(\d+):(\d{1,2}):(\d{1,2})[.,](\d{1,3})$/.exec(time.trim());
  if (!m) return time.trim().replace(",", ".");
  const [, h, mm, ss, frac] = m;
  return `${h!.padStart(2, "0")}:${mm!.padStart(2, "0")}:${ss!.padStart(2, "0")}.${frac!.padEnd(3, "0").slice(0, 3)}`;
}

/** SubRip as WebVTT. */
export function srtToVtt(srt: string): string {
  const blocks = srt.replace(/^﻿/, "").replace(/\r\n?/g, "\n").split(/\n{2,}/);
  const cues = blocks.flatMap((block) => {
    const lines = block.split("\n").filter((l, i) => !(i === 0 && /^\d+$/.test(l.trim())));
    const at = lines.findIndex((l) => l.includes("-->"));
    if (at < 0) return [];
    const [from, to] = lines[at]!.split("-->");
    const text = lines.slice(at + 1).join("\n").trim();
    return text ? [`${vttTime(from!)} --> ${vttTime(to!.trim().split(/\s+/)[0]!)}\n${text}`] : [];
  });
  return `WEBVTT\n\n${cues.join("\n\n")}\n`;
}

/** ASS/SSA's dialogue as WebVTT (its styles and positions left out; \N a new line). */
export function assToVtt(ass: string): string {
  const lines = ass.replace(/^﻿/, "").replace(/\r\n?/g, "\n").split("\n");
  let format: string[] = [];
  let events = false;
  const cues: string[] = [];
  for (const line of lines) {
    if (/^\[events\]/i.test(line.trim())) { events = true; continue; }
    if (/^\[/.test(line.trim())) { events = false; continue; }
    if (!events) continue;
    if (/^format:/i.test(line)) { format = line.slice(line.indexOf(":") + 1).split(",").map((f) => f.trim().toLowerCase()); continue; }
    if (!/^dialogue:/i.test(line) || !format.length) continue;
    const parts = line.slice(line.indexOf(":") + 1).split(",");
    const field = (name: string) => parts[format.indexOf(name)]?.trim() ?? "";
    // The text is the last field, and may have commas of its own.
    const text = parts.slice(format.length - 1).join(",").replace(/\{[^}]*\}/g, "").replace(/\\N/gi, "\n").replace(/\\h/g, " ").trim();
    if (text) cues.push(`${vttTime(field("start"))} --> ${vttTime(field("end"))}\n${text}`);
  }
  return `WEBVTT\n\n${cues.join("\n\n")}\n`;
}

/** A subtitle file's text as WebVTT, by its name. */
export function toVtt(name: string, text: string): string {
  const ext = name.slice(name.lastIndexOf(".") + 1).toLowerCase();
  if (ext === "vtt") return text;
  if (ext === "ass" || ext === "ssa") return assToVtt(text);
  return srtToVtt(text);
}
