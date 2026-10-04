import type { Metadata } from "next";
import { PlayPage } from "@/components/PlayPage";
import { SiteCopy } from "@/content/site";

export const metadata: Metadata = {
  title: SiteCopy.play,
};

export default function PlayRoute() {
  return <PlayPage />;
}
