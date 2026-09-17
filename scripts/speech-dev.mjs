import { createServer } from "node:http";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { handleSpeech } from "../netlify/functions/speech.mjs";

export function startSpeechServer({ port = 8767, apiKey, fetcher } = {}) {
  const server = createServer(async (req, res) => {
    const url = `http://localhost:${port}${req.url}`;
    if (new URL(url).pathname !== "/api/speech") {
      res.writeHead(404).end();
      return;
    }
    const abort = new AbortController();
    try {
      res.on("close", () => {
        if (!res.writableFinished) {
          abort.abort();
          console.info("[MCGEE] Browser disconnected; canceled Fish request.");
        }
      });
      const request = new Request(url, {
        method: req.method,
        headers: req.headers,
        body: ["GET", "HEAD"].includes(req.method) ? undefined : Readable.toWeb(req),
        duplex: "half",
        signal: abort.signal,
      });
      const response = await handleSpeech(request, { apiKey, fetcher });
      res.writeHead(response.status, Object.fromEntries(response.headers));
      if (response.body) await pipeline(Readable.fromWeb(response.body), res);
      else res.end();
    } catch (error) {
      if (abort.signal.aborted) return;
      console.error("Local speech server failed", error);
      if (!res.headersSent) res.writeHead(500).end();
      else res.destroy(error);
    }
  });
  server.listen(port, "127.0.0.1");
  return server;
}
