// Exercise the WebKit player's page with host events in either order, without a window or a real clock.
import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";

const source = readFileSync(new URL("../../src/host/apple_webm.h", import.meta.url), "utf8");
const part = source.split("static NSString *const kWebVideoHTML =")[1].split("// One byte range")[0];
const html = [...part.matchAll(/^\s*@?"((?:[^"\\]|\\.)*)"/gm)]
  .map((m) => JSON.parse('"' + m[1] + '"')).join("");
const script = html.match(/<script>([\s\S]*)<\/script>/)[1];

class Video {
  constructor(videoFrames = true) {
    this.handlers = new Map();
    this.callbacks = new Map();
    this.next = 1;
    this.time = 0;
    this.seeking = false;
    this.readyState = 2;
    this.paused = true;
    this.ended = false;
    this.duration = 10;
    this.videoWidth = 320;
    this.videoHeight = 240;
    this.playbackRate = 1;
    this.buffered = { length: 0 };
    this.error = null;
    this.muted = false;
    this.refusePlay = false;
    if (!videoFrames) this.requestVideoFrameCallback = undefined;
  }
  get currentTime() { return this.time; }
  set currentTime(t) { this.time = t; this.seeking = true; }
  addEventListener(name, fn, options = {}) {
    const a = this.handlers.get(name) || [];
    a.push({ fn, once: !!options.once });
    this.handlers.set(name, a);
  }
  removeEventListener(name, fn) {
    this.handlers.set(name, (this.handlers.get(name) || []).filter((v) => v.fn !== fn));
  }
  emit(name) {
    for (const item of [...(this.handlers.get(name) || [])]) {
      if (item.once) this.removeEventListener(name, item.fn);
      item.fn();
    }
  }
  requestVideoFrameCallback(fn) {
    const id = this.next++;
    this.callbacks.set(id, fn);
    return id;
  }
  cancelVideoFrameCallback(id) { this.callbacks.delete(id); }
  frame(time = this.time) {
    const entry = this.callbacks.entries().next().value;
    assert.ok(entry, "a frame was requested");
    this.callbacks.delete(entry[0]);
    entry[1](0, { mediaTime: time });
  }
  finishSeek() { this.seeking = false; this.emit("seeked"); }
  load() {}
  play() {
    if (this.refusePlay) return Promise.reject(new Error("refused"));
    this.paused = false;
    return Promise.resolve();
  }
  pause() { this.paused = true; }
}

function player(videoFrames = true, mp4 = false) {
  const video = new Video(videoFrames), messages = [];
  const context = {
    document: { getElementById: () => video },
    window: { webkit: { messageHandlers: { mbvideo: { postMessage: (m) => messages.push(m) } } } },
    requestAnimationFrame: () => {},
  };
  vm.runInNewContext(mp4 ? script.replace("const playToSeek=false,", "const playToSeek=true,") : script, context);
  return {
    video,
    api: context.window.mbPlayer,
    count: (type) => messages.filter((m) => m.type === type).length,
    state: () => messages.filter((m) => m.type === "state").at(-1),
  };
}

test("capture waits for a video frame and the seek, in either order", () => {
  const { video, api, count, state } = player();
  assert.equal(state().ready, false, "metadata alone does not mean a video frame was presented");
  api.grab(-1);
  assert.equal(count("grabReady"), 0);
  video.frame();
  assert.equal(state().ready, true);
  assert.equal(count("grabReady"), 1);
  api.endGrab();
  api.seek(2500);
  api.grab(-1);
  video.finishSeek();
  assert.equal(count("grabReady"), 1);
  video.frame();
  assert.equal(count("grabReady"), 2);
  api.endGrab();
  api.seek(3000);
  api.grab(-1);
  video.frame();
  assert.equal(count("grabReady"), 2);
  video.finishSeek();
  assert.equal(count("grabReady"), 3);
});

test("an obsolete frame does not complete a later seek", () => {
  const { video, api, count } = player();
  video.frame();
  api.seek(1000);
  const obsolete = video.callbacks.values().next().value;
  api.seek(5000);
  api.grab(-1);
  video.finishSeek();
  obsolete(0, { mediaTime: 1 });
  assert.equal(count("grabReady"), 0);
  video.frame();
  assert.equal(count("grabReady"), 1);
});

test("a frame from before a seek cannot make that seek ready", () => {
  const { video, api, count } = player();
  video.frame(0);
  video.frame(0.1);
  video.frame(0.2);
  api.seek(2500);
  api.grab(-1);
  video.frame(0.9);
  video.finishSeek();
  assert.equal(count("grabReady"), 0);
  video.frame(2.5);
  assert.equal(count("grabReady"), 1);
});

test("what shows now is grabbed without waiting for a seek", () => {
  const { api, count, video } = player();
  video.frame();
  api.seek(2500);
  assert.equal(video.seeking, true);
  api.grab(-1);
  assert.equal(count("grabReady"), 0);
  api.endGrab();
  api.grab(-1, true);
  assert.equal(count("grabReady"), 1);
});

test("a grab given up is forgotten, whether it waited for a seek or for the file", () => {
  const seeking = player();
  seeking.video.frame();
  seeking.api.seek(2500);
  seeking.api.grab(-1);
  seeking.api.endGrab();
  seeking.video.finishSeek();
  seeking.video.frame(2.5);
  assert.equal(seeking.count("grabReady"), 0);
  const loading = player();
  loading.video.readyState = 0;
  loading.api.grab(0);
  loading.api.endGrab();
  loading.video.readyState = 2;
  loading.video.emit("loadeddata");
  loading.video.frame();
  assert.equal(loading.count("grabReady"), 0);
});

