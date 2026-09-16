import { readFileSync } from "node:fs";
import { spawn } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const credentials = [
  ["OPENROUTER_API_KEY", ".secrets/openrouter-key", true],
  ["FISH_AUDIO_API_KEY", ".secrets/fishaudio-key", false],
];

// The browser never receives these values. Only the local function process
// inherits them; nothing is written into Flutter assets or a generated env file.
export function devConfiguration({
  env = process.env,
  readSecret = (path) => readFileSync(resolve(projectRoot, path), "utf8"),
} = {}) {
  const childEnv = { ...env };
  const sources = [];
  for (const [name, path, required] of credentials) {
    let value = env[name]?.trim();
    let source = "shell environment";
    if (!value) {
      source = path;
      try { value = readSecret(path).trim(); }
      catch (error) {
        if (error.code !== "ENOENT") throw new Error(`Cannot read ${path}.`);
      }
    }
    if (!value) {
      delete childEnv[name];
      if (required) throw new Error(`Set ${name} in your shell or put your key in ${path}.`);
      sources.push(`${name}: absent; speech will use OpenRouter`);
      continue;
    }
    if (/\s|["']/.test(value) || /^(?:\*+|\[?redacted\]?|undefined|null)$/i.test(value)) {
      throw new Error(`${name} from ${source} is not a usable API key. Supply the raw key without quotes or a Bearer prefix.`);
    }
    childEnv[name] = value;
    sources.push(`${name}: loaded from ${source}`);
  }
  return {
    env: childEnv,
    sources,
    // Offline disables Netlify's remote env injection and AI Gateway setup,
    // not outbound OpenRouter/Fish requests made by our function.
    args: ["dev", "--offline", "--framework", "#static", "--dir", "web", "--port", "8888", "--no-open"],
  };
}

function main() {
  try {
    const config = devConfiguration();
    for (const source of config.sources) console.info(`[MCGEE dev] ${source}`);
    if (process.argv.includes("--check")) return;
    const child = spawn(process.platform === "win32" ? "netlify.cmd" : "netlify", config.args, {
      cwd: projectRoot, env: config.env, stdio: "inherit",
    });
    child.on("error", () => {
      console.error("[MCGEE dev] Could not start Netlify CLI. Check that netlify is installed.");
      process.exitCode = 1;
    });
    const stop = (signal) => child.kill(signal);
    const interrupt = () => stop("SIGINT");
    const terminate = () => stop("SIGTERM");
    process.on("SIGINT", interrupt);
    process.on("SIGTERM", terminate);
    child.on("exit", (code, signal) => {
      process.off("SIGINT", interrupt);
      process.off("SIGTERM", terminate);
      process.exitCode = code ?? (signal === "SIGINT" ? 130 : 1);
    });
  } catch (error) {
    console.error(`[MCGEE dev] ${error.message}`);
    process.exitCode = 1;
  }
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) main();
