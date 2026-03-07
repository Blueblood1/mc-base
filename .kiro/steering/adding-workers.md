---
inclusion: manual
---

# Adding New Workers - Complete Guide

This guide covers how to create new turtle or computer workers that integrate with the central command system.

## Overview

Workers are autonomous devices (turtles or computers) that:
- Connect to the central computer on startup
- Receive commands (pause/resume/update)
- Send telemetry about their status
- Handle interruptions gracefully (resume after reboot)

## Architecture Components

### Required Libraries
- `Network` - Communication with central computer
- `Worker` - Shared worker utilities (connection, command handling)
- `Version` - Build tracking and logging
- `Updater` - Auto-update system

### For Turtles Only
- `TurtleLib` - Turtle-specific utilities (fuel management, pause checking)

## Step-by-Step Guide

### 1. Basic Structure

All workers follow this structure:

```lua
-- Required imports
local Network = require("network")
local Worker = require("worker")
local Version = require("version")
local Updater = require("updater")

-- For turtles only:
local TurtleLib = require("turtle")

-- Configuration
local WORKER_NAME = "My Worker"

-- Shared state for command listener
local sharedState = {
    centralId = nil,
    centralConnected = false,
    operatingMode = "running",
    stopRequested = false
}

-- Forward declarations
local sendAlert
local sendTelemetry

-- Your worker logic here...

-- Main program
local function main()
    Version.printBanner(WORKER_NAME)
    
    -- Initialize network
    if not Network.init() then
        Version.log("Error: No modem found!")
        return
    end
    
    -- Set computer label
    if not os.getComputerLabel() then
        os.setComputerLabel(WORKER_NAME .. "_" .. os.getComputerID())
    end
    
    -- Wait for connection to central
    Worker.waitForCentralConnection(sharedState, WORKER_NAME)
    
    -- Send initial telemetry
    sendTelemetry()
    
    -- Create command listener
    local commandListener = Worker.createCommandListener(sharedState, {
        sendAlert = sendAlert,
        sendTelemetry = sendTelemetry
    })
    
    -- Run main loop and command listener in parallel
    parallel.waitForAll(
        function()
            while true do
                local success, err = pcall(mainLoop)
                if not success then
                    Version.log("Error: " .. tostring(err))
                    sendAlert("Critical error: " .. tostring(err))
                    sleep(10)
                end
            end
        end,
        commandListener
    )
end

main()
```

### 2. Telemetry Function

Implement `sendTelemetry()` to report status:

```lua
sendTelemetry = function()
    if not sharedState.centralId then
        sharedState.centralId = Network.lookup("central")
    end
    
    local telemetryData = {
        name = WORKER_NAME .. " #" .. os.getComputerID(),
        status = "working",  -- or "idle", "error", "warning"
        task = {
            -- Your task-specific data
            phase = "processing",
            progress = 50
        },
        stats = {
            -- Your statistics
            itemsProcessed = 100,
            cyclesCompleted = 5
        }
    }
    
    -- For turtles, add fuel and inventory
    if turtle then
        telemetryData.fuel = TurtleLib.getFuelStatus()
        telemetryData.inventory = TurtleLib.getInventoryStatus()
    end
    
    if sharedState.centralId then
        Network.send(sharedState.centralId, Network.MSG_TYPES.TELEMETRY, telemetryData)
    else
        Network.broadcast(Network.MSG_TYPES.TELEMETRY, telemetryData)
    end
end
```

### 3. Alert Function

Implement `sendAlert()` for errors and warnings:

```lua
sendAlert = function(message)
    if sharedState.centralId then
        Network.send(sharedState.centralId, Network.MSG_TYPES.ALERT, {
            name = WORKER_NAME .. " #" .. os.getComputerID(),
            message = message
        })
    else
        Network.broadcast(Network.MSG_TYPES.ALERT, {
            name = WORKER_NAME .. " #" .. os.getComputerID(),
            message = message
        })
    end
end
```

### 4. Main Loop

For turtles with fuel requirements:

```lua
local CYCLE_FUEL_REQUIREMENT = 100  -- Calculate based on your cycle

local function mainLoop()
    while true do
        -- Check if paused
        TurtleLib.checkPauseState(sharedState, sendTelemetry)
        
        Version.log("Starting cycle...")
        
        -- Proactive fuel check
        TurtleLib.ensureFuelForCycle(CYCLE_FUEL_REQUIREMENT, "right", sendAlert, sendTelemetry)
        TurtleLib.checkPauseState(sharedState, sendTelemetry)
        
        -- Your work here
        doWork()
        
        Version.log("Cycle complete!")
        sendTelemetry()
        
        sleep(2)
    end
end
```

