"use client";

/**
 * `/play`. One mechanism in both build modes: the surface is resolved at
 * build time and this navigates to it.
 *
 * In the server build a staged export is already a rewrite, so this page is
 * never reached for the `hosted` surface — it is the fallback that explains
 * where the game is when this deployment does not carry one. In the static
 * export there are no rewrites, so the same component performs the hop.
 *
 * There used to be a proxy doing this server-side and this doing it again in
 * the browser, from the visitor's hostname. Two implementations of one
 * decision, one of which could not run in the mode we actually ship. Now the
 * decision is made once, at build time, by whether the artifact is there.
 *
 * Implements: spec/invariants.md#web-005
 *
 * @see ../config/runtimeConfig.ts
 * @see ../../../../docs/concepts/web.md
 */

import { useEffect } from "react";
import Link from "next/link";
import { type PlayAdmission } from "@/config/runtimeConfig";
import { SiteCopy, SitePath } from "@/content/site";

export function replaceLocation(href: string): void {
  window.location.replace(href);
}

/**
 * The resolved surface, rendered. `surface` and not the shape of the href:
 * whether a hop leaves this site is the admission decision's own answer, and
 * re-deriving it from a leading slash would be a second, quieter copy of it.
 */
export function PlayView({ admission }: { readonly admission: PlayAdmission }) {
  if (admission.destination.status === "configured") {
    return (
      <div className="page">
        <h1 className="page__title">{SiteCopy.playOpeningTitle}</h1>
        <p className="page__lede" role="status">
          {admission.surface === "itch"
            ? SiteCopy.playOpeningBodyItch
            : SiteCopy.playOpeningBody}
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
  admission,
  navigate = replaceLocation,
}: {
  readonly admission: PlayAdmission;
  readonly navigate?: (href: string) => void;
}) {
  const target =
    admission.destination.status === "configured"
      ? admission.destination.href
      : null;

  useEffect(() => {
    if (target !== null) {
      navigate(target);
    }
  }, [target, navigate]);

  return <PlayView admission={admission} />;
}
