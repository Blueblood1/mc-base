# Network Communication Refactoring - Design Document

## Overview

This design document outlines the technical approach for refactoring the network communication patterns in the ComputerCraft automation system. The refactoring introduces a new `libs/worker.lua` library, consolidates fuel management in `libs/turtle.lua`, and ensures consistent message handling across all devices.

## Architecture Changes

### New Library: `libs/worker.lua`

A new shared library for all worker devices (turtles and computers) that provides:

1. **Worker.waitForCentralConnection(state, workerName)**
   - Handles DNS lookup of central computer
   - Sends `request_mode` command
   - Waits for `set_mode` response with timeout
   - Defaults to "paused" mode on timeout
   - Updates state table with connection info

2. **Worker.createCommandListener(state, callbacks)**
   - Returns a function suitable for `parallel.waitForAll()`
   - Handles standard commands: `report_status`, `set_mode`, `update`, `stop`
   - Uses `Network.receive(1)` with 1-second timeout (non-blocking)
   - Calls appropriate callbacks for telemetry and alerts

### Enhanced Library: `libs/turtle.lua`

Add turtle-specific fuel management functions:

1. **TurtleLib.ensureFuelForCycle(minimumFuel, fuelChestDirection, sendTelemetry, sendAlert)**
   - Checks current fuel level
   - If below minimum, enters fuel lock
   - Attempts to load fuel from chest
   - Waits and retries until fuel is sufficient
   - Sends telemetry and alerts during fuel lock

2. **TurtleLib.loadFuelFromChestWithCleanup(fuelDirection, foodDirections, targetPercent)**
   - Cleans up non-fuel items to appropriate chests first
   - Loads fuel from specified chest
   - Returns unused items to fuel chest
   - Returns success status and final fuel percentage

3. **Remove moved functions:**
   - `TurtleLib.createCommandListener()` → removed (moved to Worker library)
   - `TurtleLib.waitForCentralConnection()` → removed (moved to Worker library)
   - `TurtleLib.checkPauseState()` → kept (turtle-specific, uses Version library)

## Implementation Details

### US-1: Consistent Message Handling

#### Wither Mob Farm Refactoring

**Current (WRONG):**
```lua
local function createCommandListener()
    return function()
        while true do
            local senderId, msgType, data = Network.receive()  -- BLOCKS!
            -- handle commands
        end
    end
end
```

**New (CORRECT):**
```lua
-- Use Worker.createCommandListener() instead
local commandListener = Worker.createCommandListener(sharedState, {
    sendAlert = sendAlert,
    sendTelemetry = sendTelemetry
})
```

#### Event-Driven Pattern

All devices must follow this pattern in their main event loop:

```lua
elseif event == "rednet_message" then
    local senderId = param1
    local message = param2
    local protocol = param3
    
    if protocol == Network.PROTOCOL then
        if type(message) == "table" then
            handleMessage(senderId, message.type, message.data)
        end
    end
end
```

### US-2 & US-3: Worker Library Implementation

#### Worker.waitForCentralConnection()

```lua
function Worker.waitForCentralConnection(state, workerName)
    local Network = require("network")
    local Version = require("version")
    
    Version.log("Connecting to central computer...")
    
    while not state.centralConnected do
        -- DNS lookup
        if not state.centralId then
            state.centralId = Network.lookup("central")
        end
        
        -- Send request
        local fullName = workerName .. " #" .. os.getComputerID()
        if state.centralId then
            Network.send(state.centralId, Network.MSG_TYPES.COMMAND, {
                command = "request_mode",
                name = fullName
            })
        else
            Network.broadcast(Network.MSG_TYPES.COMMAND, {
                command = "request_mode",
                name = fullName
            })
        end
        
        -- Wait for response with timeout
        local timeout = os.startTimer(5)
        while true do
            local event, param1, param2, param3 = os.pullEvent()
            
            if event == "timer" and param1 == timeout then
                Version.log("Timeout, retrying...")
                break
            elseif event == "rednet_message" then
                if param3 == Network.PROTOCOL and type(param2) == "table" then
                    if param2.type == Network.MSG_TYPES.COMMAND then
                        if param2.data.command == "set_mode" then
                            state.operatingMode = param2.data.mode
                            state.centralId = param1
                            state.centralConnected = true
                            Version.log("Connected! Mode: " .. state.operatingMode)
                            os.cancelTimer(timeout)
                            return
                        end
                    end
                end
            end
        end
        
        sleep(2)
    end
end
```

