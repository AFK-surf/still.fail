import assert from "node:assert/strict";
import test from "node:test";
import { PICTURE_BYTES, servePicture } from "../src/pictures.ts";

// GET /v1/pictures: Slack's pictures for the app in a browser (src/pictures.ts).

const SLACK = "https://avatars.slack-edge.com/2026-09-27/1_ab_72.jpg";
const asked = (url: string) => new Request(`https://app.still.fail/v1/pictures?url=${encodeURIComponent(url)}`);
const answering = (status: number, type: string, body: Uint8Array) => {
  const fetched: string[] = [];
  const get = async (url: string) => {
    fetched.push(url);
    return new Response(body, { status, headers: { "content-type": type } });
  };
  return { fetched, get };
};

test("a Slack picture is answered as it is, kept a day", async () => {
  const slack = answering(200, "image/jpeg", new Uint8Array([1, 2, 3]));
  const r = await servePicture(asked(SLACK), slack.get);
  assert.equal(r.status, 200);
  assert.deepEqual([...new Uint8Array(await r.arrayBuffer())], [1, 2, 3]);
  assert.equal(r.headers.get("content-type"), "image/jpeg");
  assert.equal(r.headers.get("cache-control"), "public, max-age=86400");
  assert.equal(r.headers.get("x-content-type-options"), "nosniff");
  assert.deepEqual(slack.fetched, [SLACK]);
});

test("no address but Slack's is fetched", async () => {
  for (const url of ["https://example.com/a.png", "http://avatars.slack-edge.com/a.jpg", "https://slack-edge.com.example.com/a.jpg", "https://169.254.169.254/", ""]) {
    const any = answering(200, "image/png", new Uint8Array([1]));
    assert.equal((await servePicture(asked(url), any.get)).status, 400, url);
    assert.deepEqual(any.fetched, []);
  }
});

test("what is not a picture, an SVG or one too large is not answered", async () => {
  assert.equal((await servePicture(asked(SLACK), answering(200, "text/html", new Uint8Array([1])).get)).status, 404);
  assert.equal((await servePicture(asked(SLACK), answering(200, "image/svg+xml", new Uint8Array([1])).get)).status, 404);
  assert.equal((await servePicture(asked(SLACK), answering(302, "image/png", new Uint8Array([])).get)).status, 404);
  assert.equal((await servePicture(asked(SLACK), answering(200, "image/png", new Uint8Array(PICTURE_BYTES + 1)).get)).status, 413);
  assert.equal((await servePicture(asked(SLACK), async () => { throw new Error("down"); })).status, 502);
});
