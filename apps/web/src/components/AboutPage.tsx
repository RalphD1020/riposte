/**
 * About: what Riposte is, what this release contains, and where it runs.
 *
 * @see ../../../../docs/concepts/web.md
 * @see ../../../../docs/concepts/game.md
 */

import { PlayCta } from "@/components/PlayCta";
import { SiteCopy } from "@/content/site";

export function AboutPage() {
  return (
    <div className="page">
      <h1 className="page__title">{SiteCopy.about}</h1>
      <p className="page__lede">{SiteCopy.aboutLead}</p>
      <p className="page__body">{SiteCopy.aboutBody}</p>
      <p className="page__body">{SiteCopy.aboutPlatform}</p>
      <PlayCta />
    </div>
  );
}
