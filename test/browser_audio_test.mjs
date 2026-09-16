import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const bridge = await readFile(new URL("../web/narration_audio.js", import.meta.url), "utf8");
const nextTurn = () => new Promise((resolve) => setImmediate(resolve));

function browser(t, { streaming = true } = {}) {
  const audios = [];
  const mediaSources = [];
  const urls = new Map();
  const revoked = [];
  const progress = [];
  class Audio extends EventTarget {
    constructor() {
      super();
      this.playCalls = 0;
      this.pauseCalls = 0;
      this.currentTime = 0;
      this.duration = Infinity;
      audios.push(this);
    }
    play() { this.playCalls++; return Promise.resolve(); }
    pause() { this.pauseCalls++; }
    removeAttribute(name) { delete this[name]; }
    load() {}
  }
  class SourceBuffer extends EventTarget {
    constructor() { super(); this.appends = []; this.updating = false; }
    appendBuffer(bytes) {
      assert.equal(this.updating, false, "appendBuffer must wait for updateend");
      this.appends.push([...bytes]);
      this.updating = true;
    }
    finishAppend() {
      assert.equal(this.updating, true);
      this.updating = false;
      this.dispatchEvent(new Event("updateend"));
    }
  }
  class MediaSource extends EventTarget {
    static isTypeSupported(type) {
      assert.equal(type, "audio/mpeg");
      return streaming;
    }
    constructor() {
      super();
      this.readyState = "closed";
      this.endCalls = 0;
      mediaSources.push(this);
    }
    open() { this.readyState = "open"; this.dispatchEvent(new Event("sourceopen")); }
    addSourceBuffer(type) {
      assert.equal(type, "audio/mpeg");
      assert.equal(this.readyState, "open");
      this.buffer = new SourceBuffer();
      return this.buffer;
    }
    endOfStream() {
      assert.equal(this.buffer.updating, false, "EOS must wait for the final append");
      this.endCalls++;
      this.readyState = "ended";
    }
  }
  const context = vm.createContext({
    Audio, MediaSource, Blob, setTimeout, clearTimeout,
    console: { info() {} },
    URL: {
      createObjectURL(object) {
        const url = `blob:test-${urls.size}`;
        urls.set(url, object);
        return url;
      },
      revokeObjectURL(url) { revoked.push(url); },
    },
  });
  vm.runInContext(bridge, context);
  const player = new context.McGeeStreamPlayer((...values) => progress.push(values));
  t.after(() => player.stop());
  return { player, audio: audios[0], mediaSources, urls, revoked, progress };
}

test("streaming playback reports the playing event before the provider finishes", async (t) => {
  const { player, audio, mediaSources, progress } = browser(t);
  let started = false;
  const start = player.start().then((timestamp) => { started = true; return timestamp; });
  const media = mediaSources[0];
  media.open();
  const append = player.append(Uint8Array.of(0xff, 0xfb));
  await nextTurn();
  media.buffer.finishAppend();
  await append;
  assert.equal(started, false, "receiving bytes is not actual playback");
  audio.dispatchEvent(new Event("playing"));
  assert.equal(typeof await start, "number");
  assert.equal(media.endCalls, 0, "playback begins before finish/endOfStream");
  assert.equal(player.stopped, false);
  audio.currentTime = 0.25;
  audio.dispatchEvent(new Event("timeupdate"));
  assert.deepEqual(progress, [[0.25, -1]]);
});

test("arbitrary network chunks remain ordered and append waits for updateend", async (t) => {
  const { player, mediaSources } = browser(t);
  player.start();
  const media = mediaSources[0];
  media.open();
  const chunks = [Uint8Array.of(0xff), Uint8Array.of(0xfb, 0x01, 0x02), Uint8Array.of(0x03)];
  for (const chunk of chunks) {
    let settled = false;
    const append = player.append(chunk).then(() => { settled = true; });
    await nextTurn();
    assert.equal(settled, false, "append must await the asynchronous buffer event");
    media.buffer.finishAppend();
    await append;
  }
  assert.deepEqual(media.buffer.appends, chunks.map((chunk) => [...chunk]));
  assert.equal(media.buffer.mode, "sequence");
  await player.finish();
  assert.equal(media.endCalls, 1);
  assert.equal(player.receivedBytes, 5);
});

