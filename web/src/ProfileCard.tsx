// A profile, or an account that could be one (the station machine's own login), as one card wherever it is listed:
// the settings' lists, a station's row in the first-profile guide, a narrow column. It lays itself out by its own width
// (a container query, ProfileCard.css.ts): its quota and state always beside its name, what it is wrapping under the name, and
// its action on a line of its own when narrow.
import type { ReactNode } from "react";
import { Link } from "react-router";
import type { MachineLogin } from "./core/shapes.ts";
import type { Profile } from "./api.ts";
import { QuotaBars } from "./components.tsx";
import { ACCESS } from "./format.ts";
import { ChevronRight } from "./icons.tsx";
import { ICON, Pill, ProviderLogo, RuntimeTags, Tip } from "./ui.tsx";
import * as css from "./ProfileCard.css.ts";
import * as waitingCss from "./styles/waiting.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as baseCss from "./styles/base.css.ts";
import { t } from "./i18n.ts";

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
      mark={<ProviderLogo runtime={profile.runtime} kind={profile.access.kind} mark={profile.providerMark} size={18} />}
      title={<>{profile.name}<RuntimeTags runtimes={profile.runtimes} /></>}
      sub={[profile.machine ? t("web-main.profile.machine") : profile.providerName ?? ACCESS[profile.access.kind].label, profile.usesText, profile.modelsText, uses]}
      quota={quota ? <QuotaBars quota={quota} compact /> : null}
      state={profile.checkTone !== "green" ? <State pill={<Pill tone={profile.checkTone}>{profile.checkText}</Pill>} why={trouble} /> : null}
      action={action ?? (to ? <ChevronRight {...ICON} className={css.profileCardChevron} /> : null)}
    />
  );
  const frame = framed ? "" : undefined;
  return to ? <Link className={`${css.profileCard} ${css.profileCardLink}`} data-framed={frame} to={to}>{body}</Link> : <div className={css.profileCard} data-framed={frame}>{body}</div>;
}

const RUNTIME: Record<MachineLogin["runtime"], string> = { claude: "Claude Code", codex: "Codex" };

/** The machine's own login, as an account a profile could be made with (`action`: making it), with its allowance. */
export function MachineLoginCard({ login, action, framed = true }: { login: MachineLogin; action?: ReactNode; framed?: boolean }) {
  const plan = login.plan ? `${login.plan[0]!.toUpperCase()}${login.plan.slice(1)}` : null;
  const quota = login.quota ?? null;
  const blocked = quota?.state === "blocked";
  const trouble = quota && (blocked || quota.state === "unavailable") ? quota.detail : null;
  return (
    <div className={css.profileCard} data-framed={framed ? "" : undefined}>
      <Card
        mark={<ProviderLogo runtime={login.runtime} kind="subscription" size={18} />}
        title={<>
          {RUNTIME[login.runtime]}
          {plan && <span className={waitingCss.runtimeTags}><span className={waitingCss.runtimeTag}>{plan}</span></span>}
          <State pill={<Pill tone={blocked ? "red" : "green"}>{blocked ? t("web-main.profile.blocked") : t("web-main.profile.machineSignedIn")}</Pill>} why={trouble} />
        </>}
        sub={[login.email ? <Tip key="email" label={login.email} cut><span className={css.profileCardEmail}>{login.email}</span></Tip> : t("web-main.profile.signedIn")]}
        quota={quota ? <QuotaBars quota={quota} compact /> : null}
        state={null}
        action={action ?? null}
      />
    </div>
  );
}

/** Its state, and why when something is wrong (what the provider said), on hover rather than in the card. */
function State({ pill, why }: { pill: ReactNode; why: string | null | undefined }) {
  return why ? <Tip label={why}><span className={css.profileCardWhy} tabIndex={0}>{pill}</span></Tip> : <>{pill}</>;
}

function Card({ mark, title, sub, quota, state, action }: {
  mark: ReactNode; title: ReactNode; sub: ReactNode[]; quota: ReactNode; state: ReactNode | null; action: ReactNode;
}) {
  // Each fact whole on a line where it fits: the line breaks between them.
  const facts = sub.filter(Boolean);
  return (
    <div className={css.profileCardGrid}>
      <span className={`${pagesCss.mark} ${waitingCss.runtimeMark} ${css.profileCardMark}`}>{mark}</span>
      <span className={css.profileCardMain}>
        <span className={css.profileCardTitle}>{title}</span>
        {facts.length > 0 && (
          <span className={css.profileCardSub}>
            {facts.map((f, i) => <span key={i} className={baseCss.phrase}>{f}{i < facts.length - 1 && "\u00a0·\u00a0"}</span>)}
          </span>
        )}
      </span>
      {quota && <span className={css.profileCardQuota}>{quota}</span>}
      {state && <span className={css.profileCardState}>{state}</span>}
      {action && <span className={css.profileCardAction}>{action}</span>}
    </div>
  );
}
