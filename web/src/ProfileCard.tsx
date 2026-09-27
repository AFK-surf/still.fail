// A profile, or an account that could be one (the station machine's own login), as one card wherever it is listed:
// the settings' lists, a station's row in the first-profile guide, a narrow column. It lays itself out by its own width
// (a container query, app.css): in one line when there is room, name and state above what it is and its quota when
// there is less, and its action on a line of its own when narrow.
import type { ReactNode } from "react";
import { Link } from "react-router";
import type { MachineLogin } from "./core/shapes.ts";
import type { Profile } from "./api.ts";
import { QuotaBars } from "./components.tsx";
import { ACCESS } from "./format.ts";
import { ChevronRight } from "./icons.tsx";
import { ICON, Pill, ProviderLogo, RuntimeTags, Tip } from "./ui.tsx";

/**
 * A profile: its name and runtimes, what it is and who uses it (`uses`, said by the page), its quota and its check.
 * `framed`: a card of its own (not a row of a list); `to`: the whole of it leads there.
 */
export function ProfileCard({ profile, uses, to, action, framed }: { profile: Profile; uses?: string; to?: string; action?: ReactNode; framed?: boolean }) {
  const quota = profile.quota;
  // Why its allowance could not be read (a refused account, a sign-in gone stale), shown on its state's hover.
  const trouble = quota && (quota.state === "blocked" || quota.state === "unavailable") ? quota.detail : null;
  const body = (
    <Card
      mark={<ProviderLogo runtime={profile.runtime} kind={profile.access.kind} size={18} />}
      title={<>{profile.name}<RuntimeTags runtimes={profile.runtimes} /></>}
      sub={[profile.machine ? "本机登录" : ACCESS[profile.access.kind].label, profile.modelsText, uses].filter(Boolean).join(" · ")}
      quota={quota ? <QuotaBars quota={quota} compact /> : null}
      state={<State pill={<Pill tone={profile.checkTone}>{profile.checkText}</Pill>} why={trouble} />}
      action={action ?? (to ? <ChevronRight {...ICON} className="profile-card-chevron" /> : null)}
    />
  );
  const frame = framed ? "" : undefined;
  return to ? <Link className="profile-card profile-card-link" data-framed={frame} to={to}>{body}</Link> : <div className="profile-card" data-framed={frame}>{body}</div>;
}

const RUNTIME: Record<MachineLogin["runtime"], string> = { claude: "Claude Code", codex: "Codex" };

/** The machine's own login, as an account a profile could be made with (`action`: making it), with its allowance. */
export function MachineLoginCard({ login, action, framed = true }: { login: MachineLogin; action?: ReactNode; framed?: boolean }) {
  const plan = login.plan ? `${login.plan[0]!.toUpperCase()}${login.plan.slice(1)}` : null;
  const quota = login.quota ?? null;
  const blocked = quota?.state === "blocked";
  const trouble = quota && (blocked || quota.state === "unavailable") ? quota.detail : null;
  return (
    <div className="profile-card" data-framed={framed ? "" : undefined}>
      <Card
        mark={<ProviderLogo runtime={login.runtime} kind="subscription" size={18} />}
        title={RUNTIME[login.runtime]}
        sub={[login.email, plan].filter(Boolean).join(" · ") || "已登录"}
        quota={quota ? <QuotaBars quota={quota} compact /> : null}
        state={<State pill={<Pill tone={blocked ? "red" : "green"}>{blocked ? "被停用" : "本机已登录"}</Pill>} why={trouble} />}
        action={action ?? null}
      />
    </div>
  );
}

/** Its state, and why when something is wrong (what the provider said), on hover rather than in the card. */
function State({ pill, why }: { pill: ReactNode; why: string | null | undefined }) {
  return why ? <Tip label={why}><span className="profile-card-why" tabIndex={0}>{pill}</span></Tip> : <>{pill}</>;
}

function Card({ mark, title, sub, quota, state, action }: {
  mark: ReactNode; title: ReactNode; sub: string; quota: ReactNode; state: ReactNode; action: ReactNode;
}) {
  return (
    <div className="profile-card-grid">
      <span className="mark runtime-mark profile-card-mark">{mark}</span>
      <span className="profile-card-main">
        <span className="profile-card-title">{title}</span>
        {sub && <span className="profile-card-sub">{sub}</span>}
      </span>
      {quota && <span className="profile-card-quota">{quota}</span>}
      <span className="profile-card-state">{state}</span>
      {action && <span className="profile-card-action">{action}</span>}
    </div>
  );
}