For computers (no fuel):

```lua
local function mainLoop()
    while true do
        -- Check if paused
        while sharedState.operatingMode == "paused" do
            Version.log("Paused - waiting for resume...")
            sendTelemetry()
            sleep(2)
        end
        
        Version.log("Starting cycle...")
        
        -- Your work here
        doWork()
        
        Version.log("Cycle complete!")
        sendTelemetry()
        
        sleep(2)
    end
end
```

## Turtle-Specific Patterns

### Fuel Management

**Calculate Cycle Fuel Requirement:**
Count every movement in one complete cycle:
- `turtle.forward()` = 1 fuel
- `turtle.back()` = 1 fuel
- `turtle.up()` = 1 fuel
- `turtle.down()` = 1 fuel
- `turtle.turnLeft()` = 0 fuel
- `turtle.turnRight()` = 0 fuel

Add 10-15% buffer for safety.

**Proactive Fuel Lock:**
```lua
-- At start of mainLoop, before any work
TurtleLib.ensureFuelForCycle(CYCLE_FUEL_REQUIREMENT, "right", sendAlert, sendTelemetry)
```

This ensures the turtle has enough fuel to complete the entire cycle before starting. If fuel is insufficient, it waits at home until refueled.

**Load Fuel with Cleanup:**
```lua
local function loadFuel()
    -- Define cleanup directions for non-fuel items
    local cleanupDirections = {
        ["sapling"] = "left",   -- Items with "sapling" in name go left
        ["bone"] = "back",      -- Items with "bone" in name go back
        [""] = "front"          -- Everything else goes front
    }
    
    local success, fuelPercent = TurtleLib.loadFuelFromChestWithCleanup(
        "right",              -- Fuel chest direction
        cleanupDirections,    -- Where to dump non-fuel items
        80                    -- Target fuel percentage
    )
    
    if not success or fuelPercent < 80 then
        sendAlert("Could not reach 80% fuel (currently " .. fuelPercent .. "%)")
    end
end
```

**No Inline Refueling:**
Never call `turtle.refuel()` in your work loops. The proactive fuel check ensures you have enough fuel for the entire cycle.

### Pause State Checking

Check pause state at logical breakpoints:

```lua
-- After loading resources
TurtleLib.checkPauseState(sharedState, sendTelemetry)

-- Between major phases
doPhase1()
TurtleLib.checkPauseState(sharedState, sendTelemetry)

doPhase2()
TurtleLib.checkPauseState(sharedState, sendTelemetry)
```

This allows the turtle to pause gracefully between operations.

### State Persistence (Resume Logic)

For turtles that can be interrupted mid-cycle:

```lua
-- State tracking
local state = {
    phase = "idle",
    position = {x = 0, y = 0, z = 0},
    -- Other state variables
}

-- Save state
local function saveState()
    local file = fs.open("my_worker_state.txt", "w")
    file.write(textutils.serialize(state))
    file.close()
end

-- Load state
local function loadState()
    if fs.exists("my_worker_state.txt") then
        local file = fs.open("my_worker_state.txt", "r")
        local data = file.readAll()
        file.close()
        state = textutils.unserialize(data)
        return true
    end
    return false
end

-- Clear state
local function clearState()
    if fs.exists("my_worker_state.txt") then
        fs.delete("my_worker_state.txt")
    end
end

-- In main(), before starting parallel loops:
local resuming = loadState()
if resuming then
    Version.log("Resuming from saved state...")
    -- Handle resume logic inside parallel main loop
end

-- In parallel main loop function:
if resuming then
    checkPauseState()  -- Wait if paused
    
    -- Resume based on phase
    if state.phase == "working" then
        completeWork()
    end
    
    clearState()
    sendTelemetry()
end
```

**Important:** Start the command listener in parallel BEFORE checking pause state during resume, otherwise the turtle can't receive unpause commands.

## Computer-Specific Patterns

### Mode Change Callbacks

Computers may need to react to mode changes (e.g., update redstone output):

```lua
local function updateRedstone()
    if sharedState.operatingMode == "running" then
        redstone.setOutput("top", true)
    else
        redstone.setOutput("top", false)
    end
end

-- In main():
local commandListener = Worker.createCommandListener(sharedState, {
    sendAlert = sendAlert,
    sendTelemetry = sendTelemetry,
    onModeChange = updateRedstone  -- Called when mode changes
})
```

