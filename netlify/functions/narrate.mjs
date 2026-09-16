import {
  renderNarrationStream,
  renderSpeechStream,
  validatePayload,
  validateSpeechPayload,
} from "./narrate_core.mjs";
import { generateOpening } from "./film_opening.mjs";

export default async function handler(request) {
  const cors = corsHeaders(request.headers.get("origin"));
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (request.method !== "POST") return jsonError(405, "Method not allowed.", cors);

  try {
    const body = await request.json();
    const options = {
      openRouterApiKey: process.env.OPENROUTER_API_KEY,
      fishApiKey: process.env.FISH_AUDIO_API_KEY,
      signal: request.signal,
    };
    if (!options.openRouterApiKey) {
      throw new Error("OpenRouter is not configured on this deployment.");
    }
    const profileHeaders = {
      "X-Narration-Revision": "narration-stream-v2",
      "X-Narration-Profile": body?.voice ?? "morgan-freeman",
    };
    if (body?.kind === "opening") {
      return Response.json(await generateOpening(body, options), {
        headers: { ...cors, ...profileHeaders, "Cache-Control": "no-store" },
      });
    }
    const result = body?.kind === "speech"
      ? await renderSpeechStream(validateSpeechPayload(body), options)
      : await renderNarrationStream(validatePayload(body), options);
    return new Response(result.audio, {
      status: 200,
      headers: {
        ...cors,
        ...profileHeaders,
        "Cache-Control": "no-store",
        "Content-Type": "audio/mpeg",
        "X-Narration-Text": Buffer.from(result.text).toString("base64url"),
        ...(result.storyState ? {
          "X-Story-State": Buffer.from(JSON.stringify(result.storyState)).toString("base64url"),
        } : {}),
        "X-TTS-Provider": result.ttsProvider,
        "Server-Timing": `first-token;dur=${result.timings.firstToken.toFixed(1)}, first-audio;dur=${result.timings.firstAudio.toFixed(1)}`,
      },
    });
  } catch (error) {
    console.error("Narration request failed", error);
    return jsonError(502, error instanceof Error ? error.message : "Narration failed.", cors);
  }
}

export const config = {
  path: "/api/narrate",
  rateLimit: {
    windowSize: 60,
    windowLimit: 30,
    aggregateBy: ["ip"],
  },
};

function corsHeaders(origin) {
  const allowed =
    origin &&
    (origin === "https://mcgee-narrator.netlify.app" ||
      /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/.test(origin));
  return {
    ...(allowed ? { "Access-Control-Allow-Origin": origin, Vary: "Origin" } : {}),
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Expose-Headers": "Server-Timing, X-Narration-Text, X-Story-State, X-TTS-Provider, X-Narration-Revision, X-Narration-Profile",
  };
}

function jsonError(status, message, headers) {
  return Response.json({ error: message }, { status, headers: { ...headers, "Cache-Control": "no-store" } });
}
