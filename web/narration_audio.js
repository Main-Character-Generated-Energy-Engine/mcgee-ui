// A single MP3 stream, fed by Flutter as fetch() delivers bytes. MSE handles
// arbitrary network chunk boundaries; each chunk is not a separate audio file.
globalThis.McGeeStreamPlayer = class McGeeStreamPlayer {
  static getAudio() {
    return this.audio ??= new Audio();
  }

  // Run during the existing Continue/camera tap, before provider requests or
  // the permission prompt. A short silent WAV grants this element permission
  // to play later sources; muting it would not unlock audible playback.
  static unlock() {
    if (this.unlocked || this.priming || (this.active && !this.active.stopped)) return;
    if (globalThis.navigator?.userActivation?.isActive === false) return;
    const audio = this.getAudio();
    const bytes = new Uint8Array(204);
    const view = new DataView(bytes.buffer);
    const label = (offset, text) => {
      for (let i = 0; i < text.length; i++) bytes[offset + i] = text.charCodeAt(i);
    };
    label(0, "RIFF"); view.setUint32(4, 196, true);
    label(8, "WAVEfmt "); view.setUint32(16, 16, true);
    view.setUint16(20, 1, true); view.setUint16(22, 1, true);
    view.setUint32(24, 8000, true); view.setUint32(28, 16000, true);
    view.setUint16(32, 2, true); view.setUint16(34, 16, true);
    label(36, "data"); view.setUint32(40, 160, true);
    const url = URL.createObjectURL(new Blob([bytes], { type: "audio/wav" }));
    audio.src = url;
    this.priming = true;
    const release = () => {
      this.priming = false;
      // Never pause a narration that attached its source while priming.
      if (audio.src === url) audio.pause();
      URL.revokeObjectURL(url);
    };
    try {
      audio.play().then(() => {
        this.unlocked = true;
        release();
      }, release);
    } catch (_) {
      release();
    }
  }

  constructor(onProgress, onBlocked = () => {}) {
    // Safari grants playback permission per element. Reuse the element after
    // a successful user tap so later passages retain that permission.
    this.audio = McGeeStreamPlayer.getAudio();
    McGeeStreamPlayer.active = this;
    this.audio.preload = "auto";
    this.onProgress = onProgress;
    this.onBlocked = onBlocked;
    this.waitingForGesture = false;
    this.stopped = false;
    this.hasStarted = false;
    this.receivedBytes = 0;
    this.chunks = [];
    this.pendingWaits = new Set();
    this.started = new Promise((resolve, reject) => {
      this.resolveStarted = resolve;
      this.rejectStarted = reject;
    });
    this.completed = new Promise((resolve, reject) => {
      this.resolveCompleted = resolve;
      this.rejectCompleted = reject;
    });
    // The Dart engine only awaits completion after the first playing event.
    this.started.catch(() => {});
    this.completed.catch(() => {});
    this.listeners = [];
    this.listen(this.audio, "playing", () => {
      if (this.stopped || this.hasStarted) return;
      this.hasStarted = true;
      McGeeStreamPlayer.unlocked = true;
      this.waitingForGesture = false;
      clearTimeout(this.startTimeout);
      this.resolveStarted(Date.now());
    });
    this.listen(this.audio, "ended", () => {
      if (this.stopped) return;
      this.resolveCompleted();
      this.cleanup();
    });
    this.listen(this.audio, "error", () => this.fail(
      this.audio.error?.message || "The browser could not decode narration audio.",
    ));
    for (const event of ["timeupdate", "durationchange"]) {
      this.listen(this.audio, event, () => {
        if (!this.stopped) this.onProgress(
          this.audio.currentTime,
          Number.isFinite(this.audio.duration) ? this.audio.duration : -1,
        );
      });
    }
    this.streaming = typeof MediaSource !== "undefined" &&
      MediaSource.isTypeSupported("audio/mpeg");
    if (!this.streaming) {
      console.info("[MCGEE] MP3 streaming is unsupported in this browser; buffering this passage.");
    }
  }

  listen(target, name, callback) {
    target.addEventListener(name, callback);
    this.listeners.push(() => target.removeEventListener(name, callback));
  }

  // Waits are explicitly rejected on stop so cancellation never leaves append
  // or source-open work hanging after a voice switch.
  wait(target, event) {
    return new Promise((resolve, reject) => {
      const done = () => { remove(); resolve(); };
      const failed = () => { remove(); reject(new Error("Audio buffer failed.")); };
      const cancel = (error) => { remove(); reject(error); };
      const remove = () => {
        target.removeEventListener(event, done);
        target.removeEventListener("error", failed);
        this.pendingWaits.delete(cancel);
      };
      target.addEventListener(event, done, { once: true });
      target.addEventListener("error", failed, { once: true });
      this.pendingWaits.add(cancel);
    });
  }

  start() {
    this.startTimeout = setTimeout(() => this.fail("Narration playback did not start."), 20000);
    if (this.streaming) {
      this.media = new MediaSource();
      this.ready = this.wait(this.media, "sourceopen").then(() => {
        this.checkActive();
        this.buffer = this.media.addSourceBuffer("audio/mpeg");
        this.buffer.mode = "sequence";
      });
      this.ready.catch((error) => this.fail(error.message));
      this.url = URL.createObjectURL(this.media);
      this.audio.src = this.url;
      this.requestPlayback();
    }
    return this.started;
  }

  checkActive() {
    if (this.stopped) throw new Error("Narration playback was stopped.");
  }

  requestPlayback() {
    // Keep this call synchronous: resume() is called from the Play button's
    // tap, and an awaited operation here would lose Safari's user gesture.
    const rejected = (error) => {
      if (this.stopped) return;
      const message = `${error.name || "Error"}: ${error.message}`;
      if (error.name === "NotAllowedError") {
        clearTimeout(this.startTimeout);
        this.waitingForGesture = true;
        this.onBlocked(message);
      } else {
        this.fail(message);
      }
    };
    try {
      this.audio.play().catch(rejected);
    } catch (error) {
      rejected(error);
    }
  }

  resume() {
    if (this.stopped || !this.waitingForGesture) return;
    clearTimeout(this.startTimeout);
    this.startTimeout = setTimeout(() => this.fail("Narration playback did not start."), 20000);
    this.requestPlayback();
  }

  async append(bytes) {
    this.checkActive();
    if (!bytes.length) return;
    this.receivedBytes += bytes.length;
    if (!this.streaming) {
      this.chunks.push(bytes);
      return;
    }
    await this.ready;
    this.checkActive();
    const updated = this.wait(this.buffer, "updateend");
    // Observe rejection even if appendBuffer throws synchronously.
    updated.catch(() => {});
    try {
      this.buffer.appendBuffer(bytes);
      await updated;
    } catch (error) {
      this.fail(error.message);
      throw error;
    }
  }

  async finish() {
    this.checkActive();
    if (!this.receivedBytes) throw new Error("Narration returned no audio.");
    if (this.streaming) {
      await this.ready;
      this.checkActive();
      this.media.endOfStream();
    } else {
      this.url = URL.createObjectURL(new Blob(this.chunks, { type: "audio/mpeg" }));
      this.chunks = [];
      this.audio.src = this.url;
      this.requestPlayback();
    }
  }

  fail(message) {
    if (this.stopped) return;
    const error = new Error(message);
    this.rejectStarted(error);
    this.rejectCompleted(error);
    this.cleanup();
  }

  stop() {
    if (this.stopped) return;
    this.rejectStarted(new Error("Narration playback was stopped."));
    this.resolveCompleted();
    this.cleanup();
  }

  cleanup() {
    if (this.stopped) return;
    this.stopped = true;
    if (McGeeStreamPlayer.active === this) McGeeStreamPlayer.active = null;
    clearTimeout(this.startTimeout);
    for (const cancel of [...this.pendingWaits]) cancel(new Error("Narration playback ended."));
    for (const remove of this.listeners) remove();
    this.listeners = [];
    this.audio.pause();
    this.audio.removeAttribute("src");
    this.audio.load();
    if (this.url) URL.revokeObjectURL(this.url);
    this.chunks = [];
  }
};

// Capture the existing gesture before Flutter dispatches it through its event
// queue. Safari requires play() in that original DOM event, not a later task.
if (typeof document !== "undefined") {
  const unlock = (event) => {
    if (!event.isTrusted) return;
    if (event.type === "keydown" && event.key !== "Enter" && event.key !== " ") return;
    globalThis.McGeeStreamPlayer.unlock();
  };
  const gestureTarget = typeof window !== "undefined" ? window : document;
  for (const event of ["pointerup", "touchend", "keydown"]) {
    gestureTarget.addEventListener(event, unlock, { capture: true, passive: true });
  }
}
