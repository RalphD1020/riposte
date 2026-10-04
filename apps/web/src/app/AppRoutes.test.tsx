import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { AboutPage } from "@/components/AboutPage";
import { HomePage } from "@/components/HomePage";
import { HowToPlayPage } from "@/components/HowToPlayPage";
import { PlayGateway } from "@/components/PlayGateway";
import { PlayPage } from "@/components/PlayPage";
import { SiteCopy, SiteName, SitePath, SiteTheme } from "@/content/site";
import AboutRoute, { metadata as aboutMetadata } from "./about/page";
import RouteError from "./error";
import GlobalError from "./global-error";
import HowToPlayRoute, {
  metadata as howToPlayMetadata,
} from "./how-to-play/page";
import RootLayout, { metadata, viewport } from "./layout";
import NotFound, { metadata as notFoundMetadata } from "./not-found";
import Page from "./page";
import PlayRoute, { metadata as playMetadata } from "./play/page";

vi.mock("./globals.css", () => ({}));

describe("route modules", () => {
  it("wire each route to its view", () => {
    expect(Page().type).toBe(HomePage);
    expect(PlayRoute().type).toBe(PlayPage);
    expect(HowToPlayRoute().type).toBe(HowToPlayPage);
    expect(AboutRoute().type).toBe(AboutPage);
    expect(PlayPage().type).toBe(PlayGateway);
  });

  it("title every page and theme the browser chrome", () => {
    expect(metadata.title).toEqual({
      default: SiteName,
      template: `%s · ${SiteName}`,
    });
    expect(metadata.manifest).toBe("/site.webmanifest");
    expect(playMetadata.title).toBe(SiteCopy.play);
    expect(howToPlayMetadata.title).toBe(SiteCopy.howToPlay);
    expect(aboutMetadata.title).toBe(SiteCopy.about);
    expect(notFoundMetadata.title).toBe(SiteCopy.notFoundTitle);
    expect(viewport.themeColor).toBe(SiteTheme.themeColor);
    expect(viewport.viewportFit).toBe("cover");
  });

  it("lays out landmarks in reading order", () => {
    render(RootLayout({ children: <p>Child</p> }), { container: document });
    expect(
      screen.getByRole("link", { name: SiteCopy.skipToContent }),
    ).toHaveAttribute("href", "#main-content");
    expect(screen.getByRole("banner")).toBeInTheDocument();
    expect(screen.getByRole("main")).toHaveAttribute("id", "main-content");
    expect(screen.getByRole("contentinfo")).toBeInTheDocument();
    expect(screen.getByText("Child")).toBeInTheDocument();
  });

  it("recover from route and root errors", async () => {
    const user = userEvent.setup();
    const retry = vi.fn();
    const { unmount } = render(
      <RouteError
        error={Object.assign(new Error("boom"), { digest: "d1" })}
        retry={retry}
      />,
    );
    expect(screen.queryByText("boom")).not.toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: SiteCopy.tryAgain }));
    expect(retry).toHaveBeenCalledOnce();
    unmount();

    const rootRetry = vi.fn();
    render(
      <GlobalError
        error={Object.assign(new Error("root"), { digest: "d2" })}
        retry={rootRetry}
      />,
      {
        container: document,
      },
    );
    expect(screen.getByRole("main")).toHaveAttribute("id", "main-content");
    expect(
      screen.getByRole("heading", { level: 1, name: SiteCopy.errorTitle }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: SiteCopy.backHome }),
    ).toHaveAttribute("href", SitePath.home);
    await user.click(screen.getByRole("button", { name: SiteCopy.tryAgain }));
    expect(rootRetry).toHaveBeenCalledOnce();
  });

  it("offer a path back from missing pages", () => {
    render(<NotFound />);
    expect(
      screen.getByRole("heading", { name: SiteCopy.notFoundTitle }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: SiteCopy.backHome }),
    ).toHaveAttribute("href", SitePath.home);
  });
});
