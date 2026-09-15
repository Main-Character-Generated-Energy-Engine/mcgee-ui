import assert from "node:assert/strict";
import test from "node:test";
import { generateOpening, openingRequestBody, parseOpening } from "../netlify/functions/film_opening.mjs";
import { validateSpeechPayload } from "../netlify/functions/narrate_core.mjs";
import handler from "../netlify/functions/narrate.mjs";

const opening = {
  title: "Le poids des petites choses",
  director: "Bastien Valcour de Sève",
  narration: "Une vie ordinaire mérite parfois une attention extraordinaire.",
};

test("opening prompts share English creative instructions for every output language", () => {
  const names = { en: "English", fr: "French", es: "Spanish", it: "Italian", ca: "Catalan" };
  const defaultBody = openingRequestBody({});
  assert.equal(defaultBody.model, "openai/gpt-5.6-terra");
  assert.deepEqual(defaultBody.reasoning, { effort: "high" });
  assert.equal(defaultBody.max_output_tokens, 2400);
  assert.equal(defaultBody.input, "Create a new opening in English.");
  for (const [code, name] of Object.entries(names)) {
    const body = openingRequestBody({ language: code });
    assert.equal(body.instructions, defaultBody.instructions);
    assert.equal(body.input, `Create a new opening in ${name}.`);
    assert.match(body.instructions, /Compose the title and narration directly/);
    assert.match(body.instructions, /Do not translate an English draft/);
  }
});

test("requests fictional opening metadata before any camera data exists", async () => {
  let sent;
  const result = await generateOpening({ language: "fr" }, {
    openRouterApiKey: "test-secret",
    fetchImpl: async (url, options) => {
      assert.equal(url, "https://openrouter.ai/api/v1/responses");
      assert.equal(options.headers.Authorization, "Bearer test-secret");
      sent = JSON.parse(options.body);
      return Response.json({ output: [{ content: [{ type: "output_text", text: JSON.stringify(opening) }] }] });
    },
  });
  assert.deepEqual(result, opening);
  assert.equal(sent.input, "Create a new opening in French.");
  assert.equal(sent.store, false);
  assert.equal(JSON.stringify(sent).includes("input_image"), false);
  assert.match(sent.instructions, /NO camera image/);
  assert.match(sent.instructions, /Do not read the title or director credit aloud/);
  assert.throws(() => openingRequestBody({ language: "de" }));
  assert.throws(() => openingRequestBody({ language: "toString" }));
  assert.throws(() => openingRequestBody({ language: ["en"] }));
});

test("rejects failed, truncated, and malformed opening responses", async () => {
  for (const body of [
    { output_text: "not JSON" },
    { output_text: JSON.stringify({ ...opening, title: "" }) },
    { output_text: JSON.stringify({ ...opening, narration: "x".repeat(901) }) },
    { status: "incomplete", output_text: JSON.stringify(opening) },
    { error: { message: "Failed" }, output_text: JSON.stringify(opening) },
  ]) {
    await assert.rejects(generateOpening({ language: "en" }, {
      openRouterApiKey: "test-secret",
      fetchImpl: async () => Response.json(body),
    }));
  }
  await assert.rejects(generateOpening({ language: "en" }, {
    openRouterApiKey: "test-secret",
    fetchImpl: async () => new Response("Provider unavailable", { status: 503 }),
  }), /HTTP 503/);
});

test("opening narration fits the speech endpoint's bounded payload", () => {
  const longOpening = parseOpening({ ...opening, narration: "A".repeat(900) });
  assert.equal(validateSpeechPayload({ text: longOpening.narration, voice: "jade", language: "fr" }).text.length, 900);
  assert.throws(() => validateSpeechPayload({ text: "A".repeat(901), voice: "jade" }));
  assert.throws(() => parseOpening({ ...opening, director: null }));
});

test("opening route returns JSON credits without waiting for speech or requiring a capture", async () => {
  const previousFetch = globalThis.fetch;
  const previousKey = process.env.OPENROUTER_API_KEY;
  let calls = 0;
  try {
    process.env.OPENROUTER_API_KEY = "server-test-key";
    globalThis.fetch = async () => {
      calls++;
      return Response.json({ output_text: JSON.stringify(opening) });
    };
    const response = await handler(new Request("https://example.test/api/narrate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ kind: "opening", language: "fr" }),
    }));
    assert.equal(response.status, 200);
    assert.match(response.headers.get("content-type"), /application\/json/);
    assert.equal(response.headers.get("cache-control"), "no-store");
    assert.deepEqual(await response.json(), opening);
    assert.equal(calls, 1);
  } finally {
    globalThis.fetch = previousFetch;
    if (previousKey === undefined) delete process.env.OPENROUTER_API_KEY;
    else process.env.OPENROUTER_API_KEY = previousKey;
  }
});
