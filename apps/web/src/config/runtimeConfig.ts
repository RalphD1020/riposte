/**
 * The one module that reads deployment configuration
 * (`process.env.NEXT_PUBLIC_*`). Everything else consumes
 * `getRuntimeConfig()` and `resolvePlaySurface()`.
 *
 * Play admission (WEB-005) resolves a **surface**, in this order:
 *   1. `hosted` — the Godot Web export staged into `public/game/`, served
 *      from this origin at `/play`. The real answer.
 *   2. `itch` — `NEXT_PUBLIC_PLAY_URL`, the published itch.io page. A
 *      secondary home, not the front door.
 *   3. `local` — `NEXT_PUBLIC_LOCAL_PLAY_URL` (default
 *      `http://127.0.0.1:8060/`), the pre-publish development loop.
 *
 * Hostname does not appear. It used to: `/play` was a redirect, so the site
 * had to guess which build a visitor could reach from where they were
 * standing. Now the game is on this origin, and whether it is there is a fact
 * about the deployment rather than about the visitor.
 *
 * Components never branch on hosts or on itch; they receive a resolved
 * Destination. Destinations are validated: public URLs must be https, local
 * ones may be http(s) or a same-origin path, and anything else is
 * unconfigured.
 *
 * Implements: spec/invariants.md#web-005, spec/invariants.md#web-006
 *
 * @see ../components/PlayGateway.tsx
 * @see ../../../../docs/concepts/web.md
 * @see ../../../../docs/architecture/SECURITY.md
 */

import { SitePath } from "@/content/site";

export type Destination =
  | { readonly status: "configured"; readonly href: string }
  | { readonly status: "unconfigured" };

export type PlaySurface = "hosted" | "itch" | "local" | "unpublished";

export interface PlayAdmission {
  readonly surface: PlaySurface;
  readonly destination: Destination;
}

export interface RuntimeConfig {
  readonly releaseVersion: string;
  /** The staged export on this origin, when the build has one. */
  readonly hostedPlay: Destination;
  readonly localPlay: Destination;
  readonly publicPlay: Destination;
  readonly community: Destination;
  readonly support: Destination;
}

export interface RuntimeEnv {
  readonly NEXT_PUBLIC_APP_VERSION?: string;
  readonly NEXT_PUBLIC_HOSTED_PLAY?: string;
  readonly NEXT_PUBLIC_LOCAL_PLAY_URL?: string;
  readonly NEXT_PUBLIC_PLAY_URL?: string;
  readonly NEXT_PUBLIC_COMMUNITY_URL?: string;
  readonly NEXT_PUBLIC_SUPPORT_URL?: string;
}

export const DEFAULT_LOCAL_PLAY_URL = "http://127.0.0.1:8060/";
/**
 * Where the staged export lives on this origin. `/play` rewrites here on the
 * server build; static exports navigate to it.
 */
export const HOSTED_PLAY_PATH = "/game/index.html";
const DEFAULT_RELEASE_VERSION = "0.0.0";
const UNCONFIGURED: Destination = { status: "unconfigured" };

function parseDestination(
  value: string | undefined,
  options: { readonly allowHttp: boolean; readonly allowPath: boolean },
): Destination {
  const href = value?.trim() ?? "";
  if (href === "" || href === SitePath.play) return UNCONFIGURED;
  if (href.startsWith("/")) {
    return options.allowPath && !href.startsWith("//")
      ? { status: "configured", href }
      : UNCONFIGURED;
  }
  if (!URL.canParse(href)) return UNCONFIGURED;
  const url = new URL(href);
  const allowed =
    url.protocol === "https:" ||
    (options.allowHttp && url.protocol === "http:");
  return allowed ? { status: "configured", href: url.href } : UNCONFIGURED;
}

/** Public destinations (itch page, community, support): https only. */
export function resolvePublicDestination(
  value: string | undefined,
): Destination {
  return parseDestination(value, { allowHttp: false, allowPath: false });
}

/** Local play: the loopback Godot serve over http(s), or a same-origin path. */
export function resolveLocalDestination(
  value: string | undefined,
): Destination {
  return parseDestination(value, { allowHttp: true, allowPath: true });
}

/**
 * Which surface `/play` should use. `hosted` is a fact established at build
 * time by the staging step, not something the browser can discover, so it
 * arrives as an argument rather than being probed here.
 */
export function resolvePlaySurface(
  config: Pick<RuntimeConfig, "hostedPlay" | "localPlay" | "publicPlay">,
): PlayAdmission {
  if (config.hostedPlay.status === "configured") {
    return { surface: "hosted", destination: config.hostedPlay };
  }
  if (config.publicPlay.status === "configured") {
    return { surface: "itch", destination: config.publicPlay };
  }
  if (config.localPlay.status === "configured") {
    return { surface: "local", destination: config.localPlay };
  }
  return { surface: "unpublished", destination: UNCONFIGURED };
}

export function readRuntimeConfig(env: RuntimeEnv): RuntimeConfig {
  const local = env.NEXT_PUBLIC_LOCAL_PLAY_URL?.trim() ?? "";
  const version = env.NEXT_PUBLIC_APP_VERSION?.trim() ?? "";
  return {
    releaseVersion: version === "" ? DEFAULT_RELEASE_VERSION : version,
    hostedPlay: resolveLocalDestination(env.NEXT_PUBLIC_HOSTED_PLAY),
    localPlay: resolveLocalDestination(
      local === "" ? DEFAULT_LOCAL_PLAY_URL : local,
    ),
    publicPlay: resolvePublicDestination(env.NEXT_PUBLIC_PLAY_URL),
    community: resolvePublicDestination(env.NEXT_PUBLIC_COMMUNITY_URL),
    support: resolvePublicDestination(env.NEXT_PUBLIC_SUPPORT_URL),
  };
}

/**
 * Next.js inlines `NEXT_PUBLIC_*` only for literal `process.env.NAME`
 * reads, so each variable is named here explicitly.
 */
export function getRuntimeConfig(): RuntimeConfig {
  return readRuntimeConfig({
    NEXT_PUBLIC_APP_VERSION: process.env.NEXT_PUBLIC_APP_VERSION,
    NEXT_PUBLIC_HOSTED_PLAY: process.env.NEXT_PUBLIC_HOSTED_PLAY,
    NEXT_PUBLIC_LOCAL_PLAY_URL: process.env.NEXT_PUBLIC_LOCAL_PLAY_URL,
    NEXT_PUBLIC_PLAY_URL: process.env.NEXT_PUBLIC_PLAY_URL,
    NEXT_PUBLIC_COMMUNITY_URL: process.env.NEXT_PUBLIC_COMMUNITY_URL,
    NEXT_PUBLIC_SUPPORT_URL: process.env.NEXT_PUBLIC_SUPPORT_URL,
  });
}
