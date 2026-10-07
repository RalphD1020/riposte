/**
 * Landing page: one primary action (Play Riposte), what the game is, how to
 * learn it, and the community stubs.
 *
 * @see ../../../../docs/concepts/web.md
 * @see ../../../../docs/concepts/ux.md
 */

import Link from "next/link";
import { CommunityCtas } from "@/components/CommunityCtas";
import { PlayCta } from "@/components/PlayCta";
import { getRuntimeConfig } from "@/config/runtimeConfig";
import { SiteCopy, SiteName, SitePath } from "@/content/site";

export function HomePage() {
  const { community, support, publicPlay } = getRuntimeConfig();
  return (
    <div className="hero">
      <h1 className="hero__title">{SiteName}</h1>
      <p className="hero__tagline">{SiteCopy.tagline}</p>
      <p className="page__lede">{SiteCopy.homeLead}</p>
      <div className="hero__actions">
        <PlayCta />
        <Link className="secondary-button" href={SitePath.howToPlay}>
          {SiteCopy.howToPlay}
        </Link>
      </div>
      <CommunityCtas
        community={community}
        support={support}
        itch={publicPlay}
      />
    </div>
  );
}
