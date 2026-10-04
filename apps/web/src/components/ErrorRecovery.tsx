/**
 * Shared recovery UI for route and root error boundaries. Shows plain
 * language, never the raw error message (it may expose internals).
 *
 * @see ../../../../docs/concepts/ux.md
 */

import { SiteCopy } from "@/content/site";

export interface ErrorRecoveryProps {
  readonly onRetry: () => void;
  readonly headingLevel?: "h1" | "h2";
}

export function ErrorRecovery({
  onRetry,
  headingLevel = "h2",
}: ErrorRecoveryProps) {
  const Heading = headingLevel;
  return (
    <div className="page" role="alert">
      <Heading className="page__title">{SiteCopy.errorTitle}</Heading>
      <p className="page__lede">{SiteCopy.errorBody}</p>
      <button type="button" className="primary-button" onClick={onRetry}>
        {SiteCopy.tryAgain}
      </button>
    </div>
  );
}
