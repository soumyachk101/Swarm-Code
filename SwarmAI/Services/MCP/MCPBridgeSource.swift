import Foundation

/// The JavaScript bridge that exposes the connected MCP servers' tools to the
/// providers that load a file SwarmAI installs: Pi (an extension) and
/// Command Code (a mod). Both dynamic-import it and call `loadMCPTools()`.
///
/// Plain ESM JavaScript (Node 18+, no npm dependencies). The server list comes
/// from the file at `SWARMAI_MCP_CONFIG` or `DROPPY_CODE_MCP_CONFIG`
/// (`{"mcpServers": { id: {command, args, env} | {type: "http", url, headers} }}`);
/// when the variable is unset or the file is missing, nothing is registered.
enum MCPBridge {
    static let mcpBridgeSource: String = #"""
    import fs from "node:fs";
    import { spawn, execFileSync } from "node:child_process";

    const PROTOCOL_VERSION = "2025-06-18";
    const CONNECT_TIMEOUT_MS = 15000;

    /// Shell metacharacters that could enable injection if ever passed to a
    /// shell or interpreted by a downstream process. Rejected from commands
    /// and arguments as a defense-in-depth measure.
    const INJECTION_RE = /[\n\r;|&`$(){}[\]\\"'<>]/;

    function assertNoInjection(label, value) {
      if (typeof value !== "string" || INJECTION_RE.test(value)) {
        throw new Error(label + " contains invalid characters.");
      }
    }

    /// Environment variables that can hijack runtime behavior or inject code
    /// into spawned MCP server processes. Any matching key is stripped before
    /// the env dictionary is merged into the child process environment.
    const BLOCKED_ENV_KEYS = new Set([
      "LD_PRELOAD", "LD_LIBRARY_PATH", "DYLD_INSERT_LIBRARIES",
      "NODE_OPTIONS", "NODE_REPL_EXTERNAL_MODULE",
      "PYTHONPATH", "PYTHONSTARTUP", "PYTHONHOME",
      "PERL5OPT", "PERL5LIB", "RUBYOPT", "RUBYLIB",
      "BASH_ENV", "ENV", "IFS",
      "GIT_", "GCONV_PATH", "NSS_WRAPPER_PASSWD", "NSS_WRAPPER_GROUP",
    ]);

    function cleanEnv(rawEnv) {
      if (!rawEnv || typeof rawEnv !== "object") return {};
      const out = {};
      for (const [key, value] of Object.entries(rawEnv)) {
        const upper = key.toUpperCase();
        if ([...BLOCKED_ENV_KEYS].some((blocked) => upper === blocked || upper.startsWith(blocked))) {
          continue;
        }
        out[key] = value;
      }
      return out;
    }

    /// Known-safe MCP server commands. Anything whose resolved path has a
    /// base name outside this set is rejected before spawning.
    const ALLOWED_COMMANDS = new Set([
      "node", "nodejs", "npx", "bun", "deno",
      "python3", "python", "uv", "uvx",
      "java", "kotlin", "ruby", "gem",
      "go", "golang",
    ]);

    /// Directories trusted to host MCP server executables. The resolved
    /// absolute path of the command must start with one of these.
    const TRUSTED_PREFIXES = [
      "/usr/bin/", "/usr/local/bin/",
      "/opt/homebrew/bin/",
      "/usr/lib/", "/Users/", "/home/",
    ];

    /// Resolve a command name to an absolute path using `which`, then
    /// validate the resolved path against the allowlist and trusted-prefix list.
    /// Throws if the command is not safe to launch.
    function validateCommand(command) {
      assertNoInjection("command", command);
      const resolved = execFileSync("which", [command], { encoding: "utf8" }).trim();
      const base = resolved.split("/").pop().toLowerCase();
      if (!ALLOWED_COMMANDS.has(base)) {
        throw new Error("'" + command + "' is not an allowed MCP server command.");
      }
      if (!TRUSTED_PREFIXES.some((p) => resolved.startsWith(p))) {
        throw new Error("'" + command + "' is not in a trusted location: " + resolved);
      }
      return resolved;
    }

    function validateUrl(url) {
      assertNoInjection("url", url);
      let parsed;
      try {
        parsed = new URL(url);
      } catch {
        throw new Error("Invalid URL: " + url);
      }
      if (!["http:", "https:"].includes(parsed.protocol)) {
        throw new Error("URL protocol must be http or https: " + parsed.protocol);
      }
      const hostname = parsed.hostname.toLowerCase();
      // Loopback
      if (hostname === "localhost" || hostname === "127.0.0.1" || hostname === "::1") {
        throw new Error("URL targets a loopback address.");
      }
      // Link-local (169.254.0.0/16, fe80::/10)
      if (hostname.startsWith("169.254.") || hostname.startsWith("fe80:")) {
        throw new Error("URL targets a link-local address.");
      }
      // RFC1918 private ranges: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
      const octets = hostname.split(".").map(Number);
      if (octets.length === 4) {
        if (octets[0] === 10 || (octets[0] === 172 && octets[1] >= 16 && octets[1] <= 31) || (octets[0] === 192 && octets[1] === 168)) {
          throw new Error("URL targets a private network address.");
        }
      }
      return parsed;
    }

    /// Validate each argument before spawning: reject shell metacharacters
    /// and leading `-` (which could smuggle flags into the child process).
    /// Returns the safe argv to pass to spawn.
    function validateArgs(args) {
      const out = [];
      for (let i = 0; i < args.length; i++) {
        const arg = String(args[i]);
        if (INJECTION_RE.test(arg)) {
          throw new Error("arg " + i + " contains invalid characters.");
        }
        if (arg.startsWith("-")) {
          throw new Error("arg " + i + " cannot start with '-' (flag smuggling guard).");
        }
        out.push(arg);
      }
      return out;
    }

    function configServers() {
      try {
        const file = process.env.SWARMAI_MCP_CONFIG || process.env.DROPPY_CODE_MCP_CONFIG || "";
        if (!file) return {};
        const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
        if (parsed && typeof parsed === "object" && parsed.mcpServers && typeof parsed.mcpServers === "object") return parsed.mcpServers;
      } catch (error) {
        console.error("swarmai mcp: could not read config: " + errorText(error));
      }
      return {};
    }

    function errorText(error) {
      return error instanceof Error ? error.message : String(error);
    }

    function contentText(content) {
      const items = Array.isArray(content) ? content : [];
      return items.map((item) => (item && item.type === "text" && typeof item.text === "string" ? item.text : "[image]")).join("\n");
    }

    function describe(entry, fallback) {
      if (entry && typeof entry.description === "string" && entry.description) return entry.description;
      return fallback;
    }

    function schemaOf(entry) {
      if (entry && entry.inputSchema && typeof entry.inputSchema === "object") return entry.inputSchema;
      return { type: "object" };
    }

    function withTimeout(promise) {
      let timer = null;
      const timeout = new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error("timed out")), CONNECT_TIMEOUT_MS);
      });
      return Promise.race([promise, timeout]).finally(() => { if (timer) clearTimeout(timer); });
    }

    function wrapTools(server, entries, callTool) {
      return entries.map((entry) => ({
        server,
        name: String(entry.name),
        description: describe(entry, String(entry.name)),
        inputSchema: schemaOf(entry),
        call: async (args) => {
          try {
            const result = await callTool(entry.name, args && typeof args === "object" ? args : {});
            if (result && result.isError) return "Error: " + (contentText(result.content) || "tool failed");
            return contentText(result ? result.content : []);
          } catch (error) {
            return "Error: " + errorText(error);
          }
        },
      }));
    }

    function connectStdio(server, entry) {
      return new Promise((resolve, reject) => {
        let child = null;
        try {
          const resolvedCommand = validateCommand(entry.command);
          const safeArgs = validateArgs(Array.isArray(entry.args) ? entry.args : []);
          child = spawn(resolvedCommand, safeArgs, {
            env: { ...process.env, ...cleanEnv(entry.env) },
            stdio: ["pipe", "pipe", "ignore"],
          });
        } catch (error) {
          reject(error);
          return;
        }
        let id = 0;
        const pending = new Map();
        let buffer = "";
        let settled = false;
        const fail = (error) => {
          for (const resolvePending of pending.values()) resolvePending({ error: { message: errorText(error) } });
          pending.clear();
          if (settled) return;
          settled = true;
          reject(error);
        };
        child.on("error", fail);
        child.on("exit", () => fail(new Error("process exited")));
        child.stdin.on("error", () => {});
        child.stdout.on("data", (data) => {
          buffer += data.toString("utf8");
          let index = -1;
          while ((index = buffer.indexOf("\n")) >= 0) {
            const line = buffer.slice(0, index).trim();
            buffer = buffer.slice(index + 1);
            if (!line) continue;
            let message = null;
            try { message = JSON.parse(line); } catch { continue; }
            if (message && message.id !== undefined && message.id !== null && pending.has(message.id)) {
              const resolvePending = pending.get(message.id);
              pending.delete(message.id);
              resolvePending(message);
            }
          }
        });
        const send = (method, params) => new Promise((resolveSend, rejectSend) => {
          const message = { jsonrpc: "2.0", id: id++, method };
          if (params !== undefined) message.params = params;
          pending.set(message.id, resolveSend);
          child.stdin.write(JSON.stringify(message) + "\n", (error) => {
            if (error) { pending.delete(message.id); rejectSend(error); }
          });
        });
        const request = async (method, params) => {
          const response = await send(method, params);
          if (response && response.error) throw new Error(String((response.error && response.error.message) || "request failed"));
          return response ? response.result : undefined;
        };
        const notify = (method, params) => {
          const message = { jsonrpc: "2.0", method };
          if (params !== undefined) message.params = params;
          child.stdin.write(JSON.stringify(message) + "\n");
        };
        const callTool = (name, args) => request("tools/call", { name, arguments: args });
        (async () => {
          await request("initialize", { protocolVersion: PROTOCOL_VERSION, capabilities: {}, clientInfo: { name: "SwarmAI" } });
          notify("notifications/initialized", {});
          let cursor = undefined;
          const tools = [];
          for (;;) {
            const result = await request("tools/list", cursor === undefined ? {} : { cursor });
            for (const tool of ((result && result.tools) || [])) tools.push(tool);
            cursor = result ? result.nextCursor : undefined;
            if (!cursor) break;
          }
          settled = true;
          resolve(wrapTools(server, tools, callTool));
        })().catch(fail);
      });
    }

    async function postMessage(url, headers, payload, sessionId) {
      const requestHeaders = { ...(headers || {}), "Content-Type": "application/json", Accept: "application/json, text/event-stream" };
      if (sessionId) requestHeaders["mcp-session-id"] = sessionId;
      const response = await fetch(url, { method: "POST", headers: requestHeaders, body: JSON.stringify(payload), redirect: "manual" });
      if (!response.url || response.url !== url) {
        throw new Error("Request was redirected to an unexpected URL: " + response.url);
      }
      const nextSession = response.headers.get("mcp-session-id") || sessionId || null;
      const contentType = response.headers.get("content-type") || "";
      let message = null;
      if (contentType.includes("text/event-stream")) {
        const text = await response.text();
        for (const line of text.split("\n")) {
          const trimmed = line.trim();
          if (!trimmed.startsWith("data:")) continue;
          const data = trimmed.slice("data:".length).trim();
          if (!data || data === "[DONE]") continue;
          try {
            const parsed = JSON.parse(data);
            if (parsed && typeof parsed === "object" && ("result" in parsed || "error" in parsed)) { message = parsed; break; }
          } catch {}
        }
      } else {
        const text = await response.text();
        try { message = text ? JSON.parse(text) : null; } catch { message = null; }
      }
      if (!message) throw new Error("empty response (status " + response.status + ")");
      return { message, sessionId: nextSession };
    }

    function connectRemote(server, entry) {
      return (async () => {
        const parsedUrl = validateUrl(entry.url);
        const url = parsedUrl.toString();
        const headers = (entry.headers && typeof entry.headers === "object") ? entry.headers : {};
        let sessionId = null;
        let id = 0;
        const request = async (method, params) => {
          const payload = { jsonrpc: "2.0", id: id++, method };
          if (params !== undefined) payload.params = params;
          const outcome = await postMessage(url, headers, payload, sessionId);
          sessionId = outcome.sessionId;
          if (outcome.message.error) throw new Error(String((outcome.message.error && outcome.message.error.message) || "request failed"));
          return outcome.message.result;
        };
        const notify = async (method, params) => {
          const payload = { jsonrpc: "2.0", method };
          if (params !== undefined) payload.params = params;
          try {
            const outcome = await postMessage(url, headers, payload, sessionId);
            sessionId = outcome.sessionId;
          } catch {}
        };
        await request("initialize", { protocolVersion: PROTOCOL_VERSION, capabilities: {}, clientInfo: { name: "SwarmAI" } });
        await notify("notifications/initialized", {});
        let cursor = undefined;
        const tools = [];
        for (;;) {
          const result = await request("tools/list", cursor === undefined ? {} : { cursor });
          for (const tool of ((result && result.tools) || [])) tools.push(tool);
          cursor = result ? result.nextCursor : undefined;
          if (!cursor) break;
        }
        const callTool = (name, args) => request("tools/call", { name, arguments: args });
        return wrapTools(server, tools, callTool);
      })();
    }

    export async function loadMCPTools() {
      const servers = configServers();
      const tools = [];
      for (const server of Object.keys(servers)) {
        const entry = servers[server];
        try {
          if (entry && typeof entry === "object" && entry.type === "http" && typeof entry.url === "string") {
            tools.push(...await withTimeout(connectRemote(server, entry)));
          } else if (entry && typeof entry === "object" && typeof entry.command === "string") {
            tools.push(...await withTimeout(connectStdio(server, entry)));
          }
        } catch (error) {
          console.error("swarmai mcp: skipping " + server + ": " + errorText(error));
        }
      }
      return tools;
    }
    """#

    /// Writes the bridge where the Pi extension and the Command Code mod can
    /// import it, and returns its path. Rewritten only when its text changed,
    /// so a new build's bridge replaces the old one.
    static func installBridge() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: LoginEnvironment.homeDirectory).appendingPathComponent("Library/Application Support")
        let directory = base.appendingPathComponent("\(AppInfo.name)/MCP", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("swarmai-mcp-bridge.mjs")
        let data = Data(mcpBridgeSource.utf8)
        if (try? Data(contentsOf: file)) != data {
            try data.write(to: file, options: .atomic)
        }
        return file
    }
}
