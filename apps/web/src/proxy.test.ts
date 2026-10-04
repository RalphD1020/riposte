import { afterEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";
import { SitePath } from "@/content/site";
import { config, proxy } from "./proxy";

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("proxy", () => {
  it("only guards the play route", () => {
    expect(config.matcher).toEqual([SitePath.play]);
  });

  it("admits loopback hosts to the standalone Godot export", () => {
    const response = proxy(new NextRequest("http://localhost:3000/play"));
    expect(response.status).toBe(307);
    expect(response.headers.get("location")).toBe("http://127.0.0.1:8060/");
    const ipv6 = proxy(
      new NextRequest("http://127.0.0.1:3000/play", {
        headers: { host: "[::1]:3000" },
      }),
    );
    expect(ipv6.headers.get("location")).toBe("http://127.0.0.1:8060/");
  });

  it("resolves a same-origin local destination against the request", () => {
    vi.stubEnv("NEXT_PUBLIC_LOCAL_PLAY_URL", "/game-build/");
    const response = proxy(new NextRequest("http://localhost:3000/play"));
    expect(response.headers.get("location")).toBe(
      "http://localhost:3000/game-build/",
    );
  });

  it("sends public hosts to the itch page once it is published", () => {
    vi.stubEnv("NEXT_PUBLIC_PLAY_URL", "https://stub.itch.io/riposte");
    const response = proxy(new NextRequest("https://riposte.example/play"));
    expect(response.status).toBe(307);
    expect(response.headers.get("location")).toBe(
      "https://stub.itch.io/riposte",
    );
  });

  it("keeps public hosts on /play while the itch page is unpublished", () => {
    const response = proxy(new NextRequest("https://riposte.example/play"));
    expect(response.status).toBe(200);
    expect(response.headers.get("location")).toBeNull();
  });

  it("trusts the Host header over the URL hostname", () => {
    const response = proxy(
      new NextRequest("http://127.0.0.1:3000/play", {
        headers: { host: "riposte.example" },
      }),
    );
    expect(response.status).toBe(200);
  });
});
