import { decode, encode } from "@msgpack/msgpack";
import WebSocket from "ws";
import { narrationLanguageInstruction, narrationLanguageName } from "./narration_language.mjs";

const OPENROUTER_RESPONSES_URL = "https://openrouter.ai/api/v1/responses";
const OPENROUTER_SPEECH_URL = "https://openrouter.ai/api/v1/audio/speech";
const FISH_LIVE_URL = "wss://api.fish.audio/v1/tts/live";

const VOICES = Object.freeze({
  "morgan-freeman": {
    fishReference: "3ad4d432023c47ee9e6c7805b973630a",
    fallbackModel: "fish-audio/s2.1-pro",
    fallbackVoice: "3ad4d432023c47ee9e6c7805b973630a",
  },
  "david-attenborough": {
    fishReference: "c39a76f685cf4f8fb41cd5d3d66b497d",
    fallbackModel: "fish-audio/s2.1-pro",
    fallbackVoice: "c39a76f685cf4f8fb41cd5d3d66b497d",
  },
  jade: {
    fallbackModel: "x-ai/grok-voice-tts-1.0",
    fallbackVoice: "eve",
  },
});

export function validatePayload(value) {
  if (!value || typeof value !== "object") throw new Error("Expected a JSON object.");
  const prompt = typeof value.prompt === "string" ? value.prompt.trim() : "";
  if (!prompt || prompt.length > 16_000) throw new Error("Invalid narration prompt.");
  const voice = VOICES[value.voice];
  if (!voice) throw new Error("Unsupported narrator voice.");
  const languageCode = typeof value.language === "string" ? value.language : "en";
  const languageInstruction = narrationLanguageInstruction(languageCode);
  const capture = value.capture;
  if (!capture || typeof capture !== "object") throw new Error("Missing capture.");
  const mediaType = capture.mediaType;
  if (!["image/jpeg", "image/png", "image/webp"].includes(mediaType)) {
    throw new Error("Unsupported capture media type.");
  }
  const encoded = typeof capture.bytesBase64 === "string" ? capture.bytesBase64 : "";
  if (!encoded || !/^[A-Za-z0-9+/]*={0,2}$/.test(encoded)) {
    throw new Error("Invalid capture bytes.");
  }
  const image = Buffer.from(encoded, "base64");
  if (!image.length || image.length > 1_500_000) {
    throw new Error("Capture must contain at most 1.5 MB.");
  }
  const capturedAt = typeof capture.capturedAt === "string" ? capture.capturedAt : "";
  if (!capturedAt || Number.isNaN(Date.parse(capturedAt))) {
    throw new Error("Invalid capture timestamp.");
  }
  return {
    prompt,
    voice,
    voiceName: value.voice,
    languageCode,
    languageInstruction,
    capture: {
      id: typeof capture.id === "string" ? capture.id.slice(0, 120) : "capture",
      capturedAt,
      mediaType,
      image,
      protagonistHint:
        typeof capture.protagonistHint === "string"
          ? capture.protagonistHint.slice(0, 240)
          : "the recurring foreground camera holder",
    },
  };
}

export function validateSpeechPayload(value) {
  if (!value || typeof value !== "object") throw new Error("Expected a JSON object.");
  const text = typeof value.text === "string" ? value.text.trim() : "";
  if (!text || text.length > 900) throw new Error("Invalid speech text.");
  const voice = VOICES[value.voice];
  if (!voice) throw new Error("Unsupported narrator voice.");
  const languageCode = typeof value.language === "string" ? value.language : "en";
  narrationLanguageName(languageCode);
  return { text, voice, voiceName: value.voice, languageCode };
}

