# Central Computer v2 - Touch Control Upgrade

## New Features

### 1. Touch Screen Controls
- Start/Stop buttons for each turtle
- Update All button
- Refresh button
- Quit button
- Works on both monitors and terminals (mouse clicks)

### 2. Persistent State Management
- Turtle modes (running/paused) are saved to disk
- State persists through reboots and updates
- Each turtle remembers its last mode

### 3. Pause/Resume Functionality
- Turtles can be paused remotely from central computer
- Paused turtles stay online and respond to commands
- Paused turtles don't consume resources or perform tasks
- Resume instantly when toggled back to running

## New Files

### libs/ui.lua
Reusable UI library providing:
- Button class with click detection
- Screen wrapper for monitor/terminal abstraction
- Drawing helpers for boxes and centered text

### libs/state.lua
State management library providing:
- Persistent state storage
- Turtle mode tracking (running/paused)
- State save/load functions

### computers/central_computer_v2.lua
Enhanced central computer with:
- Touch screen interface
- Individual turtle control
- Persistent state management
- Improved visual layout

## Turtle Updates

All turtles now support:
- `set_mode` command to switch between running/paused
- Operating mode variable that controls main loop
- Paused mode: turtle stays online, sends telemetry, but doesn't work

## Installation

### For New Installations
The installer will automatically download all new files.

### For Existing Installations

1. Update the central computer:
```lua
-- On central computer
shell.run("central_computer_v2")
```

2. Update all turtles:
Press the UPDATE button on the central computer, or manually update each turtle.

3. The new libraries (ui.lua, state.lua) will be downloaded automatically on next update.

## Usage

### Central Computer

**Touch Controls:**
- Click START/STOP next to any turtle to toggle its mode
- Click UPDATE to push updates to all turtles
- Click REFRESH to request immediate telemetry
- Click QUIT to exit

**Keyboard Controls:**
- Q - Quit

### Turtle Modes

**Running Mode (Green):**
- Turtle performs its normal operations
- Consumes fuel and resources
- Executes work cycles

**Paused Mode (Gray):**
- Turtle stays online
- Responds to commands
- Sends telemetry
- Does NOT perform work
- Does NOT consume resources

## Technical Details

### State File
- Location: `central_state.txt` on central computer
- Format: Serialized Lua table
- Contains: Turtle modes indexed by turtle ID

### Network Protocol
New command type:
```lua
{
    command = "set_mode",
    mode = "running" or "paused"
}
```

### Turtle Behavior
When paused, turtles:
1. Check operating mode at start of main loop
2. If paused, send telemetry and check for commands
3. Sleep for 2 seconds and repeat
4. When resumed, immediately continue normal operations

## Migration Path

### Option 1: Replace Central Computer
1. Rename `central_computer.lua` to `central_computer_old.lua`
2. Rename `central_computer_v2.lua` to `central_computer.lua`
3. Update startup script if needed

### Option 2: Run Side-by-Side
- Keep both versions
- Run v2 with: `shell.run("central_computer_v2")`
- Original still available as: `shell.run("central_computer")`

## Future Enhancements

Possible additions:
- Schedule-based automation (pause at night, resume at day)
- Resource level monitoring with auto-pause on low supplies
- Multi-page UI for many turtles
- Turtle grouping and batch controls
- Performance statistics and graphs
