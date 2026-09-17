import { createServer } from "node:http";
import { readFileSync } from "node:fs";
import { Readable } from "node:stream";
import { resolve } from "node:path";
import { handleSpeech } from "../netlify/functions/speech.mjs";

const mp3 = readFileSync(resolve("lib/assets/switch.mp3"));

export function startE2EServer({ port = 8767, fishDelayMs = 0 } = {}) {
  const state = { openings: 0, liveRequests: 0, speechRequests: 0, frameSamples: new Set() };
  const server = createServer(async (req, res) => {
    const url = new URL(req.url, `http://127.0.0.1:${port}`);
    const origin = req.headers.origin;
    const cors = origin && /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)
      ? { "Access-Control-Allow-Origin": origin, Vary: "Origin" } : {};
    if (req.method === "OPTIONS") {
      res.writeHead(204, { ...cors, "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Authorization, Content-Type" }).end();
      return;
    }
    if (url.pathname === "/__e2e/state") {
      res.writeHead(200, { "Content-Type": "application/json", ...cors }).end(JSON.stringify({
        openings: state.openings, liveRequests: state.liveRequests,
        speechRequests: state.speechRequests, distinctFrames: state.frameSamples.size,
      }));
      return;
    }
    if (url.pathname === "/api/speech" && req.method === "POST") {
      state.speechRequests++;
      const request = new Request(url, {
        method: "POST", headers: req.headers, body: Readable.toWeb(req), duplex: "half",
      });
      const response = await handleSpeech(request, {
        apiKey: "mock-fish-key",
        fetcher: async () => {
          if (fishDelayMs > 0) await new Promise((resolve) => setTimeout(resolve, fishDelayMs));
          return new Response(mp3, { status: 200 });
        },
      });
      res.writeHead(response.status, Object.fromEntries(response.headers));
      Readable.fromWeb(response.body).pipe(res);
      return;
    }
    if (url.pathname === "/openrouter/responses" && req.method === "POST") {
      let body;
      try {
        const chunks = [];
        for await (const chunk of req) chunks.push(chunk);
        body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
      } catch {
        res.writeHead(400, cors).end();
        return;
      }
      const isOpening = typeof body.input === "string";
      const name = (isOpening ? body.input : body.instructions)
        ?.match(/(?:protagonist name is|protagonist is named)\s+"([^"]+)"/i)?.[1] ?? "Alex";
      let output;
      if (isOpening) {
        state.openings++;
        output = { title: "The Missing Key", director: "Mira Vale",
          narration: `${name} had one ordinary job: find the missing key before the door closed for good. The clock kept moving, and every small clue seemed to point somewhere else. One clue remained, just out of reach.` };
      } else {
        state.liveRequests++;
        for (const item of body.input ?? []) {
          for (const part of item.content ?? []) {
            if (part.type === "input_image" && typeof part.image_url === "string") {
              state.frameSamples.add(part.image_url);
            }
          }
        }
        const useName = body.instructions?.includes("Use the supplied character name exactly once");
        const lead = useName ? `${name} studies` : "The search turns toward";
        output = { action: "speak",
          text: `${lead} a fresh clue in the frame, while the missing key keeps the little mystery alive.`,
          reason: "", motifs: [], canon_updates: [] };
      }
      res.writeHead(200, { ...cors, "Content-Type": "application/json" })
        .end(JSON.stringify({ output_text: JSON.stringify(output) }));
      return;
    }
    res.writeHead(404, cors).end();
  });
  server.listen(port, "127.0.0.1");
  return server;
}
