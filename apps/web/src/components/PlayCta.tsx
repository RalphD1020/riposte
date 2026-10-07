/**
 * Play control. Always a plain anchor to `/play` — a full navigation, not a
 * client-side route change, because on the server build `/play` is a rewrite
 * to the staged export and a router transition would never reach it.
 *
 * `/play` resolves the destination; this component never inspects hosts or
 * configuration, so there is exactly one place admission is decided.
 *
 * @see ../config/runtimeConfig.ts — resolvePlaySurface
 * @see ../../../../docs/concepts/web.md
 * @see ../../../../spec/invariants.md — WEB-005
 */

import { SiteCopy, SitePath } from "@/content/site";

export function PlayCta({
  variant = "hero",
}: {
  readonly variant?: "hero" | "nav";
}) {
  return (
    <a
      className={variant === "nav" ? "site-nav__play" : "primary-button"}
      href={SitePath.play}
    >
      {variant === "nav" ? SiteCopy.play : SiteCopy.playCta}
    </a>
  );
}
