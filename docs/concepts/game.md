# Game

> See also: [README.md](../../README.md)
> Source: game design document

Riposte is a browser-first Godot game with a Next.js informational site.

## Architecture

- **Godot 4.7.x**: Game runtime using Compatibility renderer
- **Next.js**: Informational website and game gateway
- **Web Export**: Single-threaded Godot Web build

## Distribution

- **itch.io**: Godot Web export (`dist/game/web/`)
- **Website**: Next.js app for information and play gateway
