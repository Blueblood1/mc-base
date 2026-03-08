-- Wither Boss Farmer V2 (Step-Based)
-- Uses declarative step system for perfect recovery

local Executor = require("executor")
local Network = require("network")
local Version = require("version")

-- Configuration
local TURTLE_NAME = "Wither Boss Farmer V2"
local FUEL_SLOT = 1
local SOUL_SAND_SLOT = 2
local SKULL_SLOT = 3

-- Shared context
local context = {
    farmComputerId = nil
}

-- Build the step sequence
local function buildSteps()
    local steps = {}
    
    -- Helper to add step
    local function add(step)
        table.insert(steps, step)
    end
    
    -- ===== LOAD RESOURCES =====
    add({action = "function", log = "Loading soul sand from left...", func = function(ctx)
        turtle.turnLeft()
        turtle.select(SOUL_SAND_SLOT)
        for i = 1, 10 do
            turtle.suck(64)
        end
        local count = turtle.getItemCount(SOUL_SAND_SLOT)
        print("Loaded " .. count .. " soul sand")
        turtle.turnRight()
        return true
    end})
    
    add({action = "function", log = "Loading skulls from behind...", func = function(ctx)
        turtle.turnRight()
        turtle.turnRight()
        turtle.select(SKULL_SLOT)
        for i = 1, 10 do
            turtle.suck(64)
        end
        local count = turtle.getItemCount(SKULL_SLOT)
        print("Loaded " .. count .. " skulls")
        turtle.turnRight()
        turtle.turnRight()
        return true
    end})
    
    -- ===== CELL 1 =====
    add({action = "move", direction = "forward", count = 2, log = "Moving to door 1..."})
    add({action = "network_send", data = {command = "open_door", cell = 1}, log = "Opening door 1..."})
    add({action = "move", direction = "forward", count = 4, log = "Entering cell 1..."})
    add({action = "network_send", data = {command = "close_door", cell = 1}, log = "Closing door 1..."})
    
    -- Build wither in cell 1
    add({action = "turn", direction = "right", count = 2, log = "Turning to build position..."})
    add({action = "move", direction = "up", log = "Ascending..."})
    add({action = "turn", direction = "right"})
    add({action = "move", direction = "forward"})
    add({action = "turn", direction = "left"})
    add({action = "place", slot = SOUL_SAND_SLOT, log = "Placing right arm soul sand..."})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SKULL_SLOT, log = "Placing right skull..."})
    add({action = "move", direction = "down"})
    add({action = "turn", direction = "left"})
    add({action = "move", direction = "forward", count = 2})
    add({action = "turn", direction = "right"})
    add({action = "place", slot = SOUL_SAND_SLOT, log = "Placing center soul sand..."})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SKULL_SLOT, log = "Placing center skull..."})
    add({action = "move", direction = "down"})
    add({action = "turn", direction = "right"})
    add({action = "move", direction = "forward"})
    add({action = "turn", direction = "left"})
    add({action = "place", slot = SOUL_SAND_SLOT, log = "Placing left arm soul sand..."})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SKULL_SLOT, log = "Placing left skull..."})
    add({action = "move", direction = "down", count = 2})
    add({action = "place", slot = SOUL_SAND_SLOT, log = "Placing bottom soul sand..."})
    
    -- Exit cell 1 to cell 2
    add({action = "network_send", data = {command = "open_door", cell = 2}, log = "Opening door 2..."})
    add({action = "turn", direction = "right", count = 2})
    add({action = "move", direction = "forward", count = 4, log = "Moving to cell 2..."})
    add({action = "network_send", data = {command = "close_door", cell = 2}, log = "Closing door 2..."})
    
    -- ===== CELL 2 =====
    -- Build wither in cell 2 (already facing correct direction)
    add({action = "turn", direction = "right", count = 2, log = "Turning to build position..."})
    add({action = "move", direction = "up"})
    add({action = "turn", direction = "right"})
    add({action = "move", direction = "forward"})
    add({action = "turn", direction = "left"})
    add({action = "place", slot = SOUL_SAND_SLOT, log = "Placing right arm soul sand..."})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SKULL_SLOT, log = "Placing right skull..."})
    add({action = "move", direction = "down"})
    add({action = "turn", direction = "left"})
    add({action = "move", direction = "forward", count = 2})
    add({action = "turn", direction = "right"})
    add({action = "place", slot = SOUL_SAND_SLOT, log = "Placing center soul sand..."})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SKULL_SLOT, log = "Placing center skull..."})
    add({action = "move", direction = "down"})
    add({action = "turn", direction = "right"})
    add({action = "move", direction = "forward"})
    add({action = "turn", direction = "left"})
    add({action = "place", slot = SOUL_SAND_SLOT, log = "Placing left arm soul sand..."})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SKULL_SLOT, log = "Placing left skull..."})
    add({action = "move", direction = "down", count = 2})
    add({action = "place", slot = SOUL_SAND_SLOT, log = "Placing bottom soul sand..."})
    
    -- Exit cell 2 to cell 3 (complex side path)
    add({action = "turn", direction = "left", log = "Turning to side exit..."})
    add({action = "network_send", data = {command = "open_door", cell = 3}, log = "Opening door 3..."})
    add({action = "move", direction = "forward", count = 6, log = "Moving through passage..."})
    add({action = "network_send", data = {command = "open_door", cell = 4}, log = "Opening door 4..."})
    add({action = "move", direction = "forward", count = 5})
    add({action = "turn", direction = "right"})
    add({action = "move", direction = "forward", count = 2})
    add({action = "turn", direction = "right", count = 2})
    add({action = "network_send", data = {command = "close_door", cell = 4}, log = "Closing door 4..."})
    
    -- ===== CELL 3 =====
    -- Build wither in cell 3 (no initial turn needed)
    add({action = "move", direction = "up", log = "Building wither in cell 3..."})
    add({action = "turn", direction = "right"})
    add({action = "move", direction = "forward"})
    add({action = "turn", direction = "left"})
    add({action = "place", slot = SOUL_SAND_SLOT, log = "Placing right arm soul sand..."})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SKULL_SLOT, log = "Placing right skull..."})
    add({action = "move", direction = "down"})
    add({action = "turn", direction = "left"})
    add({action = "move", direction = "forward", count = 2})
    add({action = "turn", direction = "right"})
    add({action = "place", slot = SOUL_SAND_SLOT, log = "Placing center soul sand..."})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SKULL_SLOT, log = "Placing center skull..."})
    add({action = "move", direction = "down"})
    add({action = "turn", direction = "right"})
    add({action = "move", direction = "forward"})
    add({action = "turn", direction = "left"})
    add({action = "place", slot = SOUL_SAND_SLOT, log = "Placing left arm soul sand..."})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SKULL_SLOT, log = "Placing left skull..."})
    add({action = "move", direction = "down", count = 2})
    add({action = "place", slot = SOUL_SAND_SLOT, log = "Placing bottom soul sand..."})
    
    -- Exit cell 3 to cell 4
    add({action = "network_send", data = {command = "open_door", cell = 5}, log = "Opening door 5..."})
    add({action = "turn", direction = "right", count = 2})
    add({action = "move", direction = "forward", count = 4, log = "Moving to cell 4..."})
    add({action = "network_send", data = {command = "close_door", cell = 5}, log = "Closing door 5..."})
    
    -- ===== CELL 4 =====
    -- Build wither in cell 4
    add({action = "turn", direction = "right", count = 2, log = "Building wither in cell 4..."})
    add({action = "move", direction = "up"})
    add({action = "turn", direction = "right"})
    add({action = "move", direction = "forward"})
    add({action = "turn", direction = "left"})
    add({action = "place", slot = SOUL_SAND_SLOT, log = "Placing right arm soul sand..."})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SKULL_SLOT, log = "Placing right skull..."})
    add({action = "move", direction = "down"})
    add({action = "turn", direction = "left"})
    add({action = "move", direction = "forward", count = 2})
    add({action = "turn", direction = "right"})
    add({action = "place", slot = SOUL_SAND_SLOT, log = "Placing center soul sand..."})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SKULL_SLOT, log = "Placing center skull..."})
    add({action = "move", direction = "down"})
    add({action = "turn", direction = "right"})
    add({action = "move", direction = "forward"})
    add({action = "turn", direction = "left"})
    add({action = "place", slot = SOUL_SAND_SLOT, log = "Placing left arm soul sand..."})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SKULL_SLOT, log = "Placing left skull..."})
    add({action = "move", direction = "down", count = 2})
    add({action = "place", slot = SOUL_SAND_SLOT, log = "Placing bottom soul sand..."})
    
    -- ===== RETURN TO START =====
    add({action = "turn", direction = "right", count = 2, log = "Returning to start..."})
    add({action = "network_send", data = {command = "open_door", cell = 6}, log = "Opening door 6..."})
    add({action = "move", direction = "forward", count = 2})
    add({action = "network_send", data = {command = "close_door", cell = 6}, log = "Closing door 6..."})
    add({action = "turn", direction = "right"})
    add({action = "move", direction = "forward", count = 11})
    add({action = "turn", direction = "left"})
    add({action = "move", direction = "forward", count = 2})
    add({action = "turn", direction = "right", count = 2})
    
    add({action = "function", log = "Cycle complete! Waiting 10 minutes...", func = function(ctx)
        sleep(600)
        return true
    end})
    
    return steps
end

-- Main program
local function main()
    Version.printBanner("Wither Boss Farmer V2")
    
    -- Initialize network
    if not Network.init() then
        print("ERROR: No modem found!")
        return
    end
    
    -- Find farm computer
    print("Looking for wither_boss_farm...")
    context.farmComputerId = Network.lookup("wither_boss_farm")
    
    if not context.farmComputerId then
        print("ERROR: Could not find wither_boss_farm computer!")
        return
    end
    
    print("Found farm computer: " .. context.farmComputerId)
    
    -- Build step sequence
    local steps = buildSteps()
    print("Generated " .. #steps .. " steps")
    
    -- Execute with automatic checkpointing
    local success, err = Executor.run(steps, context, "wither_farm_checkpoint.txt")
    
    if not success then
        print("ERROR: " .. tostring(err))
        print("Checkpoint saved. Restart to resume.")
    else
        print("All withers built successfully!")
    end
end

-- Run the program
main()
