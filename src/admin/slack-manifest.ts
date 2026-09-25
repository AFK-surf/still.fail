// The Slack app manifest for an ember bot, and a link that opens Slack's
// "create app" page with it filled in. Scopes are deliberately broader than
// ember uses today, so later features (file upload, reactions as status,
// co-author lookup) do not need a reinstall.

export function slackManifest(name: string, description = "Coding agent in your threads (ember)"): Record<string, unknown> {
  return {
    display_information: { name, description, background_color: "#7a2e0e" },
    features: { bot_user: { display_name: name, always_online: true } },
    oauth_config: {
      scopes: {
        bot: [
          // read and answer messages
          "app_mentions:read", "channels:history", "groups:history", "im:history", "mpim:history",
          "chat:write", "chat:write.public", "chat:write.customize",
          // conversations: look up, join, open DMs
          "channels:read", "groups:read", "im:read", "mpim:read", "im:write", "mpim:write",
          "channels:join", "channels:manage", "groups:write",
          // files
          "files:read", "files:write", "remote_files:read", "remote_files:write", "remote_files:share",
          // reactions, pins, bookmarks
          "reactions:read", "reactions:write", "pins:read", "pins:write", "bookmarks:read", "bookmarks:write",
          // people and workspace
          "users:read", "users:read.email", "users.profile:read", "usergroups:read", "team:read", "emoji:read",
          // links, reminders, presence
          "links:read", "links:write", "reminders:read", "reminders:write", "dnd:read", "calls:read",
        ],
      },
    },
    settings: {
      event_subscriptions: {
        bot_events: [
          "app_mention", "message.channels", "message.groups", "message.im", "message.mpim",
          "reaction_added", "reaction_removed", "file_shared", "member_joined_channel", "channel_created",
        ],
      },
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
