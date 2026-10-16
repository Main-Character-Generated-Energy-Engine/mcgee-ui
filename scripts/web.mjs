import { spawn, spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

function credential(name, path) {
  let value = process.env[name];
  if (!value) {
    try { value = readFileSync(resolve(path), "utf8"); } catch { /* checked below */ }
  }
  value = value?.trim();
  if (!value || /\s/.test(value)) {
    throw new Error(`Set ${name} or provide ${path}.`);
  }
  return value;
}

function run(command, args) {
  const result = spawnSync(command, args, { stdio: "inherit" });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

const mode = process.argv[2];
if (!["dev", "e2e", "build", "deploy", "check"].includes(mode)) {
  throw new Error("Usage: node scripts/web.mjs dev|e2e|build|deploy|check");
}
if (mode === "deploy" && spawnSync("netlify", ["--version"], { stdio: "ignore" }).status !== 0) {
  throw new Error("Netlify CLI unavailable; run mise exec -- netlify --version to prepare the shared host tool.");
}

if (mode === "check") {
  credential("OPENAI_API_KEY", ".secrets/openai-key");
  credential("FISH_AUDIO_API_KEY", ".secrets/fishaudio-key");
  process.stdout.write("Server-side OpenAI and Fish credentials are configured.\n");
  process.exit(0);
}

if (mode === "dev" || mode === "e2e") {
  const host = process.env.MCGEE_DEV_HOST ?? "127.0.0.1";
  const device = mode === "e2e" ? "web-server" : (process.env.MCGEE_WEB_DEVICE ?? "chrome");
  const server = mode === "e2e"
    ? (await import("./e2e-server.mjs")).startE2EServer({
      host,
      fishDelayMs: Number(process.env.MOCK_FISH_DELAY_MS ?? 0),
    })
    : (await import("./speech-dev.mjs")).startSpeechServer({
      host,
      apiKey: credential("FISH_AUDIO_API_KEY", ".secrets/fishaudio-key"),
      openAiApiKey: credential("OPENAI_API_KEY", ".secrets/openai-key"),
    });
  const flutter = spawn("flutter", ["run", "-d", device,
    `--web-hostname=${host}`,
    ...(device === "web-server" ? ["--web-port=8770"] : []),
    "--dart-define=NARRATION_ENDPOINT=http://127.0.0.1:8767/api/narration/",
    "--dart-define=SPEECH_ENDPOINT=http://127.0.0.1:8767/api/speech",
    ...(mode === "e2e" ? [
      "--dart-define=MOCK_CAMERA_FEED=true",
    ] : []),
    ...process.argv.slice(3)], { stdio: "inherit" });
  flutter.on("error", (error) => { console.error(error); server.close(); process.exitCode = 1; });
  flutter.on("exit", (code) => { server.close(); process.exitCode = code ?? 1; });
} else {
  if (mode === "deploy") {
    run("npm", ["test"]);
  }
  run("flutter", ["build", "web", "--release"]);
  if (mode === "deploy") run("netlify", ["deploy", "--prod", "--dir=build/web"]);
}
