import assert from "node:assert/strict";
import test from "node:test";
import { devConfiguration } from "../scripts/dev-functions.mjs";

const missing = () => { throw Object.assign(new Error("missing"), { code: "ENOENT" }); };

test("local dev loads existing secret files, trims newlines, and disables cloud injection", () => {
  const config = devConfiguration({
    env: { PATH: "/bin" },
    readSecret: (path) => path.includes("openrouter") ? "test-router-key\n" : "test-fish-key\r\n",
  });
  assert.equal(config.env.OPENROUTER_API_KEY, "test-router-key");
  assert.equal(config.env.FISH_AUDIO_API_KEY, "test-fish-key");
  assert.equal(config.env.PATH, "/bin");
  assert.ok(config.args.includes("--offline"));
  assert.equal(config.args[config.args.indexOf("--dir") + 1], "web");
  assert.equal(config.args[config.args.indexOf("--port") + 1], "8888");
  assert.match(config.sources.join("\n"), /\.secrets\/openrouter-key/);
  assert.ok(!config.sources.join("\n").includes("test-router-key"));
  assert.ok(!config.sources.join("\n").includes("test-fish-key"));
});

test("explicit shell credentials take priority without changing the parent environment", () => {
  const env = { OPENROUTER_API_KEY: " shell-router\n", FISH_AUDIO_API_KEY: "shell-fish" };
  const config = devConfiguration({ env, readSecret: () => { throw new Error("Must not read files"); } });
  assert.equal(config.env.OPENROUTER_API_KEY, "shell-router");
  assert.equal(env.OPENROUTER_API_KEY, " shell-router\n");
  assert.ok(config.sources.every((source) => source.includes("shell environment")));
});

test("missing required credential fails before starting the function server", () => {
  assert.throws(() => devConfiguration({ env: {}, readSecret: missing }), /Set OPENROUTER_API_KEY/);
});

test("Fish is optional and doesn't inject an empty credential", () => {
  const config = devConfiguration({ env: { OPENROUTER_API_KEY: "test-router" }, readSecret: missing });
  assert.equal(config.env.FISH_AUDIO_API_KEY, undefined);
  assert.match(config.sources.join("\n"), /speech will use OpenRouter/);
});

test("malformed and masked credentials fail without revealing their values", () => {
  for (const value of ["Bearer secret", '"secret"', "********", "[REDACTED]", "null"]) {
    assert.throws(() => devConfiguration({ env: { OPENROUTER_API_KEY: value }, readSecret: missing }), (error) => {
      assert.match(error.message, /not a usable API key/);
      assert.ok(!error.message.includes(value));
      return true;
    });
  }
});