#### Worker.createCommandListener()

```lua
function Worker.createCommandListener(state, callbacks)
    local Network = require("network")
    local Updater = require("updater")
    local Version = require("version")
    
    return function()
        while not state.stopRequested do
            local senderId, msgType, data = Network.receive(1)
            
            if senderId and msgType == Network.MSG_TYPES.COMMAND then
                if data.command == "report_status" then
                    callbacks.sendTelemetry()
                    
                elseif data.command == "set_mode" then
                    local oldMode = state.operatingMode
                    state.operatingMode = data.mode or "running"
                    state.centralId = senderId
                    state.centralConnected = true
                    
                    if oldMode ~= state.operatingMode then
                        Version.log("Mode: " .. oldMode .. " -> " .. state.operatingMode)
                        callbacks.sendAlert("Mode changed to " .. state.operatingMode)
                    end
                    
                    callbacks.sendTelemetry()
                    
                elseif data.command == "stop" then
                    callbacks.sendAlert("Stop command received")
                    state.stopRequested = true
                    
                elseif data.command == "update" then
                    callbacks.sendAlert("Updating...")
                    local results = Updater.updateLocal()
                    local successCount = 0
                    for _, result in pairs(results) do
                        if result.success then successCount = successCount + 1 end
                    end
                    callbacks.sendAlert("Updated " .. successCount .. " files")
                    sleep(2)
                    os.reboot()
                end
            end
        end
    end
end
```

### US-4: Proactive Fuel Lock Management

#### TurtleLib.ensureFuelForCycle()

```lua
function TurtleLib.ensureFuelForCycle(minimumFuel, fuelChestDirection, sendTelemetry, sendAlert)
    local Version = require("version")
    local fuel = TurtleLib.getFuelStatus()
    
    if fuel.level >= minimumFuel then
        return true  -- Already have enough fuel
    end
    
    -- Enter fuel lock
    Version.log("FUEL LOCK: Need " .. minimumFuel .. ", have " .. fuel.level)
    sendAlert("FUEL LOCK: Insufficient fuel for cycle")
    
    while fuel.level < minimumFuel do
        Version.log("Fuel: " .. fuel.level .. "/" .. minimumFuel .. " - Loading...")
        
        -- Try to load fuel
        local success, fuelPercent = TurtleLib.loadFuelFromChest(fuelChestDirection, 100)
        
        fuel = TurtleLib.getFuelStatus()
        sendTelemetry()
        
        if fuel.level < minimumFuel then
            Version.log("Still need more fuel, waiting...")
            sleep(5)
        end
    end
    
    Version.log("Fuel lock released: " .. fuel.level .. " fuel")
    sendAlert("Fuel lock released")
    return true
end
```

#### TurtleLib.loadFuelFromChestWithCleanup()

