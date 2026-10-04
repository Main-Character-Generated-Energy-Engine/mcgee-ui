import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const script = await readFile(new URL("../web/background_music.js", import.meta.url), "utf8");

function browser({ webAudio = true } = {}) {
  const audios = [];
  const timers = [];
  class Audio {
    constructor() {
      this.dataset = {};
      this.playCalls = 0;
      this.paused = true;
      this.currentTime = 0;
      this.volume = 1;
      audios.push(this);
    }
    play() { this.playCalls++; this.paused = false; return Promise.resolve(); }
    pause() { this.paused = true; }
    removeAttribute(name) { delete this[name]; }
    load() {}
  }
  class AudioContext {
    constructor() {
      this.currentTime = 0;
      this.destination = {};
      this.resumeCalls = 0;
    }
    resume() { this.resumeCalls++; return Promise.resolve(); }
    createGain() {
      const gain = {
        value: 0,
        targets: [],
        cancelScheduledValues() {},
        setValueAtTime(value) { this.value = value; },
        setTargetAtTime(target) { this.targets.push(target); this.value = target; },
      };
      return { gain, connect() {} };
    }
    createMediaElementSource(audio) {
      return { audio, connected: false, connect() { this.connected = true; }, disconnect() { this.connected = false; } };
    }
  }
  const context = {
    Audio,
    navigator: {},
    console,
    setTimeout: (callback) => { timers.push(callback); return timers.length; },
    clearTimeout: () => {},
    ...(webAudio ? { AudioContext } : {}),
  };
  context.globalThis = context;
  vm.runInNewContext(script, context);
  return { music: context.McGeeMusic, audios, timers, context };
}

test("streams a looping track through the gain node once unlocked", () => {
  const { music, audios } = browser();
  music.unlock();
  music.load("assets/lib/assets/music/danse-morialta.mp3");
  assert.equal(audios.length, 1);
  assert.equal(audios[0].loop, true);
  assert.equal(audios[0].preload, "auto");
  assert.equal(music.source.connected, true);

  // Loading the same track again keeps the download in progress.
  music.load("assets/lib/assets/music/danse-morialta.mp3");
  assert.equal(audios.length, 1);
});

test("connects a track that loaded before the gesture unlocked audio", () => {
  const { music } = browser();
  music.load("track.mp3");
  assert.equal(music.source, null);
  music.unlock();
  assert.equal(music.source.connected, true);
});

test("fades in, ducks under narration, and recovers", () => {
  const { music, audios } = browser();
  music.unlock();
  music.load("track.mp3");
  music.play();
  assert.equal(audios[0].playCalls, 1);
  assert.equal(music.state().gain, 0.32);

  music.duck(true);
  assert.equal(music.state().gain, 0.11);
  music.duck(false);
  assert.equal(music.state().gain, 0.32);

  // Playing again does not restart the track.
  music.play();
  assert.equal(audios[0].playCalls, 1);
});

test("fades out on stop, then pauses and rewinds", () => {
  const { music, audios, timers } = browser();
  music.unlock();
  music.load("track.mp3");
  music.play();
  music.duck(true);
  audios[0].currentTime = 42;

  music.stop();
  assert.equal(music.state().gain, 0);
  assert.equal(music.state().ducked, false);
  assert.equal(audios[0].paused, false);
  timers.at(-1)();
  assert.equal(audios[0].paused, true);
  assert.equal(audios[0].currentTime, 0);
});

test("replaces the previous track when a new one loads", () => {
  const { music, audios } = browser();
  music.unlock();
  music.load("one.mp3");
  const first = music.source;
  music.load("two.mp3");
  assert.equal(first.connected, false);
  assert.equal(audios[0].src, undefined);
  assert.equal(music.state().url, "two.mp3");
});

test("falls back to element volume without Web Audio", () => {
  const { music, audios } = browser({ webAudio: false });
  music.unlock();
  music.load("track.mp3");
  music.play();
  assert.equal(audios[0].volume, 0.32);
  music.duck(true);
  assert.equal(audios[0].volume, 0.11);
});
