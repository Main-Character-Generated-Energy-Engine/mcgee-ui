import prompt from "../../lib/assets/film-opening-prompt.json" with { type: "json" };
import { narrationLanguageName } from "./narration_language.mjs";

export function openingRequestBody(value) {
  const language = narrationLanguageName(value?.language);
  const characterName = validateCharacterName(value?.characterName);
  return {
    model: prompt.model,
    reasoning: { effort: "high" },
    // High reasoning effort consumes this same budget before the JSON output.
    max_output_tokens: 2400,
    store: false,
    provider: { sort: "latency" },
    instructions: prompt.instructions,
    input: `Create a new opening in ${language}. The protagonist name is ${JSON.stringify(characterName)}.`,
  };
}

export function validateCharacterName(value) {
  if (typeof value !== "string") throw new Error("Missing protagonist name.");
  if (/[\u0000-\u001f\u007f]/.test(value)) {
    throw new Error("Invalid protagonist name.");
  }
  const name = value.trim().replace(/\s+/g, " ");
  if (!name || name.length > 60) {
    throw new Error("Invalid protagonist name.");
  }
  return name;
}

export function parseOpening(value) {
  const limits = { title: 90, director: 70, narration: 900 };
  const opening = {};
  for (const [key, limit] of Object.entries(limits)) {
    const text = value?.[key];
    if (typeof text !== "string" || !text.trim() || text.length > limit) {
      throw new Error(`Invalid opening ${key}.`);
    }
    opening[key] = text.trim();
  }
  return opening;
}

export async function generateOpening(value, options) {
  const body = openingRequestBody(value);
  const response = await (options.fetchImpl ?? fetch)("https://openrouter.ai/api/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${options.openRouterApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(28_000),
  });
  if (!response.ok) throw new Error(`Opening generation failed with HTTP ${response.status}.`);
  const result = await response.json();
  if (result.status === "incomplete" || result.error) {
    throw new Error("Opening generation did not complete.");
  }
  const text = result.output_text ?? (result.output ?? [])
    .flatMap((item) => item.content ?? [])
    .filter((part) => part.type === "output_text")
    .map((part) => part.text).join("");
  return parseOpening(JSON.parse(text));
}
