---
inclusion: always
---

# Checkpoint-Based Recovery System

## Overview

Our automation system uses a checkpoint-based recovery system that allows turtles and computers to resume operations after crashes, server restarts, or power loss. The system is built on two core libraries:

- `libs/checkpoint.lua` - Persistent state management
- `libs/executor.lua` - Step-based execution with automatic checkpointing

## Core Principles

### 1. Atomic Steps

Every operation is broken down into single atomic actions:
- Single movement (forward, back, up, down)
- Single turn (left or right)
- Single place/dig/suck operation
- Single slot selection

**NEVER** use multi-count actions in step definitions (e.g., "move forward 4 times" as one step). Each movement must be its own step.

### 2. Two-Phase Commit for Movements

Movements can be interrupted mid-execution, so we use a two-phase commit:

1. **Save checkpoint** with current fuel level BEFORE movement
2. **Execute movement** (may be interrupted)
3. **On resume**: Compare current fuel to saved fuel
   - If fuel unchanged → movement didn't happen, retry step
   - If fuel changed → movement succeeded, skip to next step

```lua
-- Checkpoint saved before step execution
{
    step = 42,
    fuelBefore = 1500  -- Current fuel level
}

-- On resume after crash
local currentFuel = turtle.getFuelLevel()
if currentFuel == checkpoint.fuelBefore then
    -- Fuel unchanged, retry step 42
    startStep = 42
else
    -- Fuel changed, movement succeeded, continue from step 43
    startStep = 43
end
```

### 3. Compass-Based Turn Validation

**CRITICAL**: Turns are NOT atomic in ComputerCraft. State can be lost during a turn if the server crashes or chunk unloads.

**Solution**: Use a compass turtle from Advanced Peripherals mod. The compass provides absolute orientation that persists across restarts.

```lua
-- Check for compass on startup
local compass = peripheral.find("compass")
if compass then
    context.useCompass = true
    context.compass = compass
end

-- Save facing BEFORE turn
{
    step = 15,
    facingBefore = "north"  -- From compass.getFacing()
}

-- On resume after crash
local currentFacing = compass.getFacing()
if currentFacing == checkpoint.facingBefore then
    -- Facing unchanged, turn didn't happen, retry step 15
    startStep = 15
else
    -- Facing changed, turn succeeded, continue from step 16
    startStep = 16
end
```

**Without compass**: Falls back to relative orientation tracking (0=forward, 1=right, 2=back, 3=left), but this is NOT crash-safe for turns.

### 4. Idempotent Actions

Some actions are naturally idempotent (safe to retry):
- **Place**: If block already placed, place() returns false but no harm done
- **Dig**: If block already dug, dig() returns false but no harm done
- **Suck**: If items already taken, suck() returns false but no harm done
- **Select**: Always safe to retry

These actions don't need special validation - just retry on resume.

## Step Definition Format

```lua
local steps = {
    -- Movement (fuel-tracked)
    {action = "move", direction = "forward"},
    {action = "move", direction = "back"},
    {action = "move", direction = "up"},
    {action = "move", direction = "down"},
    
    -- Turn (compass-tracked if available)
    {action = "turn", direction = "right"},
    {action = "turn", direction = "left"},
    
    -- Place (idempotent)
    {action = "place", slot = 2, side = "front"},  -- side: front/up/down
    
    -- Dig (idempotent)
    {action = "dig", side = "front"},  -- side: front/up/down
    
    -- Suck (idempotent)
    {action = "suck", side = "front", amount = 64},
    
    -- Select (idempotent)
    {action = "select", slot = 3},
    
    -- Network send
    {action = "network_send", data = {command = "open_door", cell = 1}},
    
    -- Wait/sleep
    {action = "wait", duration = 5},
    
    -- Custom function
    {action = "function", func = function(context) return true end},
    
    -- Optional log message
    {action = "move", direction = "forward", log = "Moving to cell 1..."}
}
```

## Usage Pattern

