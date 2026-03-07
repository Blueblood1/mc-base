# Installation Guide

## One-Line Install

### From GitHub (Production)
On any ComputerCraft computer or turtle, run:

```lua
wget run https://raw.githubusercontent.com/Blueblood1/mc-base/master/installer/install.lua
```

### From Local CDN (Development)
If you have the local server running:

```lua
wget run http://127.0.0.1:8080/installer/install.lua
```

That's it! The installer will:
- Detect if it's a turtle or computer
- Download the correct files (tries local CDN first, then GitHub)
- Set up auto-updates
- Create startup scripts

## What Gets Installed

### On Computers (Central Command)
- `BUILD_NUMBER` - Version tracking
- `network.lua` - Networking library
- `updater.lua` - Update system
- `version.lua` - Build number utilities
- `state.lua` - State persistence
- `ui.lua` - UI components
- `central_computer.lua` - Command center
- `startup.lua` - Auto-start script

### On Turtles
- `BUILD_NUMBER` - Version tracking
- `network.lua` - Networking library
- `turtle.lua` - Turtle utilities
- `updater.lua` - Update system
- `version.lua` - Build number utilities
- `[turtle_type].lua` - Specific turtle program
- `startup.lua` - Auto-start script

## After Installation

### Central Computer
1. Attach wireless modem (ender modem recommended)
2. (Optional) Attach monitor for touchscreen interface
3. Reboot

The computer will:
- Check for updates
- Start the central command system
- Display turtle status dashboard
- Wait for turtles to connect

### Turtles
1. Attach wireless modem (ender modem recommended)
2. Follow turtle-specific setup (see below)
3. Reboot

The turtle will:
- Check for updates
- Connect to central computer
- Request its operating mode (running/paused)
- Start working if mode is "running"

## Turtle-Specific Setup

### Pig Feeder
- Place fuel chest to the RIGHT
- Place food chest in FRONT
- Position at bottom-right of 9x9 area
- Face the direction you want it to start

### Cow Feeder
- Place fuel chest to the RIGHT
- Place food chest to the LEFT
- Position at bottom-right of 9x9 area
- Face the direction you want it to start

### Tree Farmer
- Place fuel chest to the RIGHT
- Place sapling chest to the LEFT
- Place bonemeal chest BEHIND
- Face forward toward planting area (2x2 space needed)

## Updates

Everything auto-updates on boot!

To manually update all turtles:
- Click UPDATE button on the central computer

## Remote Control

From the central computer:
- Click START to resume a paused turtle
- Click STOP to pause a turtle
- Turtles remember their state through reboots

## Troubleshooting

**"HTTP API is not enabled"**
- Enable HTTP in ComputerCraft config
- Check `computercraft-server.toml` or `computercraft-common.toml`
- Set `enabled = true` under `[http]`

**"Failed to download"**
- Check internet connection
- Verify GitHub repo is public
- For local CDN: ensure server is running and 127.0.0.1 is whitelisted

**Turtle not showing on central**
- Check both have wireless modems
- Verify they're in range (ender modems = unlimited range)
- Check turtle is running (should never exit)
- Press REFRESH on central computer

**Turtle won't START/STOP**
- Ensure both devices are updated to latest version
- Restart both central computer and turtle
- Check for error messages in alerts

**Version showing as "?"**
- BUILD_NUMBER file is missing or corrupted
- Re-run installer to restore
- Check for case-sensitivity conflicts (BUILD_NUMBER vs version.lua)

**Bootloop**
- Delete `startup.lua` temporarily
- Run programs manually to debug
- Check for errors in the code
- Verify all library files are present
