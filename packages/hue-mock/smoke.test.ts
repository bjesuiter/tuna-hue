import { expect, test } from "bun:test";
import { readFile } from "node:fs/promises";
import { createInterface } from "node:readline";
import { Readable } from "node:stream";
import { fileURLToPath } from "node:url";

test("serves Hue discovery, pairing, and power updates over HTTPS", async () => {
  const server = Bun.spawn([process.execPath, fileURLToPath(new URL("./server.ts", import.meta.url))], {
    env: { ...process.env, MOCK_HUE_PORT: "0" },
    stdout: "pipe",
    stderr: "inherit",
  });
  const lines = createInterface({ input: Readable.fromWeb(server.stdout) });
  const startup = setTimeout(() => server.kill(), 5_000);
  try {
    let address = "";
    let caPath = "";
    for await (const line of lines) {
      if (line.startsWith("Mock Hue bridge listening at ")) address = line.split(" ").at(-1)!;
      if (line.startsWith("CA PEM: ")) caPath = line.slice("CA PEM: ".length);
      if (address && caPath) break;
    }
    clearTimeout(startup);
    expect(address).toMatch(/^https:\/\/127\.0\.0\.1:\d+$/);
    expect(caPath).not.toBe("");
    const ca = await readFile(caPath, "utf8");
    const request = (path: string, options: RequestInit = {}) =>
      fetch(new URL(path, address), { ...options, tls: { ca }, signal: AbortSignal.timeout(3_000) });

    const discovery = await request("/__mock/discovery");
    expect(await discovery.json()).toEqual([{ id: "001788fffe000001", internalipaddress: "127.0.0.1" }]);

    const pending = await request("/api", { method: "POST" });
    expect((await pending.json())[0].error.type).toBe(101);
    expect((await request("/__mock/link-button", { method: "POST" })).status).toBe(204);
    const paired = await request("/api", { method: "POST" });
    const key = (await paired.json())[0].success.username;
    expect(key).toBe("tuna-hue-demo-key");

    const resources = "/clip/v2/resource";
    const headers = { "hue-application-key": key };
    expect((await request(`${resources}/room`)).status).toBe(403);
    const rooms = await (await request(`${resources}/room`, { headers })).json();
    expect(rooms.data.map((room: { metadata: { name: string } }) => room.metadata.name))
      .toEqual(["Bedroom", "Living Room", "Kitchen"]);
    const connectivity = await (await request(`${resources}/zigbee_connectivity`, { headers })).json();
    expect(connectivity.data.map(({ status }: { status: string }) => status))
      .toEqual(["connected", "connected", "disconnected"]);

    const group = rooms.data[0].services[0].rid;
    const power = () => request(`${resources}/grouped_light`, { headers }).then((response) => response.json());
    expect((await power()).data.find(({ id }: { id: string }) => id === group).on.on).toBe(false);
    expect((await request(`${resources}/grouped_light/${group}`, {
      method: "PUT",
      headers: { ...headers, "content-type": "application/json" },
      body: JSON.stringify({ on: { on: true } }),
    })).ok).toBe(true);
    expect((await power()).data.find(({ id }: { id: string }) => id === group).on.on).toBe(true);
  } finally {
    clearTimeout(startup);
    lines.close();
    server.kill();
    await server.exited;
  }
}, 15_000);
