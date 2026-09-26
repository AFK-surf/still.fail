// The Slack app manifest for an ember connect, and a link that opens Slack's
// "create app" page with it filled in. Every permission group is on, so later
// features (file upload, reactions as status, co-author lookup) do not need a
// reinstall; people can turn groups off on the connect page.
import { SLACK_GROUP_IDS, SLACK_GROUPS } from "../chat/slack-apps.ts";

/** Every bot scope of every permission group. */
export function botScopes(): string[] {
  return [...new Set(SLACK_GROUP_IDS.flatMap((g) => SLACK_GROUPS[g].scopes))];
}

/**
 * `redirectUrl`: where Slack sends a person who installed it (ember cloud's page that hands the code to the station),
 * so the bot token is not copied by hand.
 */
export function slackManifest(name: string, description = "Coding agent in your threads (ember)", redirectUrl?: string): Record<string, unknown> {
  return {
    display_information: { name, description, background_color: "#7a2e0e" },
    features: { bot_user: { display_name: name, always_online: true } },
    oauth_config: { scopes: { bot: botScopes() }, ...(redirectUrl ? { redirect_urls: [redirectUrl] } : {}) },
    settings: {
      event_subscriptions: { bot_events: [...new Set(SLACK_GROUP_IDS.flatMap((g) => SLACK_GROUPS[g].events))] },
      interactivity: { is_enabled: false },
      org_deploy_enabled: false,
      socket_mode_enabled: true,
      token_rotation_enabled: false,
    },
  };
}

export function createAppUrl(name: string): string {
  return `https://api.slack.com/apps?new_app=1&manifest_json=${encodeURIComponent(JSON.stringify(slackManifest(name)))}`;
}
