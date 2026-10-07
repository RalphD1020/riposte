/**
 * `/play`: resolves the play surface at build time and hands it to the
 * browser gateway.
 *
 * @see ./PlayGateway.tsx
 * @see ../../../../docs/concepts/web.md
 */

import { PlayGateway } from "@/components/PlayGateway";
import { getRuntimeConfig, resolvePlaySurface } from "@/config/runtimeConfig";

export function PlayPage() {
  return <PlayGateway admission={resolvePlaySurface(getRuntimeConfig())} />;
}
