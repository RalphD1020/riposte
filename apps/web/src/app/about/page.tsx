import type { Metadata } from "next";
import { AboutPage } from "@/components/AboutPage";
import { SiteCopy } from "@/content/site";

export const metadata: Metadata = {
  title: SiteCopy.about,
};

export default function AboutRoute() {
  return <AboutPage />;
}
