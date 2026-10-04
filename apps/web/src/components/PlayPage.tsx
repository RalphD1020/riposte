/**
 * `/play`: hands the build-time play destinations to the browser gateway.
 *
 * @see ./PlayGateway.tsx
 * @see ../../../../docs/concepts/web.md
 */

import { PlayGateway } from "@/components/PlayGateway";
import { getRuntimeConfig } from "@/config/runtimeConfig";

export function PlayPage() {
  const { localPlay, publicPlay } = getRuntimeConfig();
  return <PlayGateway localPlay={localPlay} publicPlay={publicPlay} />;
}
