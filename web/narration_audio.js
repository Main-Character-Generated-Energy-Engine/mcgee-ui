// A single MP3 stream, fed by Flutter as fetch() delivers bytes. MSE handles
// arbitrary network chunk boundaries; each chunk is not a separate audio file.
globalThis.McGeeStreamPlayer = class McGeeStreamPlayer {
  constructor(onProgress) {
    this.audio = new Audio();
    this.audio.preload = "auto";
    this.onProgress = onProgress;
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
      this.audio.play().catch((error) => this.fail(error.message));
    }
    return this.started;
  }

  checkActive() {
    if (this.stopped) throw new Error("Narration playback was stopped.");
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
      this.audio.play().catch((error) => this.fail(error.message));
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
