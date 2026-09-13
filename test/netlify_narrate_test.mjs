import assert from "node:assert/strict";
import test from "node:test";

import {
  decodeSse,
  openRouterNarrationBody,
  renderSpeech,
  validateSpeechPayload,
  validatePayload,
} from "../netlify/functions/narrate_core.mjs";

test("validates server-side startup speech requests", () => {
  const payload = validateSpeechPayload({
    text: "C'est l'heure de passer en mode personnage principal.",
    voice: "morgan-freeman",
    language: "fr",
  });
  assert.equal(payload.languageCode, "fr");
  assert.match(payload.text, /personnage principal/);
  assert.throws(() => validateSpeechPayload({ ...payload, text: "" }));
});

test("synthesizes startup speech without a client provider key", async () => {
  let providerAuthorization;
  const payload = validateSpeechPayload({
    text: "The hour has arrived.",
    voice: "jade",
    language: "en",
  });
  const result = await renderSpeech(payload, {
    openRouterApiKey: "server-secret",
    fetchImpl: async (_url, options) => {
      providerAuthorization = options.headers.Authorization;
      return new Response(Uint8Array.from([0x49, 0x44, 0x33]));
    },
  });

  assert.equal(providerAuthorization, "Bearer server-secret");
  assert.deepEqual([...result.audio], [0x49, 0x44, 0x33]);
  assert.equal(result.ttsProvider, "openrouter");
});

test("validates and bounds the narration request", () => {
  const payload = validatePayload({
    prompt: "Continue the tiny documentary.",
    voice: "morgan-freeman",
    language: "fr",
    capture: {
      id: "capture-1",
      capturedAt: "2026-09-13T12:00:00.000Z",
      mediaType: "image/jpeg",
      bytesBase64: Buffer.from([1, 2, 3]).toString("base64"),
    },
  });
  assert.equal(payload.voice.fishReference, "3ad4d432023c47ee9e6c7805b973630a");
  assert.equal(payload.languageCode, "fr");
  assert.match(payload.languageInstruction, /français/);
  assert.deepEqual([...payload.capture.image], [1, 2, 3]);
  assert.throws(() => validatePayload({ ...payload, voice: "arbitrary" }));
  assert.throws(() => validatePayload({ ...payload, language: "de" }));
});

test("builds a latency-ranked low-detail multimodal request", () => {
  const payload = validatePayload({
    prompt: "Continue the tiny documentary.",
    voice: "jade",
    language: "ca",
    capture: {
      capturedAt: "2026-09-13T12:00:00.000Z",
      mediaType: "image/jpeg",
      bytesBase64: Buffer.from([1, 2, 3]).toString("base64"),
    },
  });
  const body = openRouterNarrationBody(payload);
  assert.deepEqual(body.provider, { sort: "latency" });
  assert.equal(body.stream, true);
  assert.match(body.instructions, /exclusivament en català/);
  assert.match(body.instructions, /visible subject's invented thoughts/);
  assert.match(body.instructions, /exclusively in the third person/);
  assert.match(body.instructions, /never use first- or/);
  assert.match(body.instructions, /inner monologue only as indirect narration/);
  assert.equal(body.input[0].content.at(-1).detail, "low");
  assert.match(body.input[0].content.at(-1).image_url, /^data:image\/jpeg;base64,/);
});

test("decodes fragmented and multiline SSE data", async () => {
  const encoder = new TextEncoder();
  const source = new ReadableStream({
    start(controller) {
      controller.enqueue(encoder.encode(': ping\n\ndata: {"type":"response.output_'));
      controller.enqueue(encoder.encode('text.delta",\ndata: "delta":"Hello"}\n\n'));
      controller.enqueue(encoder.encode("data: [DONE]\n\n"));
      controller.close();
    },
  });
  const events = [];
  for await (const event of decodeSse(source)) events.push(event);
  assert.deepEqual(events, [{ type: "response.output_text.delta", delta: "Hello" }]);
});