```lua
local Executor = require("executor")

-- Define context (shared state)
local context = {
    farmComputerId = 42,
    -- Add any shared state here
}

-- Build step array
local steps = buildSteps()  -- Returns array of step definitions

-- Execute with automatic checkpointing
local success, err = Executor.run(
    steps,                           -- Step array
    context,                         -- Shared context
    "my_checkpoint.txt",            -- Checkpoint filename
    nil                             -- Checkpoint at all steps (default)
)

if not success then
    print("ERROR: " .. tostring(err))
    print("Checkpoint saved. Restart to resume.")
end
```

## Recovery Flow

1. **Normal execution**: Executor saves checkpoint before each step, executes step, continues
2. **Crash occurs**: Server crashes, turtle loses power, chunk unloads, etc.
3. **On restart**: 
   - Executor loads checkpoint file
   - Checks if last step completed using fuel/compass validation
   - Either retries last step or continues from next step
4. **Completion**: Checkpoint file deleted when all steps complete successfully

## Best Practices

### DO:
- Break operations into single atomic actions
- Use compass turtle for any program with turns
- Save checkpoint BEFORE executing step
- Use fuel level to validate movements
- Use compass.getFacing() to validate turns
- Make place/dig/suck operations idempotent by design

### DON'T:
- Use multi-count actions (move 4 times in one step)
- Assume turns are atomic (they're not!)
- Use relative orientation without compass for crash recovery
- Skip checkpoints to "optimize" (defeats the purpose)
- Forget to delete checkpoint on successful completion

## Example: Complete Turtle Program

```lua
local Executor = require("executor")
local Network = require("network")

local context = {
    farmComputerId = nil
}

local function buildSteps()
    local steps = {}
    
    -- Load resources (atomic steps)
    table.insert(steps, {action = "turn", direction = "left", log = "Loading items..."})
    table.insert(steps, {action = "select", slot = 2})
    table.insert(steps, {action = "suck", side = "front"})
    table.insert(steps, {action = "turn", direction = "right"})
    
    -- Move to location (atomic steps)
    table.insert(steps, {action = "move", direction = "forward", log = "Moving..."})
    table.insert(steps, {action = "move", direction = "forward"})
    table.insert(steps, {action = "turn", direction = "right"})
    table.insert(steps, {action = "move", direction = "forward"})
    
    -- Place block
    table.insert(steps, {action = "place", slot = 2, log = "Placing block..."})
    
    return steps
end

local function main()
    Network.init()
    context.farmComputerId = Network.lookup("farm_computer")
    
    local steps = buildSteps()
    print("Generated " .. #steps .. " steps")
    
    local success, err = Executor.run(steps, context, "my_checkpoint.txt")
    
    if not success then
        print("ERROR: " .. tostring(err))
    else
        print("Complete!")
    end
end

main()
```

## Compass Turtle Setup

To use compass-based turn validation:

1. Install Advanced Peripherals mod
2. Craft a compass turtle (turtle + compass)
3. The executor automatically detects the compass peripheral
4. Turns are validated using absolute orientation (north/south/east/west)

Without a compass, the system falls back to relative tracking, but turn recovery is NOT guaranteed after crashes.

## Troubleshooting

**Problem**: Turtle gets lost after crash during turn
**Solution**: Use compass turtle for absolute orientation tracking

**Problem**: Turtle repeats movement after crash
**Solution**: Check fuel level is being saved in checkpoint (fuelBefore field)

**Problem**: Turtle skips step after crash
**Solution**: Verify step completed check logic (fuel changed = step succeeded)

**Problem**: Checkpoint not saving
**Solution**: Check disk space, verify checkpoint filename is valid

**Problem**: Steps take too long
**Solution**: Each step should be single action only, check for multi-count operations

## Summary

The checkpoint recovery system provides crash-safe automation by:
1. Breaking operations into atomic steps
2. Saving state before each step
3. Using fuel level to validate movements
4. Using compass to validate turns (with Advanced Peripherals)
5. Making place/dig/suck naturally idempotent
6. Automatically resuming from correct step after crash
