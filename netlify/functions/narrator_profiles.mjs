import profiles from "../../lib/assets/narrator-profiles.json" with { type: "json" };

export function narratorProfile(voice) {
  if (typeof voice !== "string" || !Object.hasOwn(profiles, voice)) {
    throw new Error("Unsupported narrator voice.");
  }
  return profiles[voice];
}
