import Link from "next/link";

export default function NotFound() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center">
      <h1 className="text-4xl font-bold mb-4">404</h1>
      <p className="mb-4">Page not found</p>
      <Link href="/" className="text-blue-600 hover:underline">
        Return home
      </Link>
    </main>
  );
}
