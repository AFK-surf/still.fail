// The preview beside a folder's list (⌘⇧P, as Finder's preview pane): the file chosen shown there as it is chosen (a
// picture whole, the start of a text, Markdown rendered, code as it is), with what it is, where (its station, its path)
// and its size and time; what plays (a video, a song) or needs a page of its own (a PDF) says how to open it. Several
// chosen, or a folder, say so. The files' page and a chat's 文件 tab both have it.
import { useEffect, useState } from "react";
import type { DriveEntry } from "../core/shapes.ts";
import { joinPath, readKept, readPart, type At } from "../drive/model.ts";
import { absoluteOf } from "../drive/useDrive.ts";
import { KindIcon } from "../drive/KindIcon.tsx";
import { Prose } from "../Prose.tsx";
import { Button } from "../ui.tsx";
import { Copy, Download } from "@stillfail/ui/icons.tsx";
import * as css from "./DrivePane.css.ts";
import { t } from "../i18n.ts";

/** A picture is shown whole up to this size; past it, as the others are, by how to open it. */
const MOST_PICTURE = 32 * 1024 * 1024;
/** The start of a text shown. */
const TEXT_PART = 64 * 1024;

/** What the preview shows: one file (where it is, its entry), several chosen, or nothing. */
export type Previewed = { at: At; entry: DriveEntry } | { many: number } | null;

export function DrivePane({ shown, stationName, onOpen, onSave, onCopyPath, below = false }: {
  shown: Previewed; stationName: string; onOpen: () => void; onSave: () => void; onCopyPath: (abs: string) => void;
  /** Under the list rather than beside it (a chat's 文件 tab, narrow). */
  below?: boolean;
}) {
  if (shown === null || "many" in shown) {
    return <aside className={css.pane} data-below={below || undefined}><p className={css.none}>{shown ? t("web-pages.files.previewMany", { n: shown.many }) : t("web-pages.files.previewNone")}</p></aside>;
  }
  const { at, entry } = shown;
  const abs = absoluteOf(at.root, joinPath(at.path, entry.name));
  return (
    <aside className={css.pane} data-below={below || undefined} aria-label={t("web-pages.files.preview")}>
      <div className={css.body}>
        <Body key={`${at.station}\n${abs}\n${entry.mtime}`} at={{ ...at, path: joinPath(at.path, entry.name) }} entry={entry} onOpen={onOpen} />
      </div>
      <div className={css.about}>
        <div className={css.name}>{entry.name}</div>
        <dl className={css.facts}>
          {!entry.dir && <><dt>{t("web-pages.files.size")}</dt><dd>{entry.sizeText}</dd></>}
          <dt>{t("web-pages.files.modified")}</dt><dd>{entry.timeText}</dd>
          <dt>Station</dt><dd>{stationName}</dd>
          <dt>{t("web-pages.files.where")}</dt><dd className={css.path} title={abs}>{abs}</dd>
        </dl>
        <div className={css.actions}>
          <Button onClick={onOpen}>{t("web-pages.drive.open")}</Button>
          {!entry.dir && <Button variant="ghost" icon={Download} onClick={onSave}>{t("web-pages.drive.download")}</Button>}
          <Button variant="ghost" icon={Copy} onClick={() => onCopyPath(abs)}>{t("web-pages.drive.copyPath")}</Button>
        </div>
      </div>
    </aside>
  );
}

/** What the file is, shown as it can be here. */
function Body({ at, entry, onOpen }: { at: At; entry: DriveEntry; onOpen: () => void }) {
  if (entry.kind === "image" && entry.size <= MOST_PICTURE && !/\.hei[cf]$/i.test(entry.name)) return <Picture at={at} entry={entry} />;
  if (["text", "markdown", "code", "csv", "html", "subtitle"].includes(entry.kind)) return <Text at={at} entry={entry} />;
  return (
    <button type="button" className={css.mark} onClick={onOpen}>
      <KindIcon kind={entry.kind} size={56} />
      <span>{entry.kind === "video" || entry.kind === "audio" ? t("web-pages.files.previewPlay") : entry.dir ? t("web-pages.files.previewFolder") : t("web-pages.files.previewOpen")}</span>
    </button>
  );
}

function Picture({ at, entry }: { at: At; entry: DriveEntry }) {
  const [url, setUrl] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let live = true;
    let made: string | null = null;
    readKept(at, entry, entry.type).then((blob) => {
      if (!live) return;
      made = URL.createObjectURL(blob);
      setUrl(made);
    }, () => { if (live) setFailed(true); });
    return () => { live = false; if (made) URL.revokeObjectURL(made); };
  }, [at.station, at.root, at.path, entry.mtime]); // eslint-disable-line react-hooks/exhaustive-deps
  if (failed) return <p className={css.none}>{t("web-pages.files.previewFailed")}</p>;
  return url ? <img className={css.picture} src={url} alt={entry.name} /> : <div className={css.waiting} />;
}

function Text({ at, entry }: { at: At; entry: DriveEntry }) {
  const [text, setText] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let live = true;
    readPart(at, 0, Math.min(TEXT_PART, entry.size)).then((got) => { if (live) setText(new TextDecoder().decode(got.bytes)); }, () => { if (live) setFailed(true); });
    return () => { live = false; };
  }, [at.station, at.root, at.path, entry.mtime]); // eslint-disable-line react-hooks/exhaustive-deps
  if (failed) return <p className={css.none}>{t("web-pages.files.previewFailed")}</p>;
  if (text === null) return <div className={css.waiting} />;
  const cut = entry.size > TEXT_PART ? <p className={css.more}>{t("web-pages.files.previewMore")}</p> : null;
  return entry.kind === "markdown"
    ? <div className={css.prose}><Prose>{text}</Prose>{cut}</div>
    : <div className={css.textBox}><pre className={css.code}>{text}</pre>{cut}</div>;
}
