import { render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { SiteCopy, SiteName, SitePath } from "@/content/site";
import { PlayCta } from "./PlayCta";
import { SiteFooter } from "./SiteFooter";
import { SiteHeader } from "./SiteHeader";
import { SkipLink } from "./SkipLink";

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("site chrome", () => {
  it("skips straight to the main landmark", () => {
    render(<SkipLink />);
    expect(
      screen.getByRole("link", { name: SiteCopy.skipToContent }),
    ).toHaveAttribute("href", "#main-content");
  });

  it("names the primary navigation and routes Play through the gateway", () => {
    render(<SiteHeader />);
    expect(screen.getByRole("link", { name: SiteName })).toHaveAttribute(
      "href",
      SitePath.home,
    );
    const nav = screen.getByRole("navigation", { name: SiteCopy.primaryNav });
    expect(
      within(nav).getByRole("link", { name: SiteCopy.howToPlay }),
    ).toHaveAttribute("href", SitePath.howToPlay);
    expect(
      within(nav).getByRole("link", { name: SiteCopy.about }),
    ).toHaveAttribute("href", SitePath.about);
    expect(
      within(nav).getByRole("link", { name: SiteCopy.play }),
    ).toHaveAttribute("href", SitePath.play);
  });

  it("uses the hero label for the default Play control", () => {
    render(<PlayCta />);
    expect(screen.getByRole("link", { name: SiteCopy.playCta })).toHaveClass(
      "primary-button",
    );
  });

  it("shows the release version in the footer", () => {
    vi.stubEnv("NEXT_PUBLIC_APP_VERSION", "2.0.1");
    render(<SiteFooter />);
    expect(screen.getByRole("contentinfo")).toHaveTextContent(
      `${SiteName} · v2.0.1`,
    );
  });
});
