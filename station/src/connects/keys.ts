// Where the names book (connects/names.ts) keeps what a platform calls people and channels, and under what: each
// platform's own file, a person or a channel by the place its names are of (a Slack workspace's team: two connects in one
// Slack workspace share its names; a Feishu or Comma connect itself: its people's ids are its app's own, or its Comma
// Group's). The surfaces write
// them; the readers read them (read/slack-known.ts).
export const NAMES_FILE = { slack: "slack-names.json", feishu: "feishu-names.json", comma: "comma-names.json" } as const;

/// The connects of other stations whose chats run on this one, as their stations described them (connects/remote.ts).
export const REMOTE_FILE = "remote-connects.json";

export const personKey = (place: string, user: string) => `u:${place}:${user}`;
export const channelKey = (place: string, channel: string) => `c:${place}:${channel}`;
