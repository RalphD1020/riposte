import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Riposte",
  description: "A browser-first Godot game with a Next.js informational site.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
