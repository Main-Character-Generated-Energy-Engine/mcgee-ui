// Background music: one looping track per session, streamed by an <audio>
// element and routed through a GainNode so fades and ducking work on iOS,
// where HTMLMediaElement.volume is read-only.
globalThis.McGeeMusic = new (class McGeeMusic {
  // Gain levels: the bed sits low, and drops further under the narrator.
  static FULL = 0.32;
  static DUCKED = 0.11;

  constructor() {
    this.context = null;
    this.gain = null;
    this.audio = null;
    this.source = null;
    this.ducked = false;
    this.playing = false;
  }

  // Call from a user gesture so the browser allows playback later.
  unlock() {
    try {
      if (navigator.audioSession) navigator.audioSession.type = "playback";
    } catch (_) {}
    const Context = globalThis.AudioContext || globalThis.webkitAudioContext;
    if (!Context) return;
    if (!this.context) {
      this.context = new Context();
      this.gain = this.context.createGain();
      this.gain.gain.value = 0;
      this.gain.connect(this.context.destination);
    }
    if (this.audio && !this.source) this.connect(this.audio);
    this.context.resume().catch(() => {});
  }

  // Starts downloading the track so it is ready by the time credits roll.
  load(url) {
    if (this.audio?.dataset.url === url) return;
    this.release();
    const audio = new Audio();
    audio.dataset.url = url;
    audio.loop = true;
    audio.preload = "auto";
    audio.crossOrigin = "anonymous";
    audio.src = url;
    this.audio = audio;
    if (this.context) this.connect(audio);
  }

  connect(audio) {
    this.source = this.context.createMediaElementSource(audio);
    this.source.connect(this.gain);
  }

  play() {
    if (!this.audio || this.playing) return;
    this.playing = true;
    this.context?.resume().catch(() => {});
    this.audio.play().catch((error) => {
      this.playing = false;
      console.info(`[MCGEE] Background music could not start: ${error.message}`);
    });
    this.ramp(this.level(), 2.5);
  }

  duck(ducked) {
    this.ducked = ducked;
    // Quick dip before speech, slow recovery after it.
    if (this.playing) this.ramp(this.level(), ducked ? 0.35 : 1.6);
  }

  stop(fadeSeconds = 2) {
    if (!this.playing) return;
    this.playing = false;
    this.ducked = false;
    const audio = this.audio;
    this.ramp(0, fadeSeconds);
    clearTimeout(this.pauseTimer);
    this.pauseTimer = setTimeout(() => {
      if (!this.playing && audio === this.audio) {
        audio.pause();
        audio.currentTime = 0;
      }
    }, fadeSeconds * 1000 + 100);
  }

  release() {
    clearTimeout(this.pauseTimer);
    this.playing = false;
    this.source?.disconnect();
    this.source = null;
    if (this.audio) {
      this.audio.pause();
      this.audio.removeAttribute("src");
      this.audio.load();
    }
    this.audio = null;
  }

  level() {
    return this.ducked ? McGeeMusic.DUCKED : McGeeMusic.FULL;
  }

  ramp(target, seconds) {
    if (!this.gain) {
      // No Web Audio: fall back to element volume where the browser allows it.
      if (this.audio) this.audio.volume = target;
      return;
    }
    const now = this.context.currentTime;
    const gain = this.gain.gain;
    gain.cancelScheduledValues(now);
    gain.setValueAtTime(gain.value, now);
    gain.setTargetAtTime(target, now, seconds / 3);
  }

  // Exposed for browser tests.
  state() {
    return {
      url: this.audio?.dataset.url ?? null,
      playing: this.playing,
      ducked: this.ducked,
      gain: this.gain?.gain.value ?? null,
    };
  }
})();
