const voices = new Set([
  "3ad4d432023c47ee9e6c7805b973630a",
  "c39a76f685cf4f8fb41cd5d3d66b497d",
  "1e5902ed8ddf433b88a717444bb90510",
]);

export async function handleSpeech(request, { apiKey = process.env.FISH_AUDIO_API_KEY, fetcher = fetch } = {}) {
  const origin = request.headers.get("origin");
  const cors = origin && /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/.test(origin)
    ? { "Access-Control-Allow-Origin": origin, Vary: "Origin" }
    : {};
  const headers = { ...cors, "Cache-Control": "no-store" };
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: {
      ...headers,
      "Access-Control-Allow-Headers": "Content-Type",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
    } });
  }
  if (request.method !== "POST") return Response.json({ error: "Method not allowed." }, { status: 405, headers });
  if (!apiKey) return Response.json({ error: "Speech is not configured." }, { status: 503, headers });

  let body;
  try {
    if (Number(request.headers.get("content-length")) > 8192) throw new Error("Request too large.");
    body = await request.json();
    if (!body || typeof body.text !== "string" || !body.text.trim() || body.text.length > 2000 ||
        !voices.has(body.reference_id) || body.format !== "mp3" || body.latency !== "low" ||
        body.chunk_length !== 100) throw new Error("Invalid speech request.");
  } catch {
    return Response.json({ error: "Invalid speech request." }, { status: 400, headers });
  }

  try {
    const upstream = await fetcher("https://api.fish.audio/v1/tts", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        model: "s2.1-pro-free",
      },
      body: JSON.stringify(body),
      signal: request.signal,
    });
    if (!upstream.ok || !upstream.body) {
      const rejected = upstream.status === 402;
      return Response.json({
        error: rejected
          ? "Fish Audio rejected s2.1-pro-free (HTTP 402). Check free-tier access with Fish Audio."
          : `Speech provider returned HTTP ${upstream.status}.`,
      }, { status: rejected ? 402 : 502, headers });
    }
    return new Response(upstream.body, {
      headers: { ...headers, "Content-Type": "audio/mpeg" },
    });
  } catch (error) {
    console.error("Speech request failed", error);
    return Response.json({ error: "Speech provider is unavailable." }, { status: 502, headers });
  }
}

export default handleSpeech;
export const config = {
  path: "/api/speech",
  rateLimit: { windowSize: 60, windowLimit: 30, aggregateBy: ["ip"] },
};
