import { render, screen } from "@testing-library/react";
import { renderToString } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import { SiteCopy, SitePath } from "@/content/site";
import { PlayGateway, PlayView, replaceLocation } from "./PlayGateway";

const LOCAL = { status: "configured", href: "http://127.0.0.1:8060/" } as const;
const UNPUBLISHED = { status: "unconfigured" } as const;

describe("PlayView", () => {
  it("announces that it is checking before the host is known", () => {
    render(<PlayView admission={null} />);
    expect(
      screen.getByRole("heading", {
        level: 1,
        name: SiteCopy.playCheckingTitle,
      }),
    ).toBeInTheDocument();
    expect(screen.getByRole("status")).toHaveTextContent(
      SiteCopy.playCheckingBody,
    );
  });

  it("offers a manual link while opening a configured destination", () => {
    render(<PlayView admission={{ surface: "local", destination: LOCAL }} />);
    expect(screen.getByRole("status")).toHaveTextContent(
      SiteCopy.playOpeningBody,
    );
    expect(
      screen.getByRole("link", { name: SiteCopy.playOpeningCta }),
    ).toHaveAttribute("href", LOCAL.href);
  });

  it("explains an unpublished game and offers the way home", () => {
    render(
      <PlayView admission={{ surface: "public", destination: UNPUBLISHED }} />,
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
  it("prerenders a neutral checking state, since static HTML cannot know the host", () => {
    const navigate = vi.fn();
    const html = renderToString(
      <PlayGateway
        localPlay={LOCAL}
        publicPlay={UNPUBLISHED}
        navigate={navigate}
      />,
    );
    expect(html).toContain(SiteCopy.playCheckingTitle);
    expect(html).not.toContain(SiteCopy.playOpeningTitle);
    expect(navigate).not.toHaveBeenCalled();
  });

  it("navigates a loopback visitor to the local export", () => {
    expect(window.location.hostname).toBe("localhost");
    const navigate = vi.fn();
    render(
      <PlayGateway
        localPlay={LOCAL}
        publicPlay={UNPUBLISHED}
        navigate={navigate}
      />,
    );
    expect(navigate).toHaveBeenCalledExactlyOnceWith(LOCAL.href);
    expect(
      screen.getByRole("heading", { name: SiteCopy.playOpeningTitle }),
    ).toBeInTheDocument();
  });

  it("stays put when there is nowhere to go", () => {
    const navigate = vi.fn();
    render(
      <PlayGateway
        localPlay={UNPUBLISHED}
        publicPlay={UNPUBLISHED}
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
