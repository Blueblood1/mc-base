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

**Operation:**
1. Loads fuel and food from chests
2. Descends 3 blocks to pig farm
3. Navigates 9x9 grid feeding pigs
4. Returns home and repeats

### Cow Feeder
Automated cow feeding in a 9x9 area.

**Setup:**
- Fuel chest to the RIGHT
- Food chest to the LEFT
- Position at bottom-right of 9x9 area

**Operation:**
Similar to pig feeder but with different chest layout.

### Tree Farmer
Automated 2x2 spruce tree farming with bonemeal.

**Setup:**
- Fuel chest to the RIGHT
- Sapling chest to the LEFT
- Bonemeal chest BEHIND
- Face forward toward planting area

**Operation:**
1. Loads fuel, saplings, and bonemeal
2. Plants 2x2 spruce saplings
3. Uses bonemeal to grow tree
4. Harvests entire tree
5. Deposits items and repeats

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
For instant updates during development:

1. Start the server: `python server.py`
2. Configure ComputerCraft to allow `127.0.0.1`
3. Updates pull from local server (no GitHub cache delay)

See SERVER.md for details.

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

### Adding New Turtles

1. Create your turtle program in `turtles/`
2. Use parallel command listener:
```lua
local function commandListener()
    while not stopRequested do
        local senderId, msgType, data = Network.receive(1)
        if msgType == Network.MSG_TYPES.COMMAND then
            if data.command == "set_mode" then
                operatingMode = data.mode
            end
        end
    end
end

parallel.waitForAll(mainLoop, commandListener)
```

3. Check pause state regularly:
```lua
local function checkPauseState()
    while operatingMode == "paused" do
        log("Paused - waiting for resume...")
        sendTelemetry()
        sleep(2)
    end
end
```

4. Add to updater manifest in `libs/updater.lua`

## Requirements

- ComputerCraft or CC: Tweaked
- HTTP API enabled
- Wireless modems (ender modems recommended)
- Minecraft 1.21+ (for ATM10)

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

## License

MIT License - Feel free to use and modify!

## Credits

Built for All the Mods 10 (ATM10) modpack.
