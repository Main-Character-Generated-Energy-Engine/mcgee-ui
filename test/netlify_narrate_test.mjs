import assert from "node:assert/strict";
import test from "node:test";
import { narrationLanguageInstruction, narrationLanguageName } from "../netlify/functions/narration_language.mjs";

import {
  decodeSse,
  openRouterNarrationBody,
  parseNarrationEnvelope,
  renderNarration,
  renderSpeech,
  validateSpeechPayload,
  validatePayload,
} from "../netlify/functions/narrate_core.mjs";

test("all output languages use the same English live instructions", () => {
  const instructions = [];
  for (const code of ["en", "fr", "es", "it", "ca"]) {
    const payload = validatePayload({
      prompt: "Continue from: Els dits reposen sobre el teclat.",
      voice: "jade",
      language: code,
      characterName: "Ari",
      story: { summary: "", recentNarrations: [], openThread: "" },
      capture: {
        capturedAt: "2026-09-13T12:00:00.000Z",
        mediaType: "image/jpeg",
        bytesBase64: Buffer.from([1, 2, 3]).toString("base64"),
      },
    });
    const body = openRouterNarrationBody(payload);
    assert.ok(body.instructions.includes(`only in ${narrationLanguageName(code)}`));
    assert.match(body.instructions, /do not translate an English draft/);
    assert.equal(body.input[0].content[1].text, payload.prompt);
    instructions.push(body.instructions.replace(narrationLanguageInstruction(code), ""));
  }
  assert.equal(new Set(instructions).size, 1);
  assert.equal(narrationLanguageName(), "English");
  assert.throws(() => narrationLanguageName("de"));
  assert.throws(() => narrationLanguageName("toString"));
});

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
    characterName: "Ari",
    story: {
      summary: "Ari began the great desk campaign.",
      recentNarrations: ["Ari studies the keyboard."],
      openThread: "Ari studies the keyboard.",
    },
    capture: {
      id: "capture-1",
      capturedAt: "2026-09-13T12:00:00.000Z",
      mediaType: "image/jpeg",
      bytesBase64: Buffer.from([1, 2, 3]).toString("base64"),
    },
  });
  assert.equal(payload.voice.fishReference, "3ad4d432023c47ee9e6c7805b973630a");
  assert.equal(payload.languageCode, "fr");
  assert.equal(payload.characterName, "Ari");
  assert.equal(payload.story.openThread, "Ari studies the keyboard.");
  assert.match(payload.languageInstruction, /only in French/);
  assert.deepEqual([...payload.capture.image], [1, 2, 3]);
  assert.throws(() => validatePayload({ ...payload, voice: "arbitrary" }));
  assert.throws(() => validatePayload({ ...payload, language: "de" }));
  assert.throws(() => validatePayload({ ...payload, characterName: "" }));
  assert.throws(() => validatePayload({
    ...payload,
    story: { ...payload.story, recentNarrations: Array(11).fill("Ari waits.") },
  }));
});

test("builds a latency-ranked low-detail multimodal request", () => {
  const payload = validatePayload({
    prompt: "Continue the tiny documentary.",
    voice: "jade",
    language: "ca",
    characterName: "Ari",
    story: { summary: "", recentNarrations: [], openThread: "" },
    capture: {
      capturedAt: "2026-09-13T12:00:00.000Z",
      mediaType: "image/jpeg",
      bytesBase64: Buffer.from([1, 2, 3]).toString("base64"),
    },
  });
  const body = openRouterNarrationBody(payload);
  assert.equal(body.model, "openai/gpt-5.6-terra");
  assert.deepEqual(body.reasoning, { effort: "high" });
  assert.equal(body.max_output_tokens, 2000);
  assert.deepEqual(body.provider, { sort: "latency" });
  assert.equal(body.stream, true);
  assert.equal(body.text.format.name, "continuous_narration");
  assert.equal(body.text.format.schema.properties.story_summary.maxLength, 1200);
  assert.equal(body.text.format.schema.properties.current_activity.maxLength, 240);
  assert.equal(body.text.format.schema.properties.open_thread.maxLength, 400);
  assert.match(body.instructions, /only in Catalan/);
  assert.match(body.instructions, /Describe the visible action first/);
  assert.match(body.instructions, /exclusively in the third person/);
  assert.match(body.instructions, /never use first- or/);
  assert.match(body.instructions, /inner monologue only as indirect narration/);
  assert.match(body.instructions, /The last spoken line is/);
  assert.match(body.instructions, /protagonist is named "Ari"/);
  assert.match(body.instructions, /Do not restart the premise/);
  assert.match(body.instructions, /Never invent unseen/);
  assert.match(body.input[0].content[0].text, /Explicit episode state/);
  assert.equal(body.input[0].content[1].text, payload.prompt);
  assert.equal(body.input[0].content.at(-1).detail, "low");
  assert.match(body.input[0].content.at(-1).image_url, /^data:image\/jpeg;base64,/);
});

