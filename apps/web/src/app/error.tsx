"use client";

/**
 * Route-segment error boundary. Layout chrome stays mounted.
 *
 * @see ../../../../docs/concepts/ux.md
 */

import { ErrorRecovery } from "@/components/ErrorRecovery";

export default function RouteError({
  retry,
}: {
  readonly error: Error & { digest?: string };
  readonly retry: () => void;
}) {
  return <ErrorRecovery onRetry={retry} />;
}
