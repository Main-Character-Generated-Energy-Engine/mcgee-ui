import assert from "node:assert/strict";
import { test } from "node:test";
import { once } from "node:events";
import { handleNarration } from "../netlify/functions/narration.mjs";
import { startSpeechServer } from "../scripts/speech-dev.mjs";

const payload = { model: "gpt-5.6-terra", instructions: "Narrate the scene.",
  input: "Create an opening.", reasoning: { effort: "medium" },
  max_output_tokens: 1200, store: false };
const request = (body = payload, headers = {}) => new Request("https://example.test/api/narration/responses", {
  method: "POST", headers: { "Content-Type": "application/json", ...headers }, body: JSON.stringify(body),
});

test("relay supplies only the server key and preserves the Responses contract", async () => {
  const response = await handleNarration(request(payload, { Authorization: "Bearer browser-value" }), {
    apiKey: "server-secret", fetcher: async (url, init) => {
      assert.equal(url, "https://api.openai.com/v1/responses");
      assert.equal(init.headers.Authorization, "Bearer server-secret");
      assert.deepEqual(JSON.parse(init.body), payload);
      return Response.json({ output_text: "An opening." });
    },
  });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(await response.json(), { output_text: "An opening." });
});

test("relay forwards SSE before upstream completes and propagates cancellation", async () => {
  let controller;
  let canceled = false;
  const response = await handleNarration(request({ ...payload, stream: true }), {
    apiKey: "secret", fetcher: async () => new Response(new ReadableStream({
      start(value) { controller = value; value.enqueue(new TextEncoder().encode('data: {"delta":"Hello"}\n\n')); },
      cancel() { canceled = true; },
    })),
  });
  assert.equal(response.headers.get("content-type"), "text/event-stream");
  const reader = response.body.getReader();
  assert.match(new TextDecoder().decode((await reader.read()).value), /Hello/);
  assert.ok(controller);
  await reader.cancel();
  assert.equal(canceled, true);
});

test("invalid requests cannot select other models, tools, token limits or persistence", async () => {
  for (const body of [null, { ...payload, model: "another-model" }, { ...payload, tools: [] },
    { ...payload, max_output_tokens: 1201 }, { ...payload, store: true },
    { ...payload, input: null }, { ...payload, stream: "true" }]) {
    const response = await handleNarration(request(body), {
      apiKey: "secret", fetcher: () => assert.fail("must not call upstream"),
    });
    assert.equal(response.status, 400);
  }
  const oversized = request({ ...payload, input: "x".repeat(2 * 1024 * 1024) });
  assert.equal((await handleNarration(oversized, { apiKey: "secret" })).status, 400);
});

test("relay handles preflight, missing credentials, methods and sanitized provider errors", async () => {
  const preflight = await handleNarration(new Request("https://example.test", {
    method: "OPTIONS", headers: { Origin: "http://localhost:8770" },
  }));
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers.get("access-control-allow-origin"), "http://localhost:8770");
  assert.equal((await handleNarration(new Request("https://example.test"))).status, 405);
  assert.equal((await handleNarration(request(), { apiKey: "" })).status, 503);
  for (const status of [401, 429, 500]) {
    const response = await handleNarration(request(), { apiKey: "secret",
      fetcher: async () => new Response("secret provider details", { status }),
    });
    assert.equal(response.status, status === 429 ? 429 : 502);
    assert.doesNotMatch(await response.text(), /secret/);
  }
  const response = await handleNarration(request(), { apiKey: "secret", fetcher: () => { throw Error("secret"); } });
  assert.equal(response.status, 502);
  assert.doesNotMatch(await response.text(), /secret/);
});

test("exhausted API credits produce an actionable error without provider details", async () => {
  const response = await handleNarration(request(), { apiKey: "secret", fetcher: async () =>
    Response.json({ error: { code: "credit_balance_exhausted", type: "insufficient_quota", message: "secret details" } }, { status: 429 }),
  });
  assert.equal(response.status, 429);
  const body = await response.json();
  assert.match(body.error, /Add credits/);
  assert.doesNotMatch(body.error, /secret/);
});

test("local narration route uses the same authenticated handler without browser authorization", async () => {
  const server = startSpeechServer({ port: 0, openAiApiKey: "local-secret", fetcher: async (url, init) => {
    assert.equal(url, "https://api.openai.com/v1/responses");
    assert.equal(init.headers.Authorization, "Bearer local-secret");
    return Response.json({ output_text: "Ready." });
  } });
  try {
    await once(server, "listening");
    const response = await fetch(`http://127.0.0.1:${server.address().port}/api/narration/responses`, {
      method: "POST", body: JSON.stringify(payload), headers: { "Content-Type": "application/json" },
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { output_text: "Ready." });
  } finally { server.closeAllConnections(); server.close(); }
});
