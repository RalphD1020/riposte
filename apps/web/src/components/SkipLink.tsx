/**
 * Skip-to-content link for keyboard and assistive-technology users.
 *
 * @see ../../../../docs/concepts/ux.md
 */

import { SiteCopy } from "@/content/site";

export function SkipLink() {
  return (
    <a href="#main-content" className="skip-link">
      {SiteCopy.skipToContent}
    </a>
  );
}
