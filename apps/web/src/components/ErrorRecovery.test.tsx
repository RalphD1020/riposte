import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { ErrorRecovery } from "./ErrorRecovery";

describe("ErrorRecovery", () => {
  it("renders error message", () => {
    const error = new Error("Test error message");
    const reset = vi.fn();
    render(<ErrorRecovery error={error} reset={reset} />);
    expect(screen.getByText("Test error message")).toBeInTheDocument();
  });

  it("calls reset when try again is clicked", () => {
    const error = new Error("Test error");
    const reset = vi.fn();
    render(<ErrorRecovery error={error} reset={reset} />);
    fireEvent.click(screen.getByRole("button", { name: "Try again" }));
    expect(reset).toHaveBeenCalledTimes(1);
  });
});
