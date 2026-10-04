import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { HomePage } from "./HomePage";

describe("HomePage", () => {
  it("renders the title", () => {
    render(<HomePage />);
    expect(
      screen.getByRole("heading", { name: "Riposte" }),
    ).toBeInTheDocument();
  });

  it("renders the play button", () => {
    render(<HomePage />);
    expect(screen.getByRole("link", { name: "Play Now" })).toBeInTheDocument();
  });
});
