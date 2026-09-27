// Slack messages go out as the agent wrote them, in Slack's own formatting (mrkdwn: instructions.ts tells it how): no
// converting, only splitting what is too long for one message.

/** Splits text for Slack's message size, preferring paragraph, then line boundaries. */
export function splitForSlack(text: string, limit = 3500): string[] {
  const chunks: string[] = [];
  let rest = text;
  while (rest.length > limit) {
    let cut = rest.lastIndexOf("\n\n", limit);
    if (cut < limit / 2) cut = rest.lastIndexOf("\n", limit);
    if (cut < limit / 2) cut = limit;
    chunks.push(rest.slice(0, cut));
    rest = rest.slice(cut).replace(/^\n+/, "");
  }
  if (rest.length > 0 || chunks.length === 0) chunks.push(rest);
  return chunks;
}
