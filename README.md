# MC Base - Networked Turtle Automation System

A complete automation system for ComputerCraft with central monitoring, telemetry, and remote control.

## Features

- 🤖 Automated turtle operations (pig feeder, cow feeder, tree farmer)
- 📡 Wireless networking with real-time telemetry
- 🖥️ Central command computer with touchscreen controls
- 🎮 Start/Stop individual turtles remotely
- 📊 Monitor support for better visualization
- 🔄 Auto-update system with local CDN support
- 🚨 Alert system for errors and warnings
- 💾 State persistence - resumes after restarts
- 🏗️ Build number tracking
- 📈 **NEW: Resource tracking with Refined Storage integration**
  - Real-time item quantity monitoring
  - Flow rate calculations (items/minute)
  - Historical graphs (1 hour of data)
  - Track multiple resources simultaneously

## Quick Start

### Installation

**From GitHub (Production):**
```lua
wget run https://raw.githubusercontent.com/Blueblood1/mc-base/master/installer/install.lua
```

**From Local CDN (Development):**
```lua
wget run http://127.0.0.1:8080/installer/install.lua
```

The installer will:
- Auto-detect if it's a turtle or computer
- Download the appropriate files
- Create startup scripts
- Configure auto-updates

### Setup

**Central Computer:**
1. Attach a wireless modem (ender modem recommended)
2. (Optional) Attach a monitor for touchscreen interface
3. Reboot or run `central_computer`

**Turtles:**
1. Attach a wireless modem (ender modem recommended)
2. Follow specific setup for turtle type (see below)
3. Reboot to auto-start

## Project Structure

```
mc-base/
├── libs/              # Shared libraries
│   ├── network.lua    # Networking and messaging
│   ├── turtle.lua     # Turtle utilities
│   ├── updater.lua    # Update system
│   ├── version.lua    # Build number tracking
│   ├── state.lua      # State persistence
│   └── ui.lua         # UI components
├── computers/         # Computer programs
│   └── central_computer.lua
├── turtles/          # Turtle programs
│   ├── pig_feeder.lua
│   ├── cow_feeder.lua
│   └── tree_farmer.lua
├── installer/        # Installation scripts
│   └── install.lua
├── BUILD_NUMBER      # Current build version
└── server.py         # Local development server
```

## Central Computer

The central computer provides:
- Real-time turtle monitoring dashboard
- Individual turtle control (Start/Stop buttons)
- Fuel level tracking with alerts
- Task progress visualization
- Alert history
- Remote update deployment

### Controls
- Click START/STOP buttons to control individual turtles
- UPDATE button - Deploy updates to all turtles
- REFRESH button - Request telemetry from all turtles
- QUIT button - Exit the program

### Display
- Auto-refreshes every 2 seconds
- Shows connected turtles with status
- Displays fuel levels, task status
- Highlights warnings and errors
- Works on monitors (touchscreen) or terminal (mouse)

## Turtle Types

### Pig Feeder
Automated pig feeding in a 9x9 area.

**Setup:**
- Fuel chest to the RIGHT
- Food chest in FRONT
- Position at bottom-right of 9x9 area

**Fuel Requirement:** 115 per cycle

**Operation:**
1. Checks fuel before starting (proactive fuel lock)
2. Loads fuel and food from chests
3. Descends 3 blocks to pig farm
4. Navigates 9x9 grid feeding pigs
5. Returns home and repeats

### Cow Feeder
Automated cow feeding in a 9x9 area.

**Setup:**
- Fuel chest to the RIGHT
- Food chest to the LEFT
- Position at bottom-right of 9x9 area

**Fuel Requirement:** 125 per cycle

**Operation:**
Similar to pig feeder but with different chest layout and slightly higher fuel needs.

### Tree Farmer
Automated 2x2 spruce tree farming with bonemeal.

**Setup:**
- Fuel chest to the RIGHT
- Sapling chest to the LEFT
- Bonemeal chest BEHIND
- Face forward toward planting area

**Fuel Requirement:** 150 per cycle

**Operation:**
1. Checks fuel before starting (proactive fuel lock)
2. Loads fuel, saplings, and bonemeal
3. Plants 2x2 spruce saplings
4. Uses bonemeal to grow tree
5. Harvests entire tree
6. Deposits items and repeats

## Updates

### Auto-Update on Boot
All devices check for updates on startup:
- Compares BUILD_NUMBER with server
- Only updates if version changed
- Shows update progress
- Reboots if updates applied

### Manual Update
From central computer, click UPDATE to:
- Broadcast update command to all turtles
- Each device downloads latest files
- Devices reboot and resume

### Local Development Server
For instant updates during development without GitHub's 5-minute cache delay:

1. Start the server: `python server.py`
2. Add `127.0.0.1` to ComputerCraft's HTTP whitelist:
   - Edit `config/computercraft-server.toml`
   - Add:
     ```toml
     [[http.rules]]
         host = "127.0.0.1"
         action = "allow"
     ```