test("parses and validates explicit evolving story state", () => {
  const parsed = parseNarrationEnvelope(JSON.stringify({
    narration: "Ari steadies the notebook, preserving the expedition's fragile momentum.",
    story_summary: "Ari has pursued order across a crowded desk.",
    current_activity: "organising the notebook",
    open_thread: "find the missing red page",
    recurring_elements: ["notebook", "red page"],
  }), "Ari");

  assert.equal(parsed.storyState.openThread, "find the missing red page");
  assert.deepEqual(parsed.storyState.recurringElements, ["notebook", "red page"]);
  const resolved = parseNarrationEnvelope(JSON.stringify({
    narration: "The notebook closes, leaving the little campaign complete for now.",
    story_summary: "Ari completed the notebook campaign.",
    current_activity: "",
    open_thread: "",
    recurring_elements: [],
  }), "Ari", {
    recentNarrations: ["Ari steadies the notebook.", "The last page receives its mark."],
  });
  assert.equal(resolved.storyState.currentActivity, "");
  assert.equal(resolved.storyState.openThread, "");
  assert.deepEqual(resolved.storyState.recurringElements, []);
  assert.throws(() => parseNarrationEnvelope(JSON.stringify({
    narration: "The notebook waits without its named protagonist.",
    story_summary: "A desk story.",
    current_activity: "waiting",
    open_thread: "find the page",
    recurring_elements: [],
  }), "Ari"), /omitted the protagonist name/);
});

test("renders only the spoken field and returns the updated story state", async () => {
  const payload = validatePayload({
    prompt: "Continue Ari's desk story.",
    voice: "jade",
    language: "en",
    characterName: "Ari",
    story: { summary: "", recentNarrations: [], openThread: "" },
    capture: {
      capturedAt: "2026-09-13T12:00:00.000Z",
      mediaType: "image/jpeg",
      bytesBase64: Buffer.from([1, 2, 3]).toString("base64"),
    },
  });
  const envelope = JSON.stringify({
    narration: "Ari steadies the notebook, carrying yesterday's tiny campaign into its decisive chapter.",
    story_summary: "Ari is organising the desk through a solemn notebook campaign.",
    current_activity: "organising the notebook",
    open_thread: "complete the notebook campaign",
    recurring_elements: ["notebook"],
  });
  const result = await renderNarration(payload, {
    openRouterApiKey: "server-secret",
    fetchImpl: async (url, options) => {
      if (url.includes("/responses")) {
        const event = JSON.stringify({
          type: "response.output_text.delta",
          delta: envelope,
        });
        return new Response(`data: ${event}\n\ndata: [DONE]\n\n`);
      }
      const speechBody = JSON.parse(options.body);
      assert.equal(
        speechBody.input,
        "Ari steadies the notebook, carrying yesterday's tiny campaign into its decisive chapter.",
      );
      assert.equal(speechBody.input.includes("story_summary"), false);
      return new Response(Uint8Array.from([0x49, 0x44, 0x33]));
    },
  });

  assert.equal(result.text.startsWith("Ari steadies"), true);
  assert.equal(result.storyState.openThread, "complete the notebook campaign");
  assert.deepEqual([...result.audio], [0x49, 0x44, 0x33]);
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
