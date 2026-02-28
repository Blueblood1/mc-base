# Installation Guide

## One-Line Install

On any ComputerCraft computer or turtle, run:

```lua
wget run https://raw.githubusercontent.com/Blueblood1/mc-base/master/installer/install.lua
```

That's it! The installer will:
- Detect if it's a turtle or computer
- Download the correct files from GitHub
- Set up auto-updates
- Create startup scripts

## What Gets Installed

### On Computers (Central Command)
- `network.lua` - Networking library
- `updater.lua` - GitHub update system
- `central_computer.lua` - Command center
- `startup.lua` - Auto-start script

### On Turtles (Pig Feeder)
- `network.lua` - Networking library
- `turtle.lua` - Turtle utilities
- `updater.lua` - GitHub update system
- `pig_feeder.lua` - Pig feeding automation
- `startup.lua` - Auto-start script

## After Installation

### Central Computer
1. Attach wireless modem
2. (Optional) Attach monitor
3. Reboot

The computer will:
- Check for updates from GitHub
- Start the central command system
- Display turtle status dashboard

### Pig Feeder Turtle
1. Attach wireless modem
2. Place fuel chest to the RIGHT
3. Place food chest in FRONT
4. Position at bottom-right of 9x9 area
5. Reboot

The turtle will:
- Check for updates from GitHub
- Start the pig feeder daemon
- Run continuously, reporting status

## Updates

Everything auto-updates on boot from GitHub!

To push updates to all turtles:
- Press `U` on the central computer

## Troubleshooting

**"HTTP API is not enabled"**
- Enable HTTP in ComputerCraft config
- Check `computercraft-server.toml` or `computercraft-common.toml`
- Set `enabled = true` under `[http]`

**"Failed to download"**
- Check internet connection
- Verify GitHub repo is public
- Try manual download to test

**Turtle not showing on central**
- Check both have wireless modems
- Verify they're in range (64 blocks default)
- Check turtle is running (should never exit)

**Bootloop**
- Delete `startup.lua` temporarily
- Run programs manually to debug
- Check for errors in the code