```lua
function TurtleLib.loadFuelFromChestWithCleanup(fuelDirection, cleanupDirections, targetPercent)
    targetPercent = targetPercent or 80
    
    -- Step 1: Clean up non-fuel items to their respective chests
    for itemType, direction in pairs(cleanupDirections) do
        -- Turn to face cleanup chest
        if direction == "left" then turtle.turnLeft()
        elseif direction == "right" then turtle.turnRight()
        elseif direction == "back" then
            turtle.turnRight()
            turtle.turnRight()
        end
        
        -- Drop items of this type
        for slot = 1, 16 do
            turtle.select(slot)
            local item = turtle.getItemDetail(slot)
            if item and item.name:find(itemType) then
                turtle.drop()
            end
        end
        
        -- Turn back to original direction
        if direction == "left" then turtle.turnRight()
        elseif direction == "right" then turtle.turnLeft()
        elseif direction == "back" then
            turtle.turnRight()
            turtle.turnRight()
        end
    end
    
    -- Step 2: Load fuel using existing function
    return TurtleLib.loadFuelFromChest(fuelDirection, targetPercent)
end
```

#### Worker Fuel Requirements

Each turtle calculates its cycle fuel requirement:

**Pig Feeder:**
- 9x9 grid navigation: 81 moves
- Descent: 3 moves
- Ascent: 3 moves
- Row transitions: 8 moves
- Safety margin: 20%
- **Total: ~115 fuel minimum**

**Cow Feeder:**
- 9x9 grid navigation: 81 moves
- Ascent start: 2 moves + 2 entry
- Return: 8 + 10 moves
- Safety margin: 20%
- **Total: ~125 fuel minimum**

**Tree Farmer:**
- Planting movement: 6 moves
- Harvesting (variable height): ~50 moves average
- Return: 4 moves
- Safety margin: 20%
- **Total: ~75 fuel minimum**

### US-5: Consistent Telemetry Patterns

#### Worker Telemetry Rules

Workers must call `sendTelemetry()` at these points:

1. **After mode changes** (running ↔ paused)
2. **After phase changes** (idle → descending → navigating → ascending → idle)
3. **On periodic timer** (every 10-30 seconds)
4. **After entering/exiting fuel lock**
5. **In response to `report_status` command**

#### Phase Change Telemetry

Add `sendTelemetry()` calls at phase transitions:

```lua
-- Example from pig_feeder.lua
local function navigateGrid()
    if state.phase == "idle" or state.phase == "descending" then
        state.phase = "descending"
        saveState()
        sendTelemetry()  -- ✓ Already present
        -- ... descending logic ...
        
        state.phase = "navigating"
        saveState()
        sendTelemetry()  -- ✓ Already present
    end
    
    -- ... navigation logic ...
    
    state.phase = "ascending"
    saveState()
    sendTelemetry()  -- ✓ Already present
end

local function returnHome()
    -- ... return logic ...
    
    state.phase = "idle"
    saveState()
    sendTelemetry()  -- ✓ Need to add this!
end
```

#### Central Computer Message Processing

The central computer already follows the correct pattern:

```lua
-- Process messages immediately (fast, no display update)
elseif event == "rednet_message" then
    if param3 == Network.PROTOCOL then
        if type(param2) == "table" then
            handleMessage(param1, param2.type, param2.data)  -- Updates internal state only
        end
    end
end

-- Update display on timer (every 2 seconds)
if event == "timer" and param1 == checkTimer then
    -- ... other periodic tasks ...
    
    if (now - lastDisplayUpdate) > (DISPLAY_REFRESH * 1000) then
        updateDisplay()  -- Renders to screen
        lastDisplayUpdate = now
    end
end
```

## Migration Strategy

### Phase 1: Create Worker Library
1. Create `libs/worker.lua` with new functions
2. Update `libs/turtle.lua` to add fuel functions and deprecation wrappers
3. Test new libraries in isolation

### Phase 2: Update Wither Mob Farm
1. Replace custom command listener with `Worker.createCommandListener()`
2. Replace custom connection logic with `Worker.waitForCentralConnection()`
3. Test message handling and mode changes

### Phase 3: Update Turtle Workers
1. Update pig_feeder.lua:
   - Use `Worker` functions instead of `TurtleLib` for connection/commands
   - Add fuel lock with calculated minimum
   - Remove inline `refuel()` calls
   - Add missing telemetry calls

2. Update cow_feeder.lua:
   - Same changes as pig_feeder

