"use client";

/**
 * Browser-side play admission (WEB-005) for `/play`. In server mode the
 * proxy has already redirected any configured destination, so this renders
 * the "not published" explanation; in static exports (no proxy) it makes the
 * same decision from `window.location.hostname` and replaces the location.
 * A visible link remains in case navigation is blocked.
 *
 * Implements: spec/invariants.md#web-005
 *
 * @see ../proxy.ts
 * @see ../config/runtimeConfig.ts
 * @see ../../../../docs/concepts/web.md
 */

import { useEffect, useSyncExternalStore } from "react";
import Link from "next/link";
import {
  resolvePlayAdmission,
  type Destination,
  type PlayAdmission,
} from "@/config/runtimeConfig";
import { SiteCopy, SitePath } from "@/content/site";

export function replaceLocation(href: string): void {
  window.location.replace(href);
}

const subscribe = () => () => {};
const readHostname = () => window.location.hostname;
const noHostname = () => null;

export function PlayView({
  admission,
}: {
  readonly admission: PlayAdmission | null;
}) {
  if (admission === null) {
    return (
      <div className="page">
        <h1 className="page__title">{SiteCopy.playCheckingTitle}</h1>
        <p className="page__lede" role="status">
          {SiteCopy.playCheckingBody}
        </p>
      </div>
    );
  }
  if (admission.destination.status === "configured") {
    return (
      <div className="page">
        <h1 className="page__title">{SiteCopy.playOpeningTitle}</h1>
        <p className="page__lede" role="status">
          {SiteCopy.playOpeningBody}
        </p>
        <a className="primary-button" href={admission.destination.href}>
          {SiteCopy.playOpeningCta}
        </a>
      </div>
    );
  }
  return (
    <div className="page">
      <h1 className="page__title">{SiteCopy.playUnpublishedTitle}</h1>
      <p className="page__lede">{SiteCopy.playUnpublishedBody}</p>
      <Link className="text-link" href={SitePath.home}>
        {SiteCopy.backHome}
      </Link>
    </div>
  );
}

export function PlayGateway({
  localPlay,
  publicPlay,
  navigate = replaceLocation,
}: {
  readonly localPlay: Destination;
  readonly publicPlay: Destination;
  readonly navigate?: (href: string) => void;
}) {
  const hostname = useSyncExternalStore(subscribe, readHostname, noHostname);
  const admission =
    hostname === null
      ? null
      : resolvePlayAdmission(hostname, { localPlay, publicPlay });
  const target =
    admission?.destination.status === "configured"
      ? admission.destination.href
      : null;

  useEffect(() => {
    if (target !== null) {
      navigate(target);
    }
  }, [target, navigate]);

  return <PlayView admission={admission} />;
}
