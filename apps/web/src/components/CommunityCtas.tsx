/**
 * Purpose-named community destinations, shown as Discord (community) and
 * Patreon (support). An unconfigured destination renders a disabled
 * "Coming soon" stub; never an invented URL (WEB-006).
 *
 * @see ../../../../spec/invariants.md — WEB-006
 * @see ../../../../docs/concepts/web.md
 */

import type { Destination } from "@/config/runtimeConfig";
import { SiteCopy } from "@/content/site";

function CommunityCta({
  destination,
  label,
}: {
  readonly destination: Destination;
  readonly label: string;
}) {
  if (destination.status === "unconfigured") {
    return (
      <button
        type="button"
        className="community-cta"
        aria-disabled="true"
        aria-label={`${label}. ${SiteCopy.comingSoon}`}
      >
        <span>{label}</span>
        <span className="stub-badge">{SiteCopy.comingSoon}</span>
      </button>
    );
  }
  return (
    <a
      className="community-cta"
      href={destination.href}
      target="_blank"
      rel="noopener noreferrer"
      aria-label={`${label} ${SiteCopy.opensInNewTab}`}
    >
      <span>{label}</span>
      <span aria-hidden="true">↗</span>
    </a>
  );
}

export function CommunityCtas({
  community,
  support,
}: {
  readonly community: Destination;
  readonly support: Destination;
}) {
  return (
    <section className="community-ctas" aria-labelledby="community-heading">
      <h2 id="community-heading" className="section-title">
        {SiteCopy.community}
      </h2>
      <div className="community-ctas__row">
        <CommunityCta destination={community} label={SiteCopy.discord} />
        <CommunityCta destination={support} label={SiteCopy.patreon} />
      </div>
    </section>
  );
}