3. Update tree_farmer.lua:
   - Migrate to `Worker` functions
   - Add fuel lock pattern
   - Already uses helpers, minimal changes

### Phase 4: Testing & Validation
1. Test each worker individually
2. Test all workers together with central computer
3. Verify telemetry updates within 2 seconds
4. Verify fuel lock behavior
5. Test reconnection after network interruption

## Backward Compatibility

### State File Compatibility

All state files remain unchanged:
- `central_state.txt` - Central computer state
- `pig_feeder_state.txt` - Pig feeder state
- `cow_feeder_state.txt` - Cow feeder state
- `tree_farmer_state.txt` - Tree farmer state

### Breaking Changes

The following functions are removed from `libs/turtle.lua`:
- `TurtleLib.createCommandListener()` - moved to `Worker.createCommandListener()`
- `TurtleLib.waitForCentralConnection()` - moved to `Worker.waitForCentralConnection()`

All worker files must be updated to use the new `Worker` library. This is a breaking change but all workers in the codebase will be updated as part of this refactoring.

## Testing Strategy

### Unit Testing (Manual)

1. **Worker.waitForCentralConnection()**
   - Test with central computer running
   - Test with central computer offline (should timeout and retry)
   - Test mode response handling

2. **Worker.createCommandListener()**
   - Test `report_status` command
   - Test `set_mode` command
   - Test `update` command
   - Test `stop` command

3. **TurtleLib.ensureFuelForCycle()**
   - Test with sufficient fuel (should pass immediately)
   - Test with insufficient fuel (should enter fuel lock)
   - Test fuel loading and lock release

### Integration Testing

1. **Message Handling**
   - Start all workers and central computer
   - Verify no message loss
   - Toggle worker modes from central
   - Verify immediate response

2. **Telemetry Display**
   - Start worker in idle state
   - Verify display shows "idle"
   - Worker starts work cycle
   - Verify display updates to "working" within 2 seconds

3. **Fuel Lock**
   - Empty fuel chest
   - Start turtle with low fuel
   - Verify fuel lock activates
   - Refill fuel chest
   - Verify turtle loads fuel and continues

## Performance Considerations

### Message Processing
- Command listeners use 1-second timeout (non-blocking)
- Message handlers execute quickly (no display updates)
- Display updates on 2-second timer (acceptable lag)

### Fuel Lock
- Checks fuel once per cycle (not during work)
- Reduces fuel-related operations by ~90%
- Eliminates mid-cycle fuel checks

### Telemetry
- Sent on state changes (immediate)
- Sent on timer (10-30 seconds)
- Central processes immediately, displays on timer

## Success Criteria

- [ ] All workers use `Worker.createCommandListener()`
- [ ] All workers use `Worker.waitForCentralConnection()`
- [ ] Wither mob farm uses event-driven message handling
- [ ] All turtles use fuel lock pattern
- [ ] No inline `refuel()` calls in work loops
- [ ] Telemetry sent on all phase changes
- [ ] Display updates within 2 seconds of state change
- [ ] No message loss during normal operations
- [ ] Workers reconnect after network interruption
- [ ] Code duplication reduced by 50%+

## Risks & Mitigations

### Risk: Breaking Existing Workers
**Mitigation:** Maintain backward compatibility with deprecated functions, test thoroughly before deployment

### Risk: Fuel Lock Calculations Wrong
**Mitigation:** Add 20% safety margin to all fuel calculations, test with empty fuel scenarios

### Risk: Telemetry Spam
**Mitigation:** Only send on actual state changes, maintain 10-second periodic minimum

### Risk: Display Performance
**Mitigation:** Keep display updates on timer, never in message handlers

## Future Enhancements (Out of Scope)

- Dynamic fuel calculation based on actual usage
- Predictive fuel alerts before lock
- Network quality monitoring
- Worker health checks and auto-restart
- Enhanced error recovery
