import { render, screen } from "@testing-library/react";
import { renderToString } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import { HOSTED_PLAY_PATH } from "@/config/runtimeConfig";
import { SiteCopy, SitePath } from "@/content/site";
import { PlayGateway, PlayView, replaceLocation } from "./PlayGateway";

const HOSTED = { status: "configured", href: HOSTED_PLAY_PATH } as const;
const ITCH = {
  status: "configured",
  href: "https://stub.itch.io/riposte",
} as const;
const UNPUBLISHED = { status: "unconfigured" } as const;

describe("PlayView", () => {
  it("offers a manual link while opening a configured destination", () => {
    render(<PlayView admission={{ surface: "hosted", destination: HOSTED }} />);
    expect(screen.getByRole("status")).toHaveTextContent(
      SiteCopy.playOpeningBody,
    );
    expect(
      screen.getByRole("link", { name: SiteCopy.playOpeningCta }),
    ).toHaveAttribute("href", HOSTED.href);
  });

  /**
   * Arriving on a different site unannounced is the one failure this page can
   * produce that looks like a bug to the visitor.
   */
  it("says so when the hop leaves this site", () => {
    render(<PlayView admission={{ surface: "itch", destination: ITCH }} />);
    expect(screen.getByRole("status")).toHaveTextContent(
      SiteCopy.playOpeningBodyItch,
    );
    expect(screen.getByRole("status")).not.toHaveTextContent(
      SiteCopy.playOpeningBody,
    );
    expect(
      screen.getByRole("link", { name: SiteCopy.playOpeningCta }),
    ).toHaveAttribute("href", ITCH.href);
  });

  it("explains an unpublished game and offers the way home", () => {
    render(
      <PlayView
        admission={{ surface: "unpublished", destination: UNPUBLISHED }}
      />,
    );
    expect(
      screen.getByRole("heading", { name: SiteCopy.playUnpublishedTitle }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: SiteCopy.backHome }),
    ).toHaveAttribute("href", SitePath.home);
  });
});

describe("PlayGateway", () => {
  /**
   * The surface is a build-time fact, so the prerendered HTML already names
   * the destination. The old gateway could not: it waited for the browser to
   * report a hostname, which meant every visitor read "Finding your duel"
   * first, including the ones whose answer was already known.
   */
  it("prerenders the resolved destination rather than a checking state", () => {
    const navigate = vi.fn();
    const html = renderToString(
      <PlayGateway
        admission={{ surface: "hosted", destination: HOSTED }}
        navigate={navigate}
      />,
    );
    expect(html).toContain(SiteCopy.playOpeningTitle);
    expect(html).toContain(HOSTED_PLAY_PATH);
    expect(navigate).not.toHaveBeenCalled();
  });

  /**
   * The static export has no rewrites, so this hop is how `/play` reaches the
   * export staged on the same origin.
   */
  it("navigates to the staged export on this origin", () => {
    const navigate = vi.fn();
    render(
      <PlayGateway
        admission={{ surface: "hosted", destination: HOSTED }}
        navigate={navigate}
      />,
    );
    expect(navigate).toHaveBeenCalledExactlyOnceWith(HOSTED_PLAY_PATH);
    expect(
      screen.getByRole("heading", { name: SiteCopy.playOpeningTitle }),
    ).toBeInTheDocument();
  });

  it("stays put when there is nowhere to go", () => {
    const navigate = vi.fn();
    render(
      <PlayGateway
        admission={{ surface: "unpublished", destination: UNPUBLISHED }}
        navigate={navigate}
      />,
    );
    expect(navigate).not.toHaveBeenCalled();
    expect(
      screen.getByRole("heading", { name: SiteCopy.playUnpublishedTitle }),
    ).toBeInTheDocument();
  });

  it("replaces the location by default so Back skips the gateway", () => {
    replaceLocation("#play-gateway");
    expect(window.location.hash).toBe("#play-gateway");
  });
});
