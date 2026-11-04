// The pictures a browser's page cannot read from where they are: their servers say nothing of other pages
// (Access-Control-Allow-Origin), so the core in a browser has still.fail cloud fetch them for it (GET /v1/pictures,
// cloud/src/pictures.ts), and the cloud fetches no others. Slack's (its people's and its bots' pictures, on
// avatars.slack-edge.com); Google's, Gravatar's and Feishu's say any page may.

/// Whether `url` is a picture still.fail cloud fetches for a browser.
export function relayedPicture(url: string): boolean {
  let at: URL;
  try {
    at = new URL(url);
  } catch {
    return false;
  }
  return at.protocol === "https:" && at.port === "" && at.username === "" && at.password === "" && (at.hostname === "slack-edge.com" || at.hostname.endsWith(".slack-edge.com"));
}

/// Where still.fail cloud at `origin` answers with the picture at `url`.
export const pictureRelay = (origin: string, url: string): string => `${origin}/v1/pictures?url=${encodeURIComponent(url)}`;
