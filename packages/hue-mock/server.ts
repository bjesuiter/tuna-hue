import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const bridgeID = "001788fffe000001";
const key = "tuna-hue-demo-key";
const port = Number(process.env.MOCK_HUE_PORT ?? 443);
if (!Number.isInteger(port) || port < 0 || port > 65535) {
  throw new Error("MOCK_HUE_PORT must be an integer from 0 to 65535");
}

const rooms = [
  { name: "Bedroom", on: false, offline: false },
  { name: "Living Room", on: true, offline: false },
  { name: "Kitchen", on: false, offline: true },
].map((room, index) => {
  const id = (resource: number) =>
    `00000000-0000-4000-8000-${String((index + 1) * 10 + resource).padStart(12, "0")}`;
  return { ...room, id: id(0), group: id(1), light: id(2), device: id(3) };
});

const resources = "/clip/v2/resource/";
const service = (rid: string, rtype: string) => ({ rid, rtype });
const envelope = (data: unknown[]) => Response.json({ errors: [], data });
let linkButtonPressed = false;

async function handleRequest(request: Request): Promise<Response> {
  const { pathname } = new URL(request.url);
  const { method } = request;

  if (method === "GET" && pathname === "/__mock/discovery") {
    return Response.json([{ id: bridgeID, internalipaddress: "127.0.0.1" }]);
  }
  if (method === "GET" && pathname === "/api/config") {
    return Response.json({ name: "Demo Hue Bridge", bridgeid: bridgeID.toUpperCase() });
  }
  if (method === "POST" && pathname === "/__mock/link-button") {
    linkButtonPressed = true;
    return new Response(null, { status: 204 });
  }
  if (method === "POST" && pathname === "/api") {
    const pressed = linkButtonPressed;
    linkButtonPressed = false;
    return Response.json(pressed
      ? [{ success: { username: key } }]
      : [{ error: { type: 101, address: "", description: "link button not pressed" } }]);
  }
  if (!pathname.startsWith(resources)) {
    return new Response(null, { status: 404 });
  }
  if (request.headers.get("hue-application-key") !== key) {
    return new Response(null, { status: 403 });
  }

  const resource = pathname.slice(resources.length);
  if (method === "GET") {
    switch (resource) {
      case "room":
        return envelope(rooms.map((room) => ({
          id: room.id,
          metadata: { name: room.name },
          children: [service(room.device, "device")],
          services: [service(room.group, "grouped_light")],
        })));
      case "zone":
        return envelope([]);
      case "grouped_light":
        return envelope(rooms.map((room) => ({ id: room.group, on: { on: room.on } })));
      case "light":
        return envelope(rooms.map((room) => ({ id: room.light, owner: service(room.device, "device") })));
      case "zigbee_connectivity":
        return envelope(rooms.map((room) => ({
          owner: service(room.device, "device"),
          status: room.offline ? "disconnected" : "connected",
        })));
    }
  }

  if (method === "PUT" && resource.startsWith("grouped_light/")) {
    const room = rooms.find((room) => resource === `grouped_light/${room.group}`);
    if (!room) return new Response(null, { status: 404 });
    const payload = await request.json().catch(() => null) as { on?: { on?: unknown } } | null;
    const on = payload?.on?.on;
    if (typeof on !== "boolean") return new Response(null, { status: 400 });
    room.on = on;
    return envelope([service(room.group, "grouped_light")]);
  }

  return new Response(null, { status: 404 });
}

const tlsDir = mkdtempSync(join(tmpdir(), "tuna-hue-mock-"));
const file = (name: string) => join(tlsDir, name);
function openssl(...args: string[]) {
  const result = Bun.spawnSync(["openssl", ...args], { cwd: tlsDir, stderr: "pipe" });
  if (result.exitCode !== 0) throw new Error(result.stderr.toString().trim());
}

try {
  // The extension checks the CA chain and expects the bridge ID in the leaf's common name.
  writeFileSync(file("ca.cnf"), `[req]
prompt = no
distinguished_name = subject
x509_extensions = ca
[subject]
CN = Tuna Hue Demo CA
[ca]
basicConstraints = critical,CA:true
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
`);
  writeFileSync(file("bridge.ext"), `basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = IP:127.0.0.1,DNS:localhost,DNS:hue-bridge.localhost
`);
  openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2",
    "-config", "ca.cnf", "-keyout", "ca.key", "-out", "ca.pem");
  openssl("req", "-newkey", "rsa:2048", "-nodes", "-subj", `/CN=${bridgeID}`,
    "-keyout", "bridge.key", "-out", "bridge.csr");
  openssl("x509", "-req", "-in", "bridge.csr", "-CA", "ca.pem", "-CAkey", "ca.key",
    "-CAcreateserial", "-days", "2", "-extfile", "bridge.ext", "-out", "bridge.pem");
  chmodSync(file("ca.key"), 0o600);
  chmodSync(file("bridge.key"), 0o600);
  chmodSync(file("ca.pem"), 0o644);
  chmodSync(tlsDir, 0o711);

  const server = Bun.serve({
    hostname: "127.0.0.1",
    port,
    tls: { key: readFileSync(file("bridge.key")), cert: readFileSync(file("bridge.pem")) },
    fetch: handleRequest,
  });
  const shutdown = () => {
    server.stop(true);
    rmSync(tlsDir, { recursive: true, force: true });
    process.exit(0);
  };
  process.once("SIGINT", shutdown);
  process.once("SIGTERM", shutdown);
  console.log(`Mock Hue bridge listening at https://127.0.0.1:${server.port}
Bridge ID: ${bridgeID}
CA PEM: ${file("ca.pem")}
Bridge certificate: ${file("bridge.pem")}
Bridge private key file: ${file("bridge.key")}
Application key: ${key}`);
} catch (error) {
  rmSync(tlsDir, { recursive: true, force: true });
  throw error;
}