export async function renderSpeech(payload, options) {
  const fetchImpl = options.fetchImpl ?? fetch;
  const started = performance.now();
  let audio = null;
  let ttsProvider = "fish-audio";
  if (payload.voice.fishReference && options.fishApiKey) {
    let fishSession;
    try {
      fishSession = await openFishSession({
        apiKey: options.fishApiKey,
        referenceId: payload.voice.fishReference,
        WebSocketImpl: options.WebSocketImpl ?? WebSocket,
      });
      const fishAudio = fishSession.completed.catch(() => null);
      fishSession.addText(payload.text);
      fishSession.finish();
      audio = await fishAudio;
    } catch (_) {
      fishSession?.close();
    }
  }
  if (!audio) {
    ttsProvider = "openrouter";
    audio = await synthesizeWithOpenRouter(payload.text, payload.voice, {
      fetchImpl,
      openRouterApiKey: options.openRouterApiKey,
    });
  }
  if (!audio.length) throw new Error("Speech synthesis returned empty audio.");
  return {
    text: payload.text,
    audio,
    ttsProvider,
    timings: { firstToken: 0, total: performance.now() - started },
  };
}

export async function renderNarration(payload, options) {
  const fetchImpl = options.fetchImpl ?? fetch;
  const started = performance.now();
  const fishPromise = payload.voice.fishReference && options.fishApiKey
    ? openFishSession({
        apiKey: options.fishApiKey,
        referenceId: payload.voice.fishReference,
        WebSocketImpl: options.WebSocketImpl ?? WebSocket,
      }).then(
        (session) => ({ session }),
        (error) => ({ error }),
      )
    : Promise.resolve({ session: null });
  const responsePromise = fetchImpl(OPENROUTER_RESPONSES_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${options.openRouterApiKey}`,
      Accept: "text/event-stream",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(openRouterNarrationBody(payload)),
  });

  const [response, fishResult] = await Promise.all([responsePromise, fishPromise]);
  if (!response.ok) throw await providerError("OpenRouter narration", response);
  if (!response.body) throw new Error("OpenRouter narration returned no stream.");

  let firstTokenStarted = null;
  let text = "";
  let completedText = null;
  const fishSession = fishResult.session;
  let fishFailure = fishResult.error ?? null;
  const fishAudio = fishSession
    ? fishSession.completed.catch((error) => {
        fishFailure = error;
        return null;
      })
    : Promise.resolve(null);

  for await (const event of decodeSse(response.body)) {
    const streamError = responseStreamError(event);
    if (streamError) throw streamError;
    const delta = responseTextDelta(event);
    if (delta) {
      firstTokenStarted ??= performance.now();
      text += delta;
      if (fishSession && !fishFailure) {
        try {
          fishSession.addText(delta);
        } catch (error) {
          fishFailure = error;
          fishSession.close();
        }
      }
    }
    completedText ??= completedResponseText(event);
  }
  text = (text || completedText || "").trim();
  if (!text) throw new Error("OpenRouter completed without narration text.");

  let audio = null;
  let ttsProvider = "fish-audio";
  if (fishSession && !fishFailure) {
    try {
      fishSession.finish();
      audio = await fishAudio;
    } catch (error) {
      fishFailure = error;
      fishSession.close();
    }
  }
  if (!audio) {
    ttsProvider = "openrouter";
    audio = await synthesizeWithOpenRouter(text, payload.voice, {
      fetchImpl,
      openRouterApiKey: options.openRouterApiKey,
    });
  }
  if (!audio.length) throw new Error("Speech synthesis returned empty audio.");

  const finished = performance.now();
  return {
    text,
    audio,
    ttsProvider,
    timings: {
      firstToken: (firstTokenStarted ?? finished) - started,
      total: finished - started,
    },
  };
}

export function openRouterNarrationBody(payload) {
  const hint = payload.capture.protagonistHint
    ? ` Use ${payload.capture.protagonistHint} as focal guidance only when supported by the image.`
    : "";
  return {
    model: "openai/gpt-5.6-terra",
    reasoning: { effort: "high" },
    // High reasoning effort consumes this same budget before visible text.
    max_output_tokens: 2000,
    store: false,
    stream: true,
    provider: { sort: "latency" },
    instructions: `
You are the cinematic narrator of one continuous natural-history epic about
an ordinary person's day. Always produce a spoken line. Keep the grand,
theatrical delivery, grounded in the current capture.
Describe the visible action first: the subject, a concrete verb or posture,
and a specific object or spatial detail. Most of the sentence must tell the
listener what is actually happening in view. Inspect the image itself; capture
markers and protagonist hints are not evidence of an action or a visible person.
A single still image cannot prove a movement sequence. Never invent unseen
actions, objects, reactions, outcomes, or off-camera events. If the image is
unclear or no person is visible, describe the discernible scene without guessing.
Read the supplied narration history oldest to newest. The last spoken line is
the beat to continue: carry forward its activity, recurring object, or unresolved
playful premise and let the current visible action advance, complicate, or
resolve it. Do not restart the premise or reintroduce the protagonist each time.
Recurring names and objects are useful continuity, not forbidden repetition.
If little changes, continue the same activity through a visible detail without
inventing escalation. If the scene changes, bridge to the new visible activity.
Current visual evidence overrides earlier speculation; history is story context,
not proof that an earlier action is still happening. If history is empty or only
a generic introduction, establish the first concrete activity.
Allow at most one brief, playful interpretation attached to that visible action.
Imagined motives are a comic gloss, never visual facts. Avoid abstract destiny,
new invented crises, and stock metaphors that could fit any unrelated image.
Write the spoken line exclusively in the third person; never use first- or
second-person narration. Render inner monologue only as indirect narration,
never as the subject speaking or thinking in quotation.
The passage must contain 10 to
20 words in one commanding sentence, with no stage directions.
${payload.languageInstruction}
Output only the exact words to
speak, without quotation marks, a label, JSON, Markdown, commentary, or stage
directions.`.trim(),
    input: [
      {
        role: "user",
        content: [
          { type: "input_text", text: payload.prompt },
          {
            type: "input_text",
            text: `Live capture ${payload.capture.id}, observed at ${payload.capture.capturedAt}.${hint}`,
          },
          {
            type: "input_image",
            detail: "low",
            image_url: `data:${payload.capture.mediaType};base64,${payload.capture.image.toString("base64")}`,
          },
        ],
      },
    ],
  };
}

export async function* decodeSse(body) {
  const decoder = new TextDecoder();
  let buffered = "";
  for await (const chunk of body) {
    buffered += decoder.decode(chunk, { stream: true });
    while (true) {
      const match = /\r?\n\r?\n/.exec(buffered);
      if (!match) break;
      const raw = buffered.slice(0, match.index);
      buffered = buffered.slice(match.index + match[0].length);
      const event = decodeSseEvent(raw);
      if (event === DONE) return;
      if (event) yield event;
    }
  }
  buffered += decoder.decode();
  const event = decodeSseEvent(buffered);
  if (event && event !== DONE) yield event;
}

const DONE = Symbol("done");

function decodeSseEvent(raw) {
  const data = raw
    .split(/\r?\n/)
    .filter((line) => line.startsWith("data:"))
    .map((line) => line.slice(5).replace(/^ /, ""));
  if (!data.length) return null;
  const value = data.join("\n");
  if (value === "[DONE]") return DONE;
  return JSON.parse(value);
}

function responseTextDelta(event) {
  if (!["response.output_text.delta", "response.content_part.delta"].includes(event.type)) {
    return null;
  }
  if (typeof event.delta === "string") return event.delta;
  return typeof event.delta?.text === "string" ? event.delta.text : null;
}

function completedResponseText(event) {
  if (!["response.completed", "response.done"].includes(event.type)) return null;
  const output = event.response?.output;
  if (!Array.isArray(output)) return null;
  return output
    .flatMap((item) => (Array.isArray(item?.content) ? item.content : []))
    .map((part) => part?.text)
    .filter((part) => typeof part === "string")
    .join("");
}

function responseStreamError(event) {
  if (event.error) return new Error(event.error.message ?? "OpenRouter stream failed.");
  if (!["error", "response.failed", "response.incomplete"].includes(event.type)) return null;
  return new Error(event.response?.error?.message ?? `OpenRouter stream ${event.type}.`);
}

async function synthesizeWithOpenRouter(text, voice, options) {
  const response = await options.fetchImpl(OPENROUTER_SPEECH_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${options.openRouterApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: voice.fallbackModel,
      voice: voice.fallbackVoice,
      input: text,
      response_format: "mp3",
    }),
  });
  if (!response.ok) throw await providerError("OpenRouter speech", response);
  return Buffer.from(await response.arrayBuffer());
}

async function providerError(provider, response) {
  const body = (await response.text()).slice(0, 1000);
  return new Error(`${provider} failed with HTTP ${response.status}: ${body}`);
}

export function openFishSession({ apiKey, referenceId, WebSocketImpl = WebSocket }) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocketImpl(FISH_LIVE_URL, {
      headers: { Authorization: `Bearer ${apiKey}`, model: "s2-pro" },
    });
    let opened = false;
    const failBeforeOpen = (error) => {
      if (!opened) reject(error);
    };
    socket.once("error", failBeforeOpen);
    socket.once("unexpected-response", (_request, response) => {
      reject(new Error(`Fish Audio handshake failed with HTTP ${response.statusCode}.`));
    });
    socket.once("open", () => {
      opened = true;
      socket.off("error", failBeforeOpen);
      resolve(new FishSession(socket, referenceId));
    });
  });
}

class FishSession {
  constructor(socket, referenceId) {
    this.socket = socket;
    this.pendingText = "";
    this.audio = [];
    this.settled = false;
    this.completed = new Promise((resolve, reject) => {
      this.resolve = resolve;
      this.reject = reject;
    });
    this.timeout = setTimeout(() => this.fail(new Error("Fish Audio timed out.")), 15_000);
    socket.on("message", (raw) => this.receive(raw));
    socket.on("error", (error) => this.fail(error));
    socket.on("close", () => {
      if (!this.settled) this.fail(new Error("Fish Audio closed before completion."));
    });
    this.send({
      event: "start",
      request: {
        text: "",
        format: "mp3",
        chunk_length: 100,
        reference_id: referenceId,
        latency: "low",
      },
    });
  }

  addText(delta) {
    this.pendingText += delta;
    const boundary = flushBoundary(this.pendingText, 48);
    if (boundary == null) return;
    this.send({ event: "text", text: this.pendingText.slice(0, boundary) });
    this.send({ event: "flush" });
    this.pendingText = this.pendingText.slice(boundary);
  }

  finish() {
    if (this.pendingText) this.send({ event: "text", text: this.pendingText });
    this.send({ event: "flush" });
    this.send({ event: "stop" });
    this.pendingText = "";
  }

  receive(raw) {
    let event;
    try {
      event = decode(new Uint8Array(raw.buffer, raw.byteOffset, raw.byteLength));
    } catch (error) {
      this.fail(error);
      return;
    }
    if (event.event === "audio" && event.audio) {
      this.audio.push(Buffer.from(event.audio));
      return;
    }
    if (event.event !== "finish") return;
    if (event.reason !== "stop" || !this.audio.length) {
      this.fail(new Error("Fish Audio reported synthesis failure."));
      return;
    }
    this.settled = true;
    clearTimeout(this.timeout);
    this.resolve(Buffer.concat(this.audio));
    this.socket.close();
  }

  send(event) {
    if (this.settled || this.socket.readyState !== 1) {
      throw new Error("Fish Audio session is unavailable.");
    }
    this.socket.send(encode(event));
  }

  fail(error) {
    if (this.settled) return;
    this.settled = true;
    clearTimeout(this.timeout);
    this.reject(error);
    this.socket.close();
  }

  close() {
    this.fail(new Error("Fish Audio session cancelled."));
  }
}

function flushBoundary(text, threshold) {
  if (text.length < threshold) return null;
  for (let index = threshold - 1; index < text.length; index += 1) {
    if (/[\s,.:;!?]/.test(text[index])) return index + 1;
  }
  return null;
}
