import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { SiteCopy } from "@/content/site";
import { CommunityCtas } from "./CommunityCtas";

describe("CommunityCtas", () => {
  it("renders announced, inert stubs until real URLs exist", () => {
    render(
      <CommunityCtas
        community={{ status: "unconfigured" }}
        support={{ status: "unconfigured" }}
        itch={{ status: "unconfigured" }}
      />,
    );
    const discord = screen.getByRole("button", {
      name: `${SiteCopy.discord}. ${SiteCopy.comingSoon}`,
    });
    expect(discord).toHaveAttribute("aria-disabled", "true");
    expect(discord).toHaveAttribute("type", "button");
    expect(discord.closest("form")).toBeNull();
    expect(
      screen.getByRole("button", {
        name: `${SiteCopy.patreon}. ${SiteCopy.comingSoon}`,
      }),
    ).toBeInTheDocument();
    expect(screen.queryAllByRole("link")).toHaveLength(0);
  });

  it("opens configured destinations in a new tab and says so", () => {
    render(
      <CommunityCtas
        community={{
          status: "configured",
          href: "https://discord.example/invite",
        }}
        support={{
          status: "configured",
          href: "https://patreon.example/riposte",
        }}
        itch={{ status: "configured", href: "https://stub.itch.io/riposte" }}
      />,
    );
    const discord = screen.getByRole("link", {
      name: `${SiteCopy.discord} ${SiteCopy.opensInNewTab}`,
    });
    expect(discord).toHaveAttribute("href", "https://discord.example/invite");
    expect(discord).toHaveAttribute("target", "_blank");
    expect(discord).toHaveAttribute("rel", "noopener noreferrer");
    expect(
      screen.getByRole("link", {
        name: `${SiteCopy.patreon} ${SiteCopy.opensInNewTab}`,
      }),
    ).toHaveAttribute("href", "https://patreon.example/riposte");
    expect(
      screen.getByRole("link", {
        name: `${SiteCopy.itch} ${SiteCopy.opensInNewTab}`,
      }),
    ).toHaveAttribute("href", "https://stub.itch.io/riposte");
  });
});
