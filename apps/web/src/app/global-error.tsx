"use client";

/**
 * Root error boundary. Supplies html/body because the root layout is gone.
 *
 * @see ../../../../docs/concepts/ux.md
 * @see ../../../../docs/concepts/web.md
 */

import { ErrorRecovery } from "@/components/ErrorRecovery";
import { SkipLink } from "@/components/SkipLink";
import { SiteCopy, SiteName, SitePath } from "@/content/site";
import "./globals.css";

export default function GlobalError({
  retry,
}: {
  readonly error: Error & { digest?: string };
  readonly retry: () => void;
}) {
  return (
    <html lang="en">
      <head>
        <title>{SiteName}</title>
      </head>
      <body>
        <div className="site-shell">
          <SkipLink />
          <main id="main-content" className="site-main" tabIndex={-1}>
            <ErrorRecovery onRetry={retry} headingLevel="h1" />
            <a className="text-link" href={SitePath.home}>
              {SiteCopy.backHome}
            </a>
          </main>
        </div>
      </body>
    </html>
  );
}
