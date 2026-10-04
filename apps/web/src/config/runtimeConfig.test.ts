import { afterEach, describe, expect, it, vi } from "vitest";
import {
  DEFAULT_LOCAL_PLAY_URL,
  getRuntimeConfig,
  hostnameFromHostHeader,
  isLocalHost,
  readRuntimeConfig,
  resolveLocalDestination,
  resolvePlayAdmission,
  resolvePublicDestination,
} from "./runtimeConfig";

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("destinations", () => {
  it("accept only https for public destinations", () => {
    expect(resolvePublicDestination("https://stub.itch.io/riposte")).toEqual({
      status: "configured",
      href: "https://stub.itch.io/riposte",
    });
    expect(resolvePublicDestination("http://insecure.example/")).toEqual({
      status: "unconfigured",
    });
    expect(resolvePublicDestination("/play-elsewhere")).toEqual({
      status: "unconfigured",
    });
    expect(resolvePublicDestination("javascript:alert(1)")).toEqual({
      status: "unconfigured",
    });
    expect(resolvePublicDestination("not a url")).toEqual({
      status: "unconfigured",
    });
    expect(resolvePublicDestination("   ")).toEqual({ status: "unconfigured" });
    expect(resolvePublicDestination(undefined)).toEqual({
      status: "unconfigured",
    });
  });

  it("let local play use loopback http or a same-origin path, never a loop", () => {
    expect(resolveLocalDestination("http://127.0.0.1:8060/")).toEqual({
      status: "configured",
      href: "http://127.0.0.1:8060/",
    });
    expect(resolveLocalDestination("/game-build/")).toEqual({
      status: "configured",
      href: "/game-build/",
    });
    expect(resolveLocalDestination("//evil.example/")).toEqual({
      status: "unconfigured",
    });
    expect(resolveLocalDestination("/play")).toEqual({
      status: "unconfigured",
    });
    expect(resolveLocalDestination("ftp://127.0.0.1/")).toEqual({
      status: "unconfigured",
    });
  });
});

describe("hosts", () => {
  it("strip ports and IPv6 brackets from Host headers", () => {
    expect(hostnameFromHostHeader("riposte.example:3000")).toBe(
      "riposte.example",
    );
    expect(hostnameFromHostHeader("[::1]:3000")).toBe("::1");
    expect(hostnameFromHostHeader("[::1")).toBe("[::1");
    expect(hostnameFromHostHeader(" localhost ")).toBe("localhost");
    expect(hostnameFromHostHeader(null)).toBe("");
  });

  it("recognize loopback hosts only", () => {
    expect(isLocalHost("localhost")).toBe(true);
    expect(isLocalHost("127.0.0.1")).toBe(true);
    expect(isLocalHost("::1")).toBe(true);
    expect(isLocalHost("[::1]")).toBe(true);
    expect(isLocalHost("riposte.example")).toBe(false);
    expect(isLocalHost("localhost.riposte.example")).toBe(false);
  });
});

describe("play admission", () => {
  const config = readRuntimeConfig({
    NEXT_PUBLIC_PLAY_URL: "https://stub.itch.io/riposte",
  });

  it("sends loopback hosts to the local Godot export", () => {
    expect(resolvePlayAdmission("localhost", config)).toEqual({
      surface: "local",
      destination: { status: "configured", href: DEFAULT_LOCAL_PLAY_URL },
    });
  });

  it("sends every other host to the public itch page", () => {
    expect(resolvePlayAdmission("riposte.example", config)).toEqual({
      surface: "public",
      destination: {
        status: "configured",
        href: "https://stub.itch.io/riposte",
      },
    });
  });
});

describe("runtime config", () => {
  it("defaults to the local serve, version 0.0.0, and unconfigured stubs", () => {
    expect(readRuntimeConfig({})).toEqual({
      releaseVersion: "0.0.0",
      localPlay: { status: "configured", href: DEFAULT_LOCAL_PLAY_URL },
      publicPlay: { status: "unconfigured" },
      community: { status: "unconfigured" },
      support: { status: "unconfigured" },
    });
  });

  it("reads each public variable from the environment", () => {
    vi.stubEnv("NEXT_PUBLIC_APP_VERSION", "1.2.3");
    vi.stubEnv("NEXT_PUBLIC_LOCAL_PLAY_URL", "http://localhost:9000/");
    vi.stubEnv("NEXT_PUBLIC_PLAY_URL", "https://stub.itch.io/riposte");
    vi.stubEnv("NEXT_PUBLIC_COMMUNITY_URL", "https://discord.example/invite");
    vi.stubEnv("NEXT_PUBLIC_SUPPORT_URL", "https://patreon.example/riposte");
    expect(getRuntimeConfig()).toEqual({
      releaseVersion: "1.2.3",
      localPlay: { status: "configured", href: "http://localhost:9000/" },
      publicPlay: {
        status: "configured",
        href: "https://stub.itch.io/riposte",
      },
      community: {
        status: "configured",
        href: "https://discord.example/invite",
      },
      support: {
        status: "configured",
        href: "https://patreon.example/riposte",
      },
    });
  });
});
