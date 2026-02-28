# MC Base - Networked Turtle Automation System

A complete automation system for ComputerCraft with central monitoring, telemetry, and remote updates via GitHub.

## Features

- 🤖 Automated turtle operations with state persistence
- 📡 Wireless networking and telemetry
- 🖥️ Central command computer with real-time monitoring
- 📊 Monitor support for better visualization
- 🔄 Auto-update from GitHub on boot
- 🚨 Alert system for errors and warnings
- 💾 Resume from server restarts

## Quick Start

### Installation

Run this one-liner on any ComputerCraft computer or turtle:

```lua
wget run https://raw.githubusercontent.com/Blueblood1/mc-base/main/installer/install.lua
```

The installer will:
- Auto-detect if it's a turtle or computer
- Download the appropriate files
- Create startup scripts
- Configure auto-updates

### Setup

**Central Computer:**
1. Attach a wireless modem
2. (Optional) Attach a monitor for better display
3. Reboot or run `central_computer`

**Pig Feeder Turtle:**
1. Attach a wireless modem
2. Place fuel chest to the right
3. Place food chest in front
4. Reboot or run `pig_feeder`

## Project Structure

```
mc-base/
├── libs/              # Shared libraries
│   ├── network.lua    # Networking and messaging
│   ├── turtle.lua     # Turtle utilities
│   └── updater.lua    # GitHub update system
├── computers/         # Computer programs
│   └── central_computer.lua
├── turtles/          # Turtle programs
│   └── pig_feeder.lua
├── installer/        # Installation scripts
│   └── install.lua
└── README.md
```

## Central Computer

The central computer provides:
- Real-time turtle monitoring
- Fuel level tracking with alerts
- Task progress visualization
- Alert history
- Remote update deployment

### Controls
- `U` - Update all turtles from GitHub
- `R` - Manual refresh (request telemetry)
- `Q` - Quit

### Display
- Auto-refreshes every 2 seconds
- Shows connected turtles
- Displays fuel levels, task status, position
- Highlights warnings and errors
- Works on monitors or terminal

## Pig Feeder Turtle

Automated pig feeding system that:
- Runs continuously in a loop
- Feeds pigs in a 9x9 area
- Auto-loads fuel and food from chests
- Reports status to central computer
- Resumes from interruptions
- Waits when out of supplies

### Operation
1. Loads fuel from right chest
2. Loads food from front chest
3. Descends 3 blocks to pig farm
4. Navigates 9x9 grid feeding pigs
5. Returns home and ascends
6. Repeats forever

## Updates

### Auto-Update on Boot
All devices check for updates on startup:
- Downloads latest code from GitHub
- Only updates if files changed
- Reboots if updates applied
- Resumes operations automatically

### Manual Update
From central computer, press `U` to:
- Broadcast update command to all turtles
- Each device downloads from GitHub
- Devices reboot and resume

### Adding New Scripts
1. Add files to GitHub repo
2. Update `libs/updater.lua` MANIFEST
3. Push to GitHub
4. Press `U` on central computer

## Network Protocol

### Message Types
- `telemetry` - Status reports from turtles
- `command` - Commands from central to turtles
- `alert` - Error/warning messages
- `heartbeat` - Keep-alive messages

### Commands
- `report_status` - Request immediate telemetry
- `update` - Download scripts and reboot
- `stop` - Emergency stop

## Development

### Adding New Turtles

1. Create your turtle program in `turtles/`
2. Use the libraries:
```lua
local Network = require("network")
local TurtleLib = require("turtle")
local Updater = require("updater")
```

3. Send telemetry:
```lua
Network.broadcast(Network.MSG_TYPES.TELEMETRY, {
    name = "My Turtle",
    status = "working",
    fuel = TurtleLib.getFuelStatus()
})
```

4. Check for commands:
```lua
local senderId, msgType, data = Network.receive(0.1)
if msgType == Network.MSG_TYPES.COMMAND then
    -- Handle command
end
```

5. Add to updater manifest in `libs/updater.lua`

## Requirements

- ComputerCraft or CC: Tweaked
- HTTP API enabled
- Wireless modems
- Minecraft 1.21+ (for ATM10)

## License

MIT License - Feel free to use and modify!

## Credits

Built for All the Mods 10 (ATM10) modpack.
