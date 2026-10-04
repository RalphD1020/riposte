/**
 * Root document shell. Semantic landmarks live here; pages supply titles.
 *
 * @see ../../../../docs/concepts/web.md
 * @see ../../../../docs/concepts/ux.md
 */

import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import { SiteFooter } from "@/components/SiteFooter";
import { SiteHeader } from "@/components/SiteHeader";
import { SkipLink } from "@/components/SkipLink";
import { SiteCopy, SiteName, SiteTheme } from "@/content/site";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: SiteName,
    template: `%s · ${SiteName}`,
  },
  description: SiteCopy.description,
  icons: {
    icon: "/favicon.svg",
  },
  manifest: "/site.webmanifest",
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: SiteTheme.themeColor,
  colorScheme: "light",
};

export default function RootLayout({
  children,
}: {
  readonly children: ReactNode;
}) {
  return (
    <html lang="en">
      <body>
        <div className="site-shell">
          <SkipLink />
          <SiteHeader />
          <main id="main-content" className="site-main" tabIndex={-1}>
            {children}
          </main>
          <SiteFooter />
        </div>
      </body>
    </html>
  );
}
