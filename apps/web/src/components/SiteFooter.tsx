/**
 * Site footer with the release version.
 *
 * @see ../../../../docs/concepts/ux.md
 */

import { getRuntimeConfig } from "@/config/runtimeConfig";
import { SiteName } from "@/content/site";

export function SiteFooter() {
  const { releaseVersion } = getRuntimeConfig();
  return (
    <footer className="site-footer">
      <p>
        {SiteName} · v{releaseVersion}
      </p>
    </footer>
  );
}
