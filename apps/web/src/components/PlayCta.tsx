/**
 * Play control. Always a full navigation to `/play`, where play admission
 * decides the destination (proxy in server mode, PlayGateway in static
 * exports), so this component never inspects hosts or configuration.
 *
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
