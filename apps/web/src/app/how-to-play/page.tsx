import type { Metadata } from "next";
import { HowToPlayPage } from "@/components/HowToPlayPage";
import { SiteCopy } from "@/content/site";

export const metadata: Metadata = {
  title: SiteCopy.howToPlay,
};

export default function HowToPlayRoute() {
  return <HowToPlayPage />;
}
