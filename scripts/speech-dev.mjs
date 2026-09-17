import { createServer } from "node:http";
import { Readable } from "node:stream";
import { handleSpeech } from "../netlify/functions/speech.mjs";

export function startSpeechServer({ port = 8767, apiKey } = {}) {
  const server = createServer(async (req, res) => {
    const url = `http://localhost:${port}${req.url}`;
    if (new URL(url).pathname !== "/api/speech") {
      res.writeHead(404).end();
      return;
    }
    try {
      const request = new Request(url, {
        method: req.method,
        headers: req.headers,
        body: ["GET", "HEAD"].includes(req.method) ? undefined : Readable.toWeb(req),
        duplex: "half",
      });
      const response = await handleSpeech(request, { apiKey });
      res.writeHead(response.status, Object.fromEntries(response.headers));
      if (response.body) Readable.fromWeb(response.body).pipe(res);
      else res.end();
    } catch (error) {
      console.error("Local speech server failed", error);
      if (!res.headersSent) res.writeHead(500).end();
      else res.destroy(error);
    }
  });
  server.listen(port, "127.0.0.1");
  return server;
}
