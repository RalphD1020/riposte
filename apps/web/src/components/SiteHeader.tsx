/**
 * Site masthead: wordmark and primary navigation, framed in Dark Steel Gray.
 * Static (no request data) so it renders identically in static exports.
 *
 * @see ../../../../docs/concepts/ux.md
 * @see ../../../../docs/concepts/web.md
 */

import Link from "next/link";
import { PlayCta } from "@/components/PlayCta";
import { SiteCopy, SiteName, SitePath } from "@/content/site";

export function SiteHeader() {
  return (
    <header className="site-header">
      <Link href={SitePath.home} className="site-wordmark">
        {SiteName}
      </Link>
      <nav className="site-nav" aria-label={SiteCopy.primaryNav}>
        <Link href={SitePath.howToPlay} className="site-nav__link">
          {SiteCopy.howToPlay}
        </Link>
        <Link href={SitePath.about} className="site-nav__link">
          {SiteCopy.about}
        </Link>
        <PlayCta variant="nav" />
      </nav>
    </header>
  );
}
