/**
 * The one module that reads deployment configuration
 * (`process.env.NEXT_PUBLIC_*`). Everything else consumes
 * `getRuntimeConfig()` and `resolvePlayAdmission()`.
 *
 * Play admission (WEB-005):
 *   - localhost / 127.0.0.1 / ::1 → the standalone Godot Web export
 *     (`http://127.0.0.1:8060/` unless NEXT_PUBLIC_LOCAL_PLAY_URL says otherwise)
 *   - any other host → NEXT_PUBLIC_PLAY_URL (the itch.io page) once
 *     published; unconfigured until then
 *
 * Components never branch on hosts; they receive a resolved Destination.
 * Destinations are validated: public URLs must be https, local ones may be
 * http(s) or a same-origin path, and anything else is unconfigured.
 *
 * Implements: spec/invariants.md#web-005, spec/invariants.md#web-006
 *
 * @see ../proxy.ts
 * @see ../components/PlayGateway.tsx
 * @see ../../../../docs/concepts/web.md
 * @see ../../../../docs/architecture/SECURITY.md
 */

import { SitePath } from "@/content/site";

export type Destination =
  | { readonly status: "configured"; readonly href: string }
  | { readonly status: "unconfigured" };

export type PlaySurface = "local" | "public";

export interface PlayAdmission {
  readonly surface: PlaySurface;
  readonly destination: Destination;
}

export interface RuntimeConfig {
  readonly releaseVersion: string;
  readonly localPlay: Destination;
  readonly publicPlay: Destination;
  readonly community: Destination;
  readonly support: Destination;
}

export interface RuntimeEnv {
  readonly NEXT_PUBLIC_APP_VERSION?: string;
  readonly NEXT_PUBLIC_LOCAL_PLAY_URL?: string;
  readonly NEXT_PUBLIC_PLAY_URL?: string;
  readonly NEXT_PUBLIC_COMMUNITY_URL?: string;
  readonly NEXT_PUBLIC_SUPPORT_URL?: string;
}

export const DEFAULT_LOCAL_PLAY_URL = "http://127.0.0.1:8060/";
const DEFAULT_RELEASE_VERSION = "0.0.0";
const LOCAL_HOSTS = new Set(["localhost", "127.0.0.1", "::1"]);
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

/** `example.com:3000` → `example.com`; `[::1]:3000` → `::1`. */
export function hostnameFromHostHeader(
  host: string | null | undefined,
): string {
  const trimmed = host?.trim() ?? "";
  if (trimmed.startsWith("[")) {
    const end = trimmed.indexOf("]");
    return end === -1 ? trimmed : trimmed.slice(1, end);
  }
  const colon = trimmed.indexOf(":");
  return colon === -1 ? trimmed : trimmed.slice(0, colon);
}

export function isLocalHost(hostname: string): boolean {
  return LOCAL_HOSTS.has(hostname.replace(/^\[(.*)\]$/, "$1"));
}

export function resolvePlayAdmission(
  hostname: string,
  config: Pick<RuntimeConfig, "localPlay" | "publicPlay">,
): PlayAdmission {
  return isLocalHost(hostname)
    ? { surface: "local", destination: config.localPlay }
    : { surface: "public", destination: config.publicPlay };
}

export function readRuntimeConfig(env: RuntimeEnv): RuntimeConfig {
  const local = env.NEXT_PUBLIC_LOCAL_PLAY_URL?.trim() ?? "";
  const version = env.NEXT_PUBLIC_APP_VERSION?.trim() ?? "";
  return {
    releaseVersion: version === "" ? DEFAULT_RELEASE_VERSION : version,
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
    NEXT_PUBLIC_LOCAL_PLAY_URL: process.env.NEXT_PUBLIC_LOCAL_PLAY_URL,
    NEXT_PUBLIC_PLAY_URL: process.env.NEXT_PUBLIC_PLAY_URL,
    NEXT_PUBLIC_COMMUNITY_URL: process.env.NEXT_PUBLIC_COMMUNITY_URL,
    NEXT_PUBLIC_SUPPORT_URL: process.env.NEXT_PUBLIC_SUPPORT_URL,
  });
}
