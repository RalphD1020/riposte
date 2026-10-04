import type { Metadata } from "next";
import Link from "next/link";
import { SiteCopy, SitePath } from "@/content/site";

export const metadata: Metadata = {
  title: SiteCopy.notFoundTitle,
};

export default function NotFound() {
  return (
    <div className="page">
      <h1 className="page__title">{SiteCopy.notFoundTitle}</h1>
      <p className="page__lede">{SiteCopy.notFoundBody}</p>
      <Link className="text-link" href={SitePath.home}>
        {SiteCopy.backHome}
      </Link>
    </div>
  );
}