test("a frame captured elsewhere restores the playhead unless it changed", () => {
  const { video, api, count } = player();
  video.frame();
  api.grab(1000);
  video.finishSeek();
  video.frame();
  assert.equal(count("grabReady"), 1);
  api.endGrab();
  assert.equal(video.currentTime, 0);
  video.finishSeek();
  video.frame();
  api.grab(2000);
  video.finishSeek();
  video.frame();
  api.pause();
  api.endGrab();
  assert.equal(video.currentTime, 2);
});

test("an error completes a pending grab and a host without frame callbacks uses seeked", () => {
  const a = player();
  a.api.grab(-1);
  a.video.error = { code: 4 };
  a.video.emit("error");
  assert.equal(a.count("grabFailed"), 1);
  const b = player(false);
  b.api.seek(1000);
  b.api.grab(-1);
  assert.equal(b.count("grabReady"), 0);
  b.video.finishSeek();
  assert.equal(b.count("grabReady"), 1);
});

// VP9 in MP4: WebKit often never finishes a seek made while paused (#3993).
test("a paused MP4 seek plays muted to the target frame, then pauses there", () => {
  const { video, api, count, state } = player(true, true);
  video.frame();
  api.seek(2500);
  assert.equal(video.paused, false, "the seek is made while playing");
  assert.equal(video.muted, true, "no sound while getting there");
  assert.equal(video.playbackRate, 0.1, "no frame after the old position is due before the seek lands");
  assert.equal(state().rate, 1);
  assert.equal(state().playing, false);
  assert.equal(state().position, 2500);
  api.grab(-1);
  video.finishSeek();
  assert.equal(video.playbackRate, 1, "the target frame is not slowed");
  video.frame(2.6);
  assert.equal(video.paused, true);
  assert.equal(video.muted, false);
  assert.equal(video.playbackRate, 1);
  assert.equal(state().playing, false);
  assert.equal(state().position, 2500, "the target, not where the muted play got to");
  assert.equal(count("grabReady"), 1);
});

test("a paused MP4 frame capture elsewhere goes there and back the same way", () => {
  const { video, api, count, state } = player(true, true);
  video.frame();
  api.seek(2500);
  video.finishSeek();
  video.frame(2.5);
  video.time = 2.53;
  api.grab(1000);
  assert.equal(video.paused, false);
  video.finishSeek();
  video.frame(1);
  assert.equal(count("grabReady"), 1);
  assert.equal(video.paused, true);
  api.endGrab();
  assert.equal(video.currentTime, 2.5, "back to the target the app was told");
  assert.equal(video.paused, false);
  video.finishSeek();
  video.frame(2.5);
  assert.equal(video.paused, true);
  assert.equal(state().position, 2500);
});

test("playing during a paused MP4 seek keeps playing with its sound", () => {
  const { video, api, state } = player(true, true);
  video.muted = true;
  video.frame();
  api.seek(2500);
  api.volume(1);
  video.muted = true;
  api.play();
  assert.equal(video.muted, true, "the page's own mute is restored, not cleared");
  const b = player(true, true);
  b.video.frame();
  b.api.seek(2500);
  b.api.rate(2);
  assert.equal(b.state().rate, 2);
  b.api.play();
  assert.equal(b.video.muted, false);
  assert.equal(b.video.playbackRate, 2, "the speed asked for meanwhile");
  b.video.finishSeek();
  b.video.frame(2.5);
  assert.equal(b.video.paused, false, "the target frame does not pause a play");
  assert.equal(b.state().playing, true);
  b.video.time = 2.7;
  b.api.pause();
  assert.equal(b.state().position, 2700);
  assert.equal(state().playing, true);
});

test("a paused MP4 seek that cannot play still seeks, and WebM and a playing MP4 seek directly", async () => {
  const a = player(true, true);
  a.video.frame();
  a.video.refusePlay = true;
  a.api.seek(2500);
  await new Promise((r) => setImmediate(r));
  assert.equal(a.video.muted, false);
  assert.equal(a.video.currentTime, 2.5);
  const b = player();
  b.video.frame();
  b.api.seek(2500);
  assert.equal(b.video.paused, true);
  const c = player(true, true);
  c.video.frame();
  c.api.play();
  c.api.seek(2500);
  assert.equal(c.video.muted, false);
  assert.equal(c.state().playing, true);
  const d = player(true, true);
  d.video.frame();
  d.api.seek(10000);
  assert.equal(d.video.paused, true, "the very end is not played to");
});

test("a paused MP4 seek whose frame never comes stops a second past the target, or at the end", () => {
  const { video, api, state } = player(true, true);
  video.frame();
  api.seek(2500);
  video.finishSeek();
  video.time = 3.4;
  video.emit("timeupdate");
  assert.equal(video.paused, false, "not yet a second past");
  video.time = 3.6;
  video.emit("timeupdate");
  assert.equal(video.paused, true);
  assert.equal(video.muted, false);
  assert.equal(state().playing, false);
  const b = player(true, true);
  b.video.frame();
  b.api.seek(4500);
  b.video.finishSeek();
  b.video.time = 5;
  b.video.paused = true;
  b.video.ended = true;
  b.video.emit("ended");
  assert.equal(b.video.muted, false);
  assert.equal(b.state().playing, false);
});
