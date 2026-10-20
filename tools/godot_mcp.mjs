
import { spawn } from "node:child_process";
import fs from "node:fs";
const BASE_ENV = JSON.parse(fs.readFileSync("D:\\休闲小岛幻境\\游戏工程\\tools\\base_env.json", "utf8"));
const UVX = "D:\\python\\Scripts\\uvx.exe";
const ARGS = ["--isolated", "--no-config", "--no-env-file", "--from", "godot-ai==4.3.0", "godot-ai", "attach"];

export function startClient() {
  const child = spawn(UVX, ARGS, { cwd: "D:\\休闲小岛幻境\\游戏工程", stdio: ["pipe", "pipe", "pipe"], env: BASE_ENV });
  let buf = ""; let seq = 0; let stderr = "";
  const pending = new Map();
  child.stderr.on("data", (d) => { stderr += d.toString(); if (stderr.length > 6000) stderr = stderr.slice(-6000); });
  child.stdout.on("data", (d) => {
    buf += d.toString();
    let idx;
    while ((idx = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, idx).trim(); buf = buf.slice(idx + 1);
      if (!line) continue;
      let msg; try { msg = JSON.parse(line); } catch { continue; }
      if (msg.id != null && pending.has(String(msg.id))) {
        const p = pending.get(String(msg.id)); pending.delete(String(msg.id));
        if (msg.error) p.rej(new Error(msg.error.message || JSON.stringify(msg.error))); else p.res(msg.result);
      }
    }
  });
  function send(method, params, timeoutMs = 45000) {
    return new Promise((res, rej) => {
      const id = ++seq;
      const t = setTimeout(() => { pending.delete(String(id)); rej(new Error("timeout " + method)); }, timeoutMs);
      pending.set(String(id), { res: (v) => { clearTimeout(t); res(v); }, rej: (e) => { clearTimeout(t); rej(e); } });
      child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
    });
  }
  const ready = (async () => {
    await send("initialize", { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "dsh-fallback", version: "1.0" } }, 60000);
    child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized", params: {} }) + "\n");
  })();
  async function call(name, args) {
    await ready;
    return await send("tools/call", { name, arguments: args || {} }, 120000);
  }
  function close() { try { child.stdin.end(); } catch {} setTimeout(() => { try { child.kill(); } catch {} }, 300); }
  return { call, close, send, getStderr: () => stderr, child };
}

export async function oneShot(name, args) {
  const c = startClient();
  try { const r = await c.call(name, args); return r; }
  finally { c.close(); }
}