## Telemetry Best Practices

### When to Send Telemetry

1. **On phase changes** - When transitioning from idle to working or vice versa
2. **After completing cycles** - When returning to idle state
3. **During pause checks** - When waiting in paused state
4. **On errors** - When encountering problems

### What to Include

**Always:**
- `name` - Worker name with computer ID
- `status` - "idle", "working", "error", "warning"

**For Turtles:**
- `fuel` - Fuel status from `TurtleLib.getFuelStatus()`
- `inventory` - Inventory status from `TurtleLib.getInventoryStatus()`

**Task-Specific:**
- `task.phase` - Current phase of work
- `task.progress` - Progress indicator
- `stats` - Counters, totals, etc.

### Telemetry Frequency

- Don't spam - send every 10-30 seconds during normal operation
- Send immediately on phase changes
- Send when paused (every 2 seconds while waiting)

## Error Handling

### Alert on Errors

```lua
if not success then
    sendAlert("Failed to complete operation: " .. reason)
    sendTelemetry()  -- Update status to show error
end
```

### Retry Logic

```lua
local attempts = 0
local maxAttempts = 3

while attempts < maxAttempts do
    if tryOperation() then
        break
    end
    
    attempts = attempts + 1
    if attempts >= maxAttempts then
        sendAlert("Operation failed after " .. maxAttempts .. " attempts")
    end
    sleep(5)
end
```

### Graceful Degradation

```lua
if not canDoOptimalWork() then
    Version.log("Optimal path blocked, using fallback...")
    doFallbackWork()
end
```

## Startup Script

Create a startup script for auto-start on boot:

```lua
local function installStartup()
    if not fs.exists("startup") and not fs.exists("startup.lua") then
        Version.log("Installing startup file...")
        local file = fs.open("startup.lua", "w")
        file.write('-- Auto-start worker on boot\n')
        file.write('print("Checking for updates...")\n')
        file.write('local Updater = require("updater")\n')
        file.write('Updater.updateLocal()\n')
        file.write('print("Starting worker...")\n')
        file.write('shell.run("my_worker")\n')
        file.close()
        Version.log("Startup file installed!")
    end
end

-- Call in main() before starting work
installStartup()
```

## Adding to Update System

Add your worker to the updater manifest in `libs/updater.lua`:

```lua
local MANIFEST = {
    -- ... existing entries ...
    
    ["my_worker.lua"] = {
        path = "turtles/my_worker.lua",  -- or "computers/my_worker.lua"
        url = GITHUB_BASE .. "turtles/my_worker.lua",
        type = "turtle"  -- or "computer"
    }
}
```

## Testing Checklist

- [ ] Worker connects to central on startup
- [ ] Telemetry appears on central computer display
- [ ] START button resumes worker
- [ ] STOP button pauses worker
- [ ] Worker resumes after reboot (if paused)
- [ ] Worker completes interrupted cycles (if applicable)
- [ ] Fuel lock prevents mid-cycle fuel exhaustion (turtles)
- [ ] UPDATE command downloads and reboots
- [ ] Alerts appear on central computer
- [ ] Worker handles network disconnection gracefully

## Common Mistakes

1. **Calling `Network.receive()` in command listener** - Use Worker.createCommandListener() which handles this correctly with event-driven message handling

2. **Checking pause state before starting command listener** - Start the command listener in parallel first, then check pause state

3. **Inline refueling in work loops** - Use proactive fuel checking instead

4. **Not sending telemetry on phase changes** - Always send telemetry when transitioning between idle and working

5. **Blocking operations in message handlers** - Worker library handles this, but if you add custom message handling, keep it fast

6. **Forgetting to add to updater manifest** - Your worker won't auto-update without this

## Example Workers

Reference these existing workers for patterns:

- **Simple turtle:** `turtles/pig_feeder.lua` - Basic movement and resource management
- **Complex turtle:** `turtles/tree_farmer.lua` - Multiple phases, complex resume logic
- **Computer:** `computers/wither_mob_farm.lua` - Redstone control, mode change callbacks

## Summary

Creating a new worker:
1. Use Worker library for connection and command handling
2. Implement sendTelemetry() and sendAlert()
3. For turtles: calculate fuel requirement, use proactive fuel lock
4. Check pause state at logical breakpoints
5. Send telemetry on phase changes
6. Add startup script for auto-start
7. Add to updater manifest
8. Test all scenarios (pause, resume, reboot, update)
