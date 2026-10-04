import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { SiteCopy } from "@/content/site";
import { ErrorRecovery } from "./ErrorRecovery";

describe("ErrorRecovery", () => {
  it("alerts in plain language and retries on request", async () => {
    const retry = vi.fn();
    render(<ErrorRecovery onRetry={retry} />);
    expect(screen.getByRole("alert")).toHaveTextContent(SiteCopy.errorBody);
    expect(
      screen.getByRole("heading", { level: 2, name: SiteCopy.errorTitle }),
    ).toBeInTheDocument();
    await userEvent
      .setup()
      .click(screen.getByRole("button", { name: SiteCopy.tryAgain }));
    expect(retry).toHaveBeenCalledOnce();
  });

  it("can own the page heading when the layout is gone", () => {
    render(<ErrorRecovery onRetry={vi.fn()} headingLevel="h1" />);
    expect(
      screen.getByRole("heading", { level: 1, name: SiteCopy.errorTitle }),
    ).toBeInTheDocument();
  });
});
