import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { SiteCopy, SiteName, SitePath } from "@/content/site";
import { HomePage } from "./HomePage";

describe("HomePage", () => {
  it("leads with the game and one primary Play action", () => {
    render(<HomePage />);
    expect(
      screen.getByRole("heading", { level: 1, name: SiteName }),
    ).toBeInTheDocument();
    expect(screen.getByText(SiteCopy.tagline)).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: SiteCopy.playCta }),
    ).toHaveAttribute("href", SitePath.play);
    expect(
      screen.getByRole("link", { name: SiteCopy.howToPlay }),
    ).toHaveAttribute("href", SitePath.howToPlay);
  });

  it("lists community destinations under their own heading", () => {
    render(<HomePage />);
    expect(
      screen.getByRole("region", { name: SiteCopy.community }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", {
        name: `${SiteCopy.discord}. ${SiteCopy.comingSoon}`,
      }),
    ).toBeInTheDocument();
  });
});
