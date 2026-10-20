
// Minimal MCP stdio client for the godot-ai attach server.
import { spawn } from "node:child_process";
import fs from "node:fs";
const BASE_ENV = JSON.parse(fs.readFileSync("D:\\休闲小岛幻境\\游戏工程\\tools\\base_env.json", "utf8"));

const UVX = "D:\\python\\Scripts\\uvx.exe";
const ARGS = ["--isolated", "--no-config", "--no-env-file", "--from", "godot-ai==4.3.0", "godot-ai", "attach"];
const reqs = [];
let buf = "";
let seq = 0;
const pending = new Map();

const child = spawn(UVX, ARGS, { cwd: "D:\\休闲小岛幻境\\游戏工程", stdio: ["pipe", "pipe", "pipe"], env: { ...BASE_ENV } });
child.stderr.on("data", d => { const s = d.toString(); if (process.env.VERBOSE) process.stderr.write(s); });
child.on("error", e => { console.error("SPAWN ERR", e.message); process.exit(1); });

function send(method, params) {
  const id = ++seq;
  const msg = { jsonrpc: "2.0", id, method, params: params || {} };
  child.stdin.write(JSON.stringify(msg) + "\n");
  return new Promise((res, rej) => pending.set(id, { res, rej, method }));
}
function notify(method, params) {
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method, params: params || {} }) + "\n");
}
child.stdout.on("data", d => {
  buf += d.toString();
  let idx;
  while ((idx = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, idx).trim();
    buf = buf.slice(idx + 1);
    if (!line) continue;
    let msg;
    try { msg = JSON.parse(line); } catch { if (process.env.VERBOSE) console.error("NONJSON:", line.slice(0, 200)); continue; }
    if (msg.id && pending.has(msg.id)) {
      const p = pending.get(msg.id); pending.delete(msg.id);
      if (msg.error) p.rej(new Error(msg.error.message || JSON.stringify(msg.error))); else p.res(msg.result);
    }
  }
});

async function main() {
  process.stderr.write("STAGE start\n");
  process.stderr.write("STAGE sending initialize\n");
  const init = await send("initialize", { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "dsh-fallback", version: "1.0" } });
  notify("notifications/initialized", {});
  process.stderr.write("STAGE initialized\n");
  const list = await send("tools/list", {});
  const names = (list.tools || []).map(t => t.name);
  process.stderr.write("STAGE got init " + JSON.stringify(init.serverInfo) + "\n");
  console.log("INIT", JSON.stringify(init.serverInfo || {}));
  console.log("TOOLS", names.join(","));
  process.stderr.write("STAGE got tools " + names.length + "\n");
  const callName = process.argv[2] || "session_manage";
  const callArgs = JSON.parse(process.argv[3] || '{"op":"list"}');
  const r = await send("tools/call", { name: callName, arguments: callArgs });
  console.log("RESULT " + JSON.stringify(r).slice(0, 4000));
  process.stderr.write("STAGE got result\n");
  child.stdin.end();
  setTimeout(() => { child.kill(); process.exit(0); }, 300);
}
setTimeout(() => { console.error("TIMEOUT"); child.kill(); process.exit(2); }, 60000);
main().catch(e => { console.error("ERR", e.message); child.kill(); process.exit(3); });
