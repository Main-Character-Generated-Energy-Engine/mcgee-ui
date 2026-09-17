import assert from "node:assert/strict";
import { request as httpRequest } from "node:http";
import { once } from "node:events";
import { test } from "node:test";
import { startSpeechServer } from "../scripts/speech-dev.mjs";

const payload = JSON.stringify({
  text: "Ari opens the door.",
  reference_id: "3ad4d432023c47ee9e6c7805b973630a",
  format: "mp3",
  latency: "low",
  chunk_length: 100,
});

test("browser disconnect cancels Fish stream without crashing the local relay", async () => {
  let cancelFish;
  const fishCanceled = new Promise((resolve) => { cancelFish = resolve; });
  let calls = 0;
  const server = startSpeechServer({ port: 0, apiKey: "test-secret", fetcher: async () => {
    calls++;
    if (calls > 1) return new Response(new Uint8Array([4, 5, 6]));
    return new Response(new ReadableStream({
      start(controller) { controller.enqueue(new Uint8Array([1, 2, 3])); },
      cancel() { cancelFish(); },
    }));
  } });

  try {
    await once(server, "listening");
    const url = `http://127.0.0.1:${server.address().port}/api/speech`;
    await new Promise((resolve, reject) => {
      const req = httpRequest(url, { method: "POST", headers: {
        "Content-Type": "application/json", "Content-Length": Buffer.byteLength(payload),
      } }, (res) => {
        res.once("data", () => req.destroy());
        res.once("close", resolve);
        res.once("error", (error) => { if (error.code !== "ECONNRESET") reject(error); });
      });
      req.once("error", (error) => { if (error.code !== "ECONNRESET") reject(error); });
      req.end(payload);
    });
    await fishCanceled;

    const response = await fetch(url, { method: "POST", body: payload });
    assert.equal(response.status, 200);
    assert.deepEqual(new Uint8Array(await response.arrayBuffer()), new Uint8Array([4, 5, 6]));
    assert.equal(calls, 2);
  } finally {
    server.closeAllConnections();
    server.close();
  }
});
