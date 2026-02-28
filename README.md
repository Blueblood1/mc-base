# Networked Turtle Automation System

A complete automation system for ComputerCraft with central monitoring, telemetry, and remote updates.

## Files

### Libraries
- `lib_network.lua` - Network communication and messaging
- `lib_turtle.lua` - Turtle utilities (fuel, inventory, etc.)
- `lib_updater.lua` - Pastebin update system

### Programs
- `central_computer.lua` - Central command and monitoring system
- `pig_feeder_networked.lua` - Automated pig feeding turtle
- `setup_updates.lua` - Configure pastebin codes for updates

## Setup

### Central Computer
1. Place a wireless modem on the computer
2. (Optional) Attach a monitor for better display
3. Copy files: `lib_network.lua`, `lib_updater.lua`, `central_computer.lua`
4. Run: `central_computer`

### Turtles
1. Place a wireless modem on the turtle
2. Copy files: `lib_network.lua`, `lib_turtle.lua`, `lib_updater.lua`, `pig_feeder_networked.lua`
3. Run: `pig_feeder_networked`

## Features

### Central Computer
- Auto-refreshing dashboard (updates every 2 seconds)
- Monitor support (auto-detects connected monitors)
- Real-time turtle status and telemetry
- Fuel level monitoring with alerts
- Task progress tracking
- Alert history

### Commands
- `U` - Send update command to all turtles
- `R` - Manual refresh (request telemetry)
- `Q` - Quit

### Turtle Features
- Automatic telemetry reporting
- Resume from crashes/restarts
- Remote update capability
- Alert system for errors
- Statistics tracking

## Pastebin Updates

### Setup (One-time)
1. Upload each script to pastebin.com and get the codes
2. Edit `lib_updater.lua` and update the `CONFIG` table:
```lua
Updater.CONFIG = {
    ["lib_network.lua"] = "abc123XY",
    ["lib_turtle.lua"] = "def456ZZ",
    ["lib_updater.lua"] = "ghi789QQ",
    ["central_computer.lua"] = "jkl012PP",
    ["pig_feeder_networked.lua"] = "mno345RR"
}
```
3. Copy the updated `lib_updater.lua` to all computers/turtles
4. Done! All devices now share the same config

### Usage
From the central computer:
- Press `U` to broadcast update command to all turtles
- Each turtle downloads only the files it has locally
- Turtles automatically reboot to apply updates

### Manual Update
On any turtle/computer:
```lua
local Updater = require("lib_updater")
Updater.updateLocal()  -- Updates only files that exist locally
os.reboot()
```

### Updating the Config
When you add new scripts:
1. Upload new script to pastebin
2. Edit `lib_updater.lua` CONFIG table
3. Upload the updated `lib_updater.lua` to pastebin
4. Press `U` on central computer
5. All devices get the new config and can update new scripts

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

## Extending the System

To add new turtles:
1. Copy the library files
2. Create your turtle program
3. Use `Network` for communication
4. Use `TurtleLib` for common operations
5. Send telemetry to central computer
6. Listen for commands

Example:
```lua
local Network = require("lib_network")
local TurtleLib = require("lib_turtle")

Network.init()
Network.broadcast(Network.MSG_TYPES.TELEMETRY, {
    name = "My Turtle",
    status = "working",
    fuel = TurtleLib.getFuelStatus()
})
```
