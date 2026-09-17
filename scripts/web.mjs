import { spawn, spawnSync } from "node:child_process";
import { readFileSync, mkdirSync, writeFileSync } from "node:fs";
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

const config = {
  OPENROUTER_API_KEY: mode === "e2e"
    ? "mock-openrouter-key"
    : credential("OPENROUTER_API_KEY", ".secrets/openrouter-key"),
};
if (mode === "check") {
  credential("FISH_AUDIO_API_KEY", ".secrets/fishaudio-key");
  process.stdout.write("OpenRouter and server-side Fish credentials are configured.\n");
  process.exit(0);
}

mkdirSync(resolve(".secrets"), { recursive: true });
const defines = resolve(mode === "e2e" ? ".secrets/e2e-keys.json" : ".secrets/web-keys.json");
writeFileSync(defines, JSON.stringify(config), { mode: 0o600 });

if (mode === "dev" || mode === "e2e") {
  const server = mode === "e2e"
    ? (await import("./e2e-server.mjs")).startE2EServer({
      fishDelayMs: Number(process.env.MOCK_FISH_DELAY_MS ?? 0),
    })
    : (await import("./speech-dev.mjs")).startSpeechServer({
      apiKey: credential("FISH_AUDIO_API_KEY", ".secrets/fishaudio-key"),
    });
  const flutter = spawn("flutter", ["run", "-d", mode === "e2e" ? "web-server" : "chrome",
    `--dart-define-from-file=${defines}`,
    "--dart-define=SPEECH_ENDPOINT=http://127.0.0.1:8767/api/speech",
    ...(mode === "e2e" ? [
      "--web-port=8770",
      "--dart-define=MOCK_CAMERA_FEED=true",
      "--dart-define=OPENROUTER_ENDPOINT=http://127.0.0.1:8767/openrouter/",
    ] : []),
    ...process.argv.slice(3)], { stdio: "inherit" });
  flutter.on("error", (error) => { console.error(error); server.close(); process.exitCode = 1; });
  flutter.on("exit", (code) => { server.close(); process.exitCode = code ?? 1; });
} else {
  if (mode === "deploy") {
    run("npm", ["test"]);
    run("flutter", ["test"]);
  }
  run("flutter", ["build", "web", "--release", `--dart-define-from-file=${defines}`]);
  if (mode === "deploy") run("netlify", ["deploy", "--prod", "--dir=build/web"]);
}
