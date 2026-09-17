import assert from "node:assert/strict";
import { test } from "node:test";
import { handleSpeech } from "../netlify/functions/speech.mjs";

const payload = {
  text: "Ari opens the door.",
  reference_id: "3ad4d432023c47ee9e6c7805b973630a",
  format: "mp3",
  latency: "low",
  chunk_length: 100,
};

test("speech proxy authenticates with Fish and streams audio", async () => {
  let sent;
  const response = await handleSpeech(new Request("http://localhost/api/speech", {
    method: "POST", body: JSON.stringify(payload),
    headers: { "Content-Type": "application/json", Origin: "http://localhost:8766" },
  }), {
    apiKey: "test-secret",
    fetcher: async (url, init) => {
      sent = { url, init };
      return new Response(new Uint8Array([1, 2, 3]), { status: 200 });
    },
  });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("Access-Control-Allow-Origin"), "http://localhost:8766");
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), new Uint8Array([1, 2, 3]));
  assert.equal(sent.url, "https://api.fish.audio/v1/tts");
  assert.equal(sent.init.headers.Authorization, "Bearer test-secret");
  assert.equal(sent.init.headers.model, "s2.1-pro-free");
});

test("speech proxy rejects unapproved voices before contacting Fish", async () => {
  let called = false;
  const response = await handleSpeech(new Request("http://localhost/api/speech", {
    method: "POST", body: JSON.stringify({ ...payload, reference_id: "other" }),
  }), {
    apiKey: "test-secret",
    fetcher: async () => { called = true; throw Error("unexpected"); },
  });
  assert.equal(response.status, 400);
  assert.equal(called, false);
});

test("speech proxy reports free-tier access failure", async () => {
  const response = await handleSpeech(new Request("http://localhost/api/speech", {
    method: "POST", body: JSON.stringify(payload),
  }), {
    apiKey: "test-secret",
    fetcher: async () => new Response(null, { status: 402 }),
  });
  assert.equal(response.status, 402);
  assert.match((await response.json()).error, /s2\.1-pro-free.*free-tier access/);
});
