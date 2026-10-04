import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { SiteCopy, SitePath } from "@/content/site";
import { AboutPage } from "./AboutPage";
import { HowToPlayPage } from "./HowToPlayPage";

describe("content pages", () => {
  it("teaches both verbs on every device", () => {
    render(<HowToPlayPage />);
    expect(
      screen.getByRole("heading", { level: 1, name: SiteCopy.howToPlay }),
    ).toBeInTheDocument();
    const terms = screen.getAllByRole("term").map((term) => term.textContent);
    expect(terms).toEqual([SiteCopy.controlsMove, SiteCopy.controlsAttack]);
    expect(screen.getByText(SiteCopy.controlsAttackHow)).toBeInTheDocument();
    expect(screen.getByText(SiteCopy.controlsPhysics)).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: SiteCopy.playCta }),
    ).toHaveAttribute("href", SitePath.play);
  });

  it("explains what this release is", () => {
    render(<AboutPage />);
    expect(
      screen.getByRole("heading", { level: 1, name: SiteCopy.about }),
    ).toBeInTheDocument();
    expect(screen.getByText(SiteCopy.aboutBody)).toBeInTheDocument();
    expect(
      screen.getByRole("link", { name: SiteCopy.playCta }),
    ).toHaveAttribute("href", SitePath.play);
  });
});
