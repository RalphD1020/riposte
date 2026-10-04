export function HomePage() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center p-8">
      <h1 className="text-4xl font-bold mb-4">Riposte</h1>
      <p className="text-lg text-gray-600 mb-8">A browser-first Godot game</p>
      <div className="flex gap-4">
        <a
          href="/play"
          className="px-6 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
        >
          Play Now
        </a>
      </div>
    </main>
  );
}