test("EOS keeps playback alive until ended and then releases the object URL", async (t) => {
  const { player, audio, mediaSources, revoked } = browser(t);
  const start = player.start();
  const media = mediaSources[0];
  media.open();
  const append = player.append(Uint8Array.of(1, 2));
  await nextTurn();
  media.buffer.finishAppend();
  await append;
  audio.dispatchEvent(new Event("playing"));
  await start;
  await player.finish();
  let completed = false;
  const completion = player.completed.then(() => { completed = true; });
  await nextTurn();
  assert.equal(completed, false);
  assert.deepEqual(revoked, []);
  audio.dispatchEvent(new Event("ended"));
  await completion;
  assert.equal(player.stopped, true);
  assert.deepEqual(revoked, ["blob:test-0"]);
  assert.equal(audio.src, undefined);
});

test("stop while sourceopen is pending settles startup and pending append", async (t) => {
  const { player, audio, revoked } = browser(t);
  const startRejected = assert.rejects(player.start(), /stopped/);
  const appendRejected = assert.rejects(player.append(Uint8Array.of(1)), /ended|stopped/);
  player.stop();
  await Promise.all([startRejected, appendRejected, player.completed]);
  await nextTurn();
  assert.equal(player.pendingWaits.size, 0);
  assert.equal(audio.pauseCalls, 1);
  assert.deepEqual(revoked, ["blob:test-0"]);
});

test("stop during an unfinished append rejects it and ignores late browser events", async (t) => {
  const { player, audio, mediaSources, progress } = browser(t);
  const start = player.start();
  mediaSources[0].open();
  audio.dispatchEvent(new Event("playing"));
  await start;
  const appendRejected = assert.rejects(player.append(Uint8Array.of(1)), /ended/);
  await nextTurn();
  player.stop();
  await Promise.all([appendRejected, player.completed]);
  mediaSources[0].buffer.finishAppend();
  audio.dispatchEvent(new Event("timeupdate"));
  audio.dispatchEvent(new Event("ended"));
  await nextTurn();
  assert.equal(player.pendingWaits.size, 0);
  assert.deepEqual(progress, []);
  assert.equal(audio.pauseCalls, 1);
});

test("provider failure after playback starts rejects completion and cancels append", async (t) => {
  const { player, audio, mediaSources, revoked } = browser(t);
  const start = player.start();
  mediaSources[0].open();
  audio.dispatchEvent(new Event("playing"));
  await start;
  const completionRejected = assert.rejects(player.completed, /provider disconnected/);
  const appendRejected = assert.rejects(player.append(Uint8Array.of(1)), /ended/);
  await nextTurn();
  player.fail("provider disconnected");
  await Promise.all([completionRejected, appendRejected]);
  assert.equal(player.stopped, true);
  assert.equal(player.pendingWaits.size, 0);
  assert.deepEqual(revoked, ["blob:test-0"]);
});

test("unsupported MSE buffers bytes and only requests playback after finish", async (t) => {
  const { player, audio, mediaSources, urls } = browser(t, { streaming: false });
  let started = false;
  const start = player.start().then(() => { started = true; });
  await player.append(Uint8Array.of(1, 2));
  await player.append(Uint8Array.of(3, 4, 5));
  await nextTurn();
  assert.equal(audio.playCalls, 0);
  assert.equal(started, false);
  assert.equal(mediaSources.length, 0);
  assert.equal(urls.size, 0);
  await player.finish();
  assert.equal(audio.playCalls, 1);
  const blob = urls.get(audio.src);
  assert.equal(blob.type, "audio/mpeg");
  assert.deepEqual([...new Uint8Array(await blob.arrayBuffer())], [1, 2, 3, 4, 5]);
  assert.equal(started, false, "play() alone is not playback confirmation");
  audio.dispatchEvent(new Event("playing"));
  await start;
  audio.dispatchEvent(new Event("ended"));
  await player.completed;
});
