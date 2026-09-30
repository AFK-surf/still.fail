// A station's software on its page on a narrow screen, as the Android app has it (apps/android/…/screens/Versions.kt):
// the wide screen's versions (../Versions.tsx: useSoftware, describe), one to a row on a card, then the check. What the
// wide screen says on hover is said under the name.
import type { SoftwareVersion } from "../core/shapes.ts";
import { describe, useSoftware } from "../Versions.tsx";
import { ListCard, ListRow, SectionHeader, Spinner } from "./parts.tsx";
import * as css from "./Versions.css.ts";

/** `updates`: the station's overview's (none from a station older than them: nothing shows); `manager`: may update. */
export function Versions({ station, updates, manager }: { station: string; updates: SoftwareVersion[] | undefined; manager: boolean }) {
  const { update, check } = useSoftware(station);
  if (!updates?.length) return null;
  const checked = updates[0]?.checkedAt;
  const failed = update.error ?? check.error;
  return (
    <>
      <SectionHeader title="版本" trailing={checked != null ? `上次检查 ${new Date(checked).toLocaleString("zh-CN", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" })}` : undefined} start={24} />
      <ListCard>
        {updates.map((v) => <Row key={v.id} v={v} manager={manager} busy={update.busy && update.args?.[0] === v.id} onUpdate={() => void update.run(v.id)} />)}
        <ListRow onClick={checked == null || check.busy ? undefined : () => void check.run()}>
          <span className={css.mVersionCheck}>{checked == null ? "正在检查版本…" : check.busy ? "正在检查…" : "检查更新"}</span>
          {(checked == null || check.busy) && <Spinner size={13} />}
        </ListRow>
      </ListCard>
      {failed && <p className={css.mVersionError}>{failed.message}</p>}
    </>
  );
}

function Row({ v, manager, busy, onUpdate }: { v: SoftwareVersion; manager: boolean; busy: boolean; onUpdate(): void }) {
  const { shown, verb, tip, updating } = describe(v);
  const note = [tip, v.state === "failed" ? v.message : null].filter(Boolean).join("；");
  const action = (label: string) => manager && v.updatable && (
    busy ? <Spinner size={13} /> : <button type="button" className={css.mVersionAction} onClick={onUpdate}>{label}</button>
  );
  return (
    <ListRow>
      <span className={css.mVersionText}>
        <span className={css.mVersionHead}><span className={css.mVersionName}>{v.name}</span><span className={css.mVersionShown}>{shown}</span></span>
        {note && <span className={css.mVersionNote} data-failed={v.state === "failed" || undefined}>{note}</span>}
      </span>
      {v.state === "updating" ? <span className={css.mVersionState}><Spinner size={12} />{updating}</span>
        : v.state === "failed" ? <span className={css.mVersionState}><span className={css.mVersionNote} data-failed style={{ fontWeight: 500 }}>{verb}失败</span>{action("重试")}</span>
        : !v.installed ? <span className={css.mVersionState}>{action("安装")}</span>
        : v.newer && v.latest ? <span className={css.mVersionState}>→ {v.latest}{action("更新")}</span>
        : null}
    </ListRow>
  );
}
