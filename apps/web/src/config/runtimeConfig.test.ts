import { readFileSync } from "node:fs";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  DEFAULT_LOCAL_PLAY_URL,
  HOSTED_PLAY_PATH,
  getRuntimeConfig,
  readRuntimeConfig,
  resolveLocalDestination,
  resolvePlaySurface,
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

describe("play surface", () => {
  const hosted = { status: "configured", href: HOSTED_PLAY_PATH } as const;
  const itch = {
    status: "configured",
    href: "https://stub.itch.io/riposte",
  } as const;
  const local = { status: "configured", href: DEFAULT_LOCAL_PLAY_URL } as const;
  const none = { status: "unconfigured" } as const;

  it("prefers the export served from this origin over anywhere else", () => {
    expect(
      resolvePlaySurface({
        hostedPlay: hosted,
        publicPlay: itch,
        localPlay: local,
      }),
    ).toEqual({ surface: "hosted", destination: hosted });
  });

  it("falls back to the published itch build, then to the local serve", () => {
    expect(
      resolvePlaySurface({
        hostedPlay: none,
        publicPlay: itch,
        localPlay: local,
      }),
    ).toEqual({ surface: "itch", destination: itch });
    expect(
      resolvePlaySurface({
        hostedPlay: none,
        publicPlay: none,
        localPlay: local,
      }),
    ).toEqual({ surface: "local", destination: local });
  });

  it("reports unpublished rather than inventing somewhere to send people", () => {
    expect(
      resolvePlaySurface({
        hostedPlay: none,
        publicPlay: none,
        localPlay: none,
      }),
    ).toEqual({ surface: "unpublished", destination: none });
  });
});

/**
 * `next.config.ts` runs before the app's module aliases exist, so it repeats
 * one thing this module owns, and it is the only place the hosting contract
 * for the staged export is stated (WEB-004).
 *
 * The header assertions load the real config and read the values it would
 * actually send. Asserting the source text instead would pass on a policy
 * that had been refactored into a shared constant and quietly widened.
 */
describe("the hosting contract in next.config.ts", () => {
  const source = readFileSync("./next.config.ts", "utf-8");

  async function headerValue(
    source_: string,
    key: string,
  ): Promise<string | undefined> {
    const config = (await import("../../next.config")).default;
    const groups = (await config.headers?.()) ?? [];
    return groups
      .find((group) => group.source === source_)
      ?.headers.find((header) => header.key === key)?.value;
  }

  it("rewrites /play to the path this module resolves", () => {
    expect(source).toContain(`const HOSTED_PLAY_PATH = "${HOSTED_PLAY_PATH}"`);
  });

  /**
   * A bare rewrite array is `afterFiles`, which loses to the `/play` page
   * that exists as the fallback — so the rewrite would silently never fire.
   * Whether it is populated depends on a staged artifact, which a test must
   * not require; that it is in the right bucket does not.
   */
  it("puts the rewrite before the page it is meant to replace", () => {
    expect(source).toContain("beforeFiles: hasStagedGame");
  });

  it("grants wasm and worker capabilities to /game and to nothing else", async () => {
    const site = await headerValue("/(.*)", "Content-Security-Policy");
    const game = await headerValue("/game/:path*", "Content-Security-Policy");
    expect(site).not.toContain("wasm-unsafe-eval");
    expect(site).not.toContain("worker-src");
    expect(game).toContain("'wasm-unsafe-eval'");
    expect(game).toContain("worker-src 'self' blob:");
    expect(game).not.toContain("'unsafe-eval'");
  });

  /** Both policies must keep every protection the site has. */
  it("hardens /game exactly as much as the rest of the site", async () => {
    const site = await headerValue("/(.*)", "Content-Security-Policy");
    const game = await headerValue("/game/:path*", "Content-Security-Policy");
    for (const directive of (site ?? "").split("; ")) {
      const name = directive.split(" ")[0];
      expect(game, `${name} is missing from the game policy`).toContain(name);
    }
    expect(game).toContain("frame-ancestors 'none'");
  });

  it("keeps the engine shell out of any cache", async () => {
    expect(await headerValue(HOSTED_PLAY_PATH, "Cache-Control")).toBe(
      "no-cache",
    );
  });
});

describe("runtime config", () => {
  it("defaults to the local serve, version 0.0.0, and unconfigured stubs", () => {
    expect(readRuntimeConfig({})).toEqual({
      releaseVersion: "0.0.0",
      hostedPlay: { status: "unconfigured" },
      localPlay: { status: "configured", href: DEFAULT_LOCAL_PLAY_URL },
      publicPlay: { status: "unconfigured" },
      community: { status: "unconfigured" },
      support: { status: "unconfigured" },
    });
  });

  it("reads each public variable from the environment", () => {
    vi.stubEnv("NEXT_PUBLIC_APP_VERSION", "1.2.3");
    vi.stubEnv("NEXT_PUBLIC_HOSTED_PLAY", HOSTED_PLAY_PATH);
    vi.stubEnv("NEXT_PUBLIC_LOCAL_PLAY_URL", "http://localhost:9000/");
    vi.stubEnv("NEXT_PUBLIC_PLAY_URL", "https://stub.itch.io/riposte");
    vi.stubEnv("NEXT_PUBLIC_COMMUNITY_URL", "https://discord.example/invite");
    vi.stubEnv("NEXT_PUBLIC_SUPPORT_URL", "https://patreon.example/riposte");
    expect(getRuntimeConfig()).toEqual({
      releaseVersion: "1.2.3",
      hostedPlay: { status: "configured", href: HOSTED_PLAY_PATH },
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
