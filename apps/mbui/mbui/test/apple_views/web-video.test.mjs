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
  play() { this.paused = false; return Promise.resolve(); }
  pause() { this.paused = true; }
}

function player(videoFrames = true) {
  const video = new Video(videoFrames), messages = [];
  const context = {
    document: { getElementById: () => video },
    window: { webkit: { messageHandlers: { mbvideo: { postMessage: (m) => messages.push(m) } } } },
    requestAnimationFrame: () => {},
  };
  vm.runInNewContext(script, context);
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
