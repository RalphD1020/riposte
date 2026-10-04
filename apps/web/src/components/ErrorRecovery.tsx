"use client";

interface ErrorRecoveryProps {
  error: Error & { digest?: string };
  reset: () => void;
}

export function ErrorRecovery({ error, reset }: ErrorRecoveryProps) {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center p-8">
      <h1 className="text-2xl font-bold mb-4">Something went wrong</h1>
      <p className="mb-4 text-gray-600">{error.message}</p>
      <button
        onClick={() => reset()}
        className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700"
      >
        Try again
      </button>
    </main>
  );
}
