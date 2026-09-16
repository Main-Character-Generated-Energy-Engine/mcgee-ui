import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import test from "node:test";
import { encode, decode } from "@msgpack/msgpack";
import handler from "../netlify/functions/narrate.mjs";
import {
  renderSpeechStream, renderNarrationStream, validateSpeechPayload, validatePayload,
} from "../netlify/functions/narrate_core.mjs";

const speech = (voice = "morgan-freeman") => validateSpeechPayload({
  text: "I remembered the afternoon Ari finally answered that message.", voice,
});

function fishSocket(onStop, { connect = true } = {}) {
  let instance;
  class FakeSocket extends EventEmitter {
    constructor() {
      super();
      instance = this;
      this.readyState = 0;
      if (connect) queueMicrotask(() => { this.readyState = 1; this.emit("open"); });
    }
    send(bytes) {
      if (decode(bytes).event === "stop") queueMicrotask(() => onStop(this));
    }
    event(value) { this.emit("message", Buffer.from(encode(value))); }
    close() { this.readyState = 3; this.emit("close"); }
    terminate() { this.close(); }
  }
  return { WebSocketImpl: FakeSocket, socket: () => instance };
}

const audioEvent = (bytes) => ({ event: "audio", audio: Uint8Array.from(bytes) });
const finishEvent = { event: "finish", reason: "stop" };

test("Fish returns first audio before synthesis finishes and preserves chunk order", async () => {
  const fake = fishSocket((socket) => socket.event(audioEvent([1, 2, 3])));
  const result = await renderSpeechStream(speech(), {
    ...fake, fishApiKey: "test-only", openRouterApiKey: "test-only",
    fetchImpl: () => { throw new Error("Fallback must not run."); },
  });
  assert.equal(result.ttsProvider, "fish-audio");
  const reader = result.audio.getReader();
  assert.deepEqual([...(await reader.read()).value], [1, 2, 3]);
  assert.equal(fake.socket().readyState, 1, "provider must still be synthesizing");
  fake.socket().event(audioEvent([4, 5]));
  fake.socket().event(finishEvent);
  assert.deepEqual([...(await reader.read()).value], [4, 5]);
  assert.equal((await reader.read()).done, true);
  assert.equal(fake.socket().readyState, 3);
});

test("canceling streamed audio closes the Fish provider connection", async () => {
  const fake = fishSocket((socket) => socket.event(audioEvent([1, 2, 3])));
  const result = await renderSpeechStream(speech(), { ...fake, fishApiKey: "test-only" });
  const reader = result.audio.getReader();
  await reader.read();
  await reader.cancel("Narrator changed.");
  assert.equal(fake.socket().readyState, 3);
});

test("Fish failure before first audio can fall back, and fallback is also streamed", async () => {
  const fake = fishSocket((socket) => socket.emit("error", new Error("Unavailable")));
  let providerController;
  let requests = 0;
  const result = await renderSpeechStream(speech(), {
    ...fake, fishApiKey: "test-only", openRouterApiKey: "test-only",
    fetchImpl: async () => {
      requests++;
      return new Response(new ReadableStream({ start(controller) {
        providerController = controller;
        controller.enqueue(Uint8Array.from([9]));
      } }));
    },
  });
  assert.equal(requests, 1);
  assert.equal(result.ttsProvider, "openrouter");
  assert.equal(fake.socket().readyState, 3);
  const reader = result.audio.getReader();
  assert.deepEqual([...(await reader.read()).value], [9]);
  providerController.enqueue(Uint8Array.from([8, 7]));
  providerController.close();
  assert.deepEqual([...(await reader.read()).value], [8, 7]);
  assert.equal((await reader.read()).done, true);
});

test("failure after first Fish audio errors the stream without splicing another provider", async () => {
  const fake = fishSocket((socket) => socket.event(audioEvent([1, 2, 3])));
  let fallbackCalled = false;
  const result = await renderSpeechStream(speech(), {
    ...fake, fishApiKey: "test-only", openRouterApiKey: "test-only",
    fetchImpl: () => { fallbackCalled = true; throw new Error("Unexpected fallback"); },
  });
  const reader = result.audio.getReader();
  await reader.read();
  fake.socket().emit("error", new Error("Provider disconnected"));
  await assert.rejects(reader.read(), /Provider disconnected/);
  assert.equal(fallbackCalled, false);
});

test("request cancellation while Fish connects closes the socket without fallback", async () => {
  const fake = fishSocket(() => {}, { connect: false });
  const cancellation = new AbortController();
  const pending = renderSpeechStream(speech(), {
    ...fake, fishApiKey: "test-only", signal: cancellation.signal,
    fetchImpl: () => { throw new Error("Cancellation must not start fallback."); },
  });
  cancellation.abort(new Error("User stopped playback"));
  await assert.rejects(pending, /User stopped playback/);
  assert.equal(fake.socket().readyState, 3);
});

