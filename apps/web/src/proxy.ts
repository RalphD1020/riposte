/**
 * Server-mode play admission for `/play` (WEB-005): a 307 to the resolved
 * destination, or the `/play` page when none is configured. Static exports
 * cannot run a proxy; there, `PlayGateway` makes the same decision in the
 * browser from the same `resolvePlayAdmission`.
 *
 * Implements: spec/invariants.md#web-005
 *
 * @see ./config/runtimeConfig.ts
 * @see ./components/PlayGateway.tsx
 * @see ../../../../docs/concepts/web.md
 */

import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import {
  getRuntimeConfig,
  hostnameFromHostHeader,
  resolvePlayAdmission,
} from "@/config/runtimeConfig";

export function proxy(request: NextRequest): NextResponse {
  const hostname =
    hostnameFromHostHeader(request.headers.get("host")) ||
    request.nextUrl.hostname;
  const { destination } = resolvePlayAdmission(hostname, getRuntimeConfig());
  if (destination.status === "unconfigured") {
    return NextResponse.next();
  }
  return NextResponse.redirect(new URL(destination.href, request.url), 307);
}

// Next.js parses `config.matcher` at compile time, so entries MUST be string
// literals. `proxy.test.ts` asserts this stays equal to `SitePath.play`.
export const config = {
  matcher: ["/play"],
};
