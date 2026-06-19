# Pong Multiplayer

A small Godot 4.7 Pong project with automatic LAN multiplayer.

## Run

Open `project.godot` in Godot, or run two instances:

```powershell
..\Godot_v4.7-stable_win64_console.exe --path .
```

## Controls

- Start two copies on the same PC or LAN. They discover each other automatically.
- Left/host paddle uses `W`/`S`.
- Right/client paddle uses arrow up/down.
- `Space` resets the score on the host.
- `Esc` restarts automatic matchmaking.

LAN multiplayer uses UDP port `4242` for gameplay and UDP port `4243` for discovery.
If Windows Firewall asks for access, allow the game on private networks. The game uses both broadcast discovery and direct LAN subnet scanning.
