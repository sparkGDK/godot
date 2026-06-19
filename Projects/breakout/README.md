# Breakout Coop Multiplayer

A small Godot 4.7 cooperative Breakout project with automatic LAN multiplayer.

## Run

Open `project.godot` in Godot, or run two copies of the exported executable:

```powershell
build\windows\BreakoutCoop.exe
```

## Controls

- Start two copies on the same PC or LAN. They discover each other automatically.
- Player 1 / host paddle uses `A` / `D`.
- Player 2 / client paddle uses left/right arrow keys.
- `F2` starts local coop on one machine.
- `Space` restarts the match on the host.
- `Esc` restarts automatic matchmaking.

LAN multiplayer uses UDP port `4242` for gameplay and UDP port `4243` for discovery, matching the Pong project.
If Windows Firewall asks for access, allow the game on private networks. The game uses both broadcast discovery and direct LAN subnet scanning.