3. Restart your Minecraft server
4. Updates now pull from local server first, then fallback to GitHub

The server runs on port 8080 and serves files with no caching. Both the installer and updater automatically try the local server first (at `http://127.0.0.1:8080`) before falling back to GitHub.

## Remote Control

### Pausing Turtles
Click STOP button on central computer to pause a turtle:
- Turtle completes current operation
- Enters paused state
- Sends telemetry showing "PAUSED"
- Persists through reboots

### Resuming Turtles
Click START button to resume:
- Turtle receives command immediately
- Resumes from where it left off
- Updates status to "active"

## Network Protocol

### Message Types
- `telemetry` - Status reports from turtles
- `command` - Commands from central to turtles
- `alert` - Error/warning messages
- `heartbeat` - Keep-alive messages
- `response` - Acknowledgments

### Commands
- `report_status` - Request immediate telemetry
- `set_mode` - Set turtle to "running" or "paused"
- `request_mode` - Turtle requests its mode on startup
- `update` - Download scripts and reboot

## Development

### Build System
- BUILD_NUMBER file tracks version
- Pre-commit hook auto-increments version
- Post-push hook displays deployed build
- Version shown in all log messages

### Fuel Management Pattern

All turtles use a proactive fuel lock pattern:

1. **Calculate cycle fuel requirement** - Determine how much fuel one complete cycle needs
2. **Check before starting** - Use `TurtleLib.ensureFuelForCycle()` at the start of each cycle
3. **No inline refueling** - Remove all `refuel()` calls from work loops
4. **Fuel lock behavior** - If fuel is insufficient, turtle waits at home until refueled

**Benefits:**
- Turtles never get stuck mid-cycle due to low fuel
- Predictable behavior - always completes or doesn't start
- Cleaner code - no fuel checks scattered throughout

### Adding New Workers

See `.kiro/steering/adding-workers.md` for comprehensive guidance on creating new turtle or computer workers.

**Quick Reference:**

For turtles:
```lua
local Worker = require("worker")
local TurtleLib = require("turtle")

-- Define fuel requirement
local CYCLE_FUEL_REQUIREMENT = 100

-- In main():
Worker.waitForCentralConnection(sharedState, "My Turtle")

-- In mainLoop():
TurtleLib.ensureFuelForCycle(CYCLE_FUEL_REQUIREMENT, "right", sendAlert, sendTelemetry)

-- Start command listener in parallel:
local commandListener = Worker.createCommandListener(sharedState, {
    sendAlert = sendAlert,
    sendTelemetry = sendTelemetry
})
parallel.waitForAll(mainLoop, commandListener)
```

For computers:
```lua
local Worker = require("worker")

-- In main():
Worker.waitForCentralConnection(sharedState, "My Computer")

-- Start command listener with optional callback:
local commandListener = Worker.createCommandListener(sharedState, {
    sendAlert = sendAlert,
    sendTelemetry = sendTelemetry,
    onModeChange = updateRedstone  -- Optional: called when mode changes
})
parallel.waitForAll(mainLoop, commandListener)
```

## Requirements

- ComputerCraft or CC: Tweaked
- HTTP API enabled
- Wireless modems (ender modems recommended)
- Minecraft 1.21+ (for ATM10)
- **Optional: Advanced Peripherals** (for resource tracking with Refined Storage)

## Troubleshooting

**Turtle not responding to START/STOP:**
- Check both have wireless modems
- Verify they're in range (ender modems = unlimited)
- Restart both devices

**Updates not working:**
- Check HTTP is enabled in ComputerCraft config
- Verify GitHub repo is accessible
- Try manual download to test connectivity

**Version showing as "?":**
- BUILD_NUMBER file missing or corrupted
- Run installer to restore
- Check file isn't conflicting with version.lua (case-sensitive filesystems)

**Resource tracking not showing:**
- Ensure Advanced Peripherals mod is installed
- Place RS Monitor computer next to RS Bridge
- Check RS Bridge is connected to RS network
- Wait 5-10 seconds for first data poll

## Resource Tracking (NEW!)

Track items in your Refined Storage system with real-time graphs and flow rates.

**Quick Setup:**
1. Place computer next to RS Bridge
2. Run installer, select option 4 (rs_monitor)
3. Edit top of `rs_monitor.lua` to specify items in TRACKED_ITEMS list
4. Reboot RS Monitor computer
5. Central computer will auto-update on next reboot

**See:** `RESOURCE_TRACKING_QUICKSTART.md` for detailed setup

**Features:**
- Real-time item counts
- Flow rates (items/minute)
- Historical graphs (1 hour)
- Automatic data persistence

## License

MIT License - Feel free to use and modify!

## Credits

Built for All the Mods 10 (ATM10) modpack.