test("Fish handshake timeout closes the socket and allows fallback", async () => {
  const fake = fishSocket(() => {}, { connect: false });
  const result = await renderSpeechStream(speech(), {
    ...fake, fishApiKey: "test-only", providerTimeoutMs: 10,
    fetchImpl: async () => new Response(Uint8Array.from([4])),
  });
  assert.equal(result.ttsProvider, "openrouter");
  assert.equal(fake.socket().readyState, 3);
  assert.deepEqual([...new Uint8Array(await new Response(result.audio).arrayBuffer())], [4]);
});

test("canceling fallback audio cancels its response body and fetch signal", async () => {
  let canceled = false;
  let providerSignal;
  const result = await renderSpeechStream(speech("jade"), {
    openRouterApiKey: "test-only",
    fetchImpl: async (_url, options) => {
      providerSignal = options.signal;
      return new Response(new ReadableStream({
        start(controller) { controller.enqueue(Uint8Array.from([1])); },
        cancel() { canceled = true; },
      }));
    },
  });
  const reader = result.audio.getReader();
  await reader.read();
  await reader.cancel();
  assert.equal(canceled, true);
  assert.equal(providerSignal.aborted, true);
});

test("live narration validates the complete state before sending any text to Fish", async () => {
  const fake = fishSocket((socket) => {
    socket.event(audioEvent([1]));
    socket.event(finishEvent);
  });
  const payload = validatePayload({
    prompt: "Continue.", voice: "morgan-freeman", characterName: "Ari",
    capture: { capturedAt: "2026-09-16T10:00:00Z", mediaType: "image/jpeg", bytesBase64: "AQID" },
  });
  await assert.rejects(renderNarrationStream(payload, {
    ...fake, fishApiKey: "test-only", openRouterApiKey: "test-only",
    fetchImpl: async () => new Response('data: {"type":"response.output_text.delta","delta":"{invalid"}\n\ndata: [DONE]\n\n'),
  }), /malformed narration state/);
  assert.equal(fake.socket(), undefined);
});

test("HTTP handler exposes narration headers while the provider is still producing audio", async () => {
  const originalFetch = globalThis.fetch;
  const originalKey = process.env.OPENROUTER_API_KEY;
  process.env.OPENROUTER_API_KEY = "test-only";
  let providerController;
  globalThis.fetch = async () => new Response(new ReadableStream({
    start(controller) {
      providerController = controller;
      controller.enqueue(Uint8Array.from([0x49, 0x44, 0x33]));
    },
  }));
  try {
    const response = await handler(new Request("https://example.com/api/narrate", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ kind: "speech", voice: "jade", text: "The incident is unfolding now." }),
    }));
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("Content-Type"), "audio/mpeg");
    assert.equal(response.headers.get("X-Narration-Revision"), "narration-stream-v2");
    assert.equal(Buffer.from(response.headers.get("X-Narration-Text"), "base64url").toString(), "The incident is unfolding now.");
    assert.match(response.headers.get("Server-Timing"), /first-audio;dur=/);
    assert.equal(response.headers.has("Content-Length"), false);
    const reader = response.body.getReader();
    assert.deepEqual([...(await reader.read()).value], [0x49, 0x44, 0x33]);
    providerController.close();
    assert.equal((await reader.read()).done, true);
  } finally {
    globalThis.fetch = originalFetch;
    if (originalKey == null) delete process.env.OPENROUTER_API_KEY;
    else process.env.OPENROUTER_API_KEY = originalKey;
  }
});

test("Fish synthesis timeout after first audio terminates stream without fallback", async () => {
  const fake = fishSocket((socket) => socket.event(audioEvent([1])));
  let fallbackCalled = false;
  const result = await renderSpeechStream(speech(), {
    ...fake, fishApiKey: "test-only", providerTimeoutMs: 10,
    fetchImpl: () => { fallbackCalled = true; throw new Error("Unexpected fallback"); },
  });
  const reader = result.audio.getReader();
  await reader.read();
  await assert.rejects(reader.read(), /timed out/);
  assert.equal(fake.socket().readyState, 3);
  assert.equal(fallbackCalled, false);
});

test("an empty fallback response fails before committing an audio response", async () => {
  await assert.rejects(renderSpeechStream(speech("jade"), {
    openRouterApiKey: "test-only", fetchImpl: async () => new Response(new Uint8Array()),
  }), /empty audio/);
});

test("local development CORS permits IPv4 and IPv6 loopback only", async () => {
  for (const origin of ["http://localhost:8888", "http://127.0.0.1:8888", "http://[::1]:8888"]) {
    const response = await handler(new Request("https://example.com/api/narrate", {
      method: "OPTIONS", headers: { origin },
    }));
    assert.equal(response.status, 204);
    assert.equal(response.headers.get("Access-Control-Allow-Origin"), origin);
  }
  for (const origin of ["http://[::2]:8888", "http://localhost.attacker.test:8888", "https://attacker.test"]) {
    const response = await handler(new Request("https://example.com/api/narrate", {
      method: "OPTIONS", headers: { origin },
    }));
    assert.equal(response.headers.has("Access-Control-Allow-Origin"), false);
  }
});
