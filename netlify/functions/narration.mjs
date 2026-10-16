const maximumBodyBytes = 2 * 1024 * 1024;

export async function handleNarration(request, { apiKey = process.env.OPENAI_API_KEY, fetcher = fetch } = {}) {
  const origin = request.headers.get("origin");
  const cors = origin && /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/.test(origin)
    ? { "Access-Control-Allow-Origin": origin, Vary: "Origin" } : {};
  const headers = { ...cors, "Cache-Control": "no-store" };
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: {
    ...headers, "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  } });
  if (request.method !== "POST") return Response.json({ error: "Method not allowed." }, { status: 405, headers });
  if (!apiKey) return Response.json({ error: "Narration is not configured." }, { status: 503, headers });

  let body;
  try {
    if (Number(request.headers.get("content-length")) > maximumBodyBytes) throw new Error();
    const reader = request.body?.getReader();
    if (!reader) throw new Error();
    const chunks = [];
    let size = 0;
    try {
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > maximumBodyBytes) { await reader.cancel(); throw new Error(); }
        chunks.push(value);
      }
    } finally { reader.releaseLock(); }
    body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    const allowed = new Set(["model", "instructions", "input", "reasoning", "max_output_tokens", "store", "text", "stream"]);
    if (!body || Object.keys(body).some((key) => !allowed.has(key)) ||
        body.model !== "gpt-5.6-terra" || typeof body.instructions !== "string" ||
        !(typeof body.input === "string" || Array.isArray(body.input)) ||
        body.store !== false || !Number.isInteger(body.max_output_tokens) ||
        body.max_output_tokens < 1 || body.max_output_tokens > 1200 ||
        (body.stream !== undefined && typeof body.stream !== "boolean") ||
        JSON.stringify(body.reasoning) !== '{"effort":"medium"}') throw new Error();
  } catch {
    return Response.json({ error: "Invalid narration request." }, { status: 400, headers });
  }
  try {
    const upstream = await fetcher("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify(body), signal: request.signal,
    });
    if (!upstream.ok || !upstream.body) {
      let error = `Narration provider returned HTTP ${upstream.status}.`;
      if (upstream.status === 429) {
        const details = await upstream.json().catch(() => null);
        if (details?.error?.type === "insufficient_quota" ||
            ["insufficient_quota", "credit_balance_exhausted"].includes(details?.error?.code)) {
          error = "OpenAI API credits are exhausted. Add credits to the server's OpenAI project.";
        }
      }
      return Response.json({ error }, { status: upstream.status === 429 ? 429 : 502, headers });
    }
    return new Response(upstream.body, { headers: {
      ...headers, "Content-Type": body.stream ? "text/event-stream" : "application/json",
    } });
  } catch {
    return Response.json({ error: "Narration provider is unavailable." }, { status: 502, headers });
  }
}

export default handleNarration;
export const config = {
  path: "/api/narration/responses",
  rateLimit: { windowSize: 60, windowLimit: 30, aggregateBy: ["ip"] },
};
