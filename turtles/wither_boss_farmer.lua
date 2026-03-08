-- Wither Boss Farmer (Step-Based with Atomic Actions)
-- Each step is a single atomic action for perfect recovery

local Executor = require("executor")
local Network = require("network")
local Version = require("version")
local Worker = require("worker")

-- Configuration
local TURTLE_NAME = "Wither Boss Farmer"
local FUEL_SLOT = 1
local SOUL_SAND_SLOT = 2
local SKULL_SLOT = 3
local TELEMETRY_INTERVAL = 30

-- Shared context
local context = {
    farmComputerId = nil
}

-- Shared state for command listener
local sharedState = {
    centralId = nil,
    centralConnected = false,
    operatingMode = "running",
    stopRequested = false
}

-- Status tracking
local status = {
    withersBuilt = 0,
    cyclesCompleted = 0,
    lastError = nil
}

-- Check if we have required resources
local function hasRequiredResources()
    local soulSandCount = turtle.getItemCount(SOUL_SAND_SLOT)
    local skullCount = turtle.getItemCount(SKULL_SLOT)
    
    -- Need 16 soul sand and 12 skulls for 4 withers
    return soulSandCount >= 16 and skullCount >= 12
end

-- Forward declarations
local sendAlert
local sendTelemetry

-- Send alert to central computer
sendAlert = function(message, level)
    if not sharedState.centralId then
        sharedState.centralId = Network.lookup("central")
    end
    
    if sharedState.centralId then
        Network.send(sharedState.centralId, Network.MSG_TYPES.ALERT, {
            worker = TURTLE_NAME,
            message = message,
            level = level or "info",
            timestamp = os.epoch("utc")
        })
    end
end

-- Send telemetry to central computer
sendTelemetry = function()
    if not sharedState.centralId then
        sharedState.centralId = Network.lookup("central")
    end
    
    local fuel = turtle.getFuelLevel()
    local fuelLimit = turtle.getFuelLimit()
    local fuelPercent = 0
    if fuelLimit > 0 then
        fuelPercent = math.floor((fuel / fuelLimit) * 100)
    end
    
    if sharedState.centralId then
        Network.send(sharedState.centralId, Network.MSG_TYPES.TELEMETRY, {
            name = os.getComputerLabel() or (TURTLE_NAME .. " #" .. os.getComputerID()),
            status = sharedState.operatingMode == "paused" and "idle" or "working",
            fuel = {
                current = fuel,
                limit = fuelLimit,
                percent = fuelPercent
            },
            task = {
                phase = sharedState.operatingMode == "paused" and "paused" or "farming",
                withersBuilt = status.withersBuilt,
                cyclesCompleted = status.cyclesCompleted
            },
            stats = {
                withersBuilt = status.withersBuilt,
                cyclesCompleted = status.cyclesCompleted
            }
        })
    end
end

-- Build the step sequence with atomic actions only
local function buildSteps()
    local steps = {}
    
    -- Helper to add step
    local function add(step)
        table.insert(steps, step)
    end
    
    -- Helper to add multiple moves
    local function addMoves(direction, count, log)
        if log then add({action = "function", log = log, func = function() return true end}) end
        for i = 1, count do
            add({action = "move", direction = direction})
        end
    end
    
    -- Helper to add multiple turns
    local function addTurns(direction, count)
        for i = 1, count do
            add({action = "turn", direction = direction})
        end
    end
    
    -- ===== LOAD FUEL =====
    add({action = "refuel_to_level", targetLevel = 5000, slot = FUEL_SLOT, chestSide = "right", log = "Checking fuel..."})
    
    -- ===== LOAD RESOURCES =====
    -- Check and load soul sand (left chest)
    add({action = "function", log = "Checking soul sand...", func = function(ctx)
        ctx.needSoulSand = turtle.getItemCount(SOUL_SAND_SLOT) < 16
        return true
    end})
    
    -- Only load if needed
    add({action = "turn", direction = "left"})
    add({action = "select", slot = SOUL_SAND_SLOT})
    add({action = "function", func = function(ctx)
        if ctx.needSoulSand then
            local current = turtle.getItemCount(SOUL_SAND_SLOT)
            turtle.suck(16 - current)
        end
        return true
    end})
    add({action = "turn", direction = "right"})
    
    -- Check and load skulls (back chest)
    add({action = "function", log = "Checking skulls...", func = function(ctx)
        ctx.needSkulls = turtle.getItemCount(SKULL_SLOT) < 12
        return true
    end})
    
    -- Only load if needed
    add({action = "turn", direction = "right"})
    add({action = "turn", direction = "right"})
    add({action = "select", slot = SKULL_SLOT})
    add({action = "function", func = function(ctx)
        if ctx.needSkulls then
            local current = turtle.getItemCount(SKULL_SLOT)
            turtle.suck(12 - current)
        end
        return true
    end})
    add({action = "turn", direction = "right"})
    add({action = "turn", direction = "right"})
    
    -- ===== START FARMING =====
    addMoves("forward", 2, "Moving to door 1...")
    add({action = "network_send", data = {command = "open_door", cell = 1}, log = "Opening door 1..."})
    addMoves("forward", 4, "Entering cell 1...")
    add({action = "network_send", data = {command = "close_door", cell = 1}, log = "Closing door 1..."})
    
    -- Build wither in cell 1
    addTurns("right", 2)
    add({action = "move", direction = "up", log = "Building wither in cell 1..."})
    add({action = "turn", direction = "right"})
    add({action = "move", direction = "forward"})
    add({action = "turn", direction = "left"})
    add({action = "place", slot = SOUL_SAND_SLOT})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SKULL_SLOT})
    add({action = "move", direction = "down"})
    add({action = "turn", direction = "left"})
    add({action = "move", direction = "forward"})
    add({action = "move", direction = "forward"})
    add({action = "turn", direction = "right"})
    add({action = "place", slot = SOUL_SAND_SLOT})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SKULL_SLOT})
    add({action = "move", direction = "down"})
    add({action = "turn", direction = "right"})
    add({action = "move", direction = "forward"})
    add({action = "turn", direction = "left"})
    add({action = "move", direction = "down"})
    add({action = "place", slot = SOUL_SAND_SLOT})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SOUL_SAND_SLOT})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SKULL_SLOT})  -- Spawns wither!
    add({action = "move", direction = "down"})
    add({action = "move", direction = "down"})
    
    -- Exit cell 1 to cell 2
    add({action = "network_send", data = {command = "open_door", cell = 2}, log = "Opening door 2..."})
    addTurns("right", 2)
    addMoves("forward", 4, "Moving to cell 2...")
    add({action = "network_send", data = {command = "close_door", cell = 2}, log = "Closing door 2..."})
    
    -- ===== CELL 2 =====
    addTurns("right", 2)
    add({action = "move", direction = "up", log = "Building wither in cell 2..."})
    add({action = "turn", direction = "right"})
    add({action = "move", direction = "forward"})
    add({action = "turn", direction = "left"})
    add({action = "place", slot = SOUL_SAND_SLOT})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SKULL_SLOT})
    add({action = "move", direction = "down"})
    add({action = "turn", direction = "left"})
    add({action = "move", direction = "forward"})
    add({action = "move", direction = "forward"})
    add({action = "turn", direction = "right"})
    add({action = "place", slot = SOUL_SAND_SLOT})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SKULL_SLOT})
    add({action = "move", direction = "down"})
    add({action = "turn", direction = "right"})
    add({action = "move", direction = "forward"})
    add({action = "turn", direction = "left"})
    add({action = "move", direction = "down"})
    add({action = "place", slot = SOUL_SAND_SLOT})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SOUL_SAND_SLOT})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SKULL_SLOT})  -- Spawns wither!
    add({action = "move", direction = "down"})
    add({action = "move", direction = "down"})
    
    -- Exit cell 2 to cell 3 (complex side path)
    add({action = "turn", direction = "left", log = "Exiting to cell 3..."})
    add({action = "network_send", data = {command = "open_door", cell = 3}})
    addMoves("forward", 6)
    add({action = "network_send", data = {command = "open_door", cell = 4}})
    addMoves("forward", 5)
    add({action = "turn", direction = "right"})
    add({action = "move", direction = "forward"})
    add({action = "move", direction = "forward"})
    addTurns("right", 2)
    add({action = "network_send", data = {command = "close_door", cell = 4}})
    
    -- ===== CELL 3 =====
    add({action = "move", direction = "up", log = "Building wither in cell 3..."})
    add({action = "turn", direction = "right"})
    add({action = "move", direction = "forward"})
    add({action = "turn", direction = "left"})
    add({action = "place", slot = SOUL_SAND_SLOT})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SKULL_SLOT})
    add({action = "move", direction = "down"})
    add({action = "turn", direction = "left"})
    add({action = "move", direction = "forward"})
    add({action = "move", direction = "forward"})
    add({action = "turn", direction = "right"})
    add({action = "place", slot = SOUL_SAND_SLOT})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SKULL_SLOT})
    add({action = "move", direction = "down"})
    add({action = "turn", direction = "right"})
    add({action = "move", direction = "forward"})
    add({action = "turn", direction = "left"})
    add({action = "move", direction = "down"})
    add({action = "place", slot = SOUL_SAND_SLOT})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SOUL_SAND_SLOT})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SKULL_SLOT})  -- Spawns wither!
    add({action = "move", direction = "down"})
    add({action = "move", direction = "down"})
    
    -- Exit cell 3 to cell 4
    add({action = "network_send", data = {command = "open_door", cell = 5}, log = "Opening door 5..."})
    addTurns("right", 2)
    addMoves("forward", 4, "Moving to cell 4...")
    add({action = "network_send", data = {command = "close_door", cell = 5}})
    
    -- ===== CELL 4 =====
    addTurns("right", 2)
    add({action = "move", direction = "up", log = "Building wither in cell 4..."})
    add({action = "turn", direction = "right"})
    add({action = "move", direction = "forward"})
    add({action = "turn", direction = "left"})
    add({action = "place", slot = SOUL_SAND_SLOT})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SKULL_SLOT})
    add({action = "move", direction = "down"})
    add({action = "turn", direction = "left"})
    add({action = "move", direction = "forward"})
    add({action = "move", direction = "forward"})
    add({action = "turn", direction = "right"})
    add({action = "place", slot = SOUL_SAND_SLOT})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SKULL_SLOT})
    add({action = "move", direction = "down"})
    add({action = "turn", direction = "right"})
    add({action = "move", direction = "forward"})
    add({action = "turn", direction = "left"})
    add({action = "move", direction = "down"})
    add({action = "place", slot = SOUL_SAND_SLOT})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SOUL_SAND_SLOT})
    add({action = "move", direction = "up"})
    add({action = "place", slot = SKULL_SLOT})  -- Spawns wither!
    add({action = "move", direction = "down"})
    add({action = "move", direction = "down"})
    
    -- ===== RETURN TO START =====
    addTurns("right", 2)
    add({action = "network_send", data = {command = "open_door", cell = 6}, log = "Returning to start..."})
    add({action = "move", direction = "forward"})
    add({action = "move", direction = "forward"})
    add({action = "network_send", data = {command = "close_door", cell = 6}})
    add({action = "turn", direction = "right"})
    addMoves("forward", 11)
    add({action = "turn", direction = "left"})
    add({action = "move", direction = "forward"})
    add({action = "move", direction = "forward"})
    addTurns("right", 2)
    
    return steps
end

-- Main program
local function main()
    Version.printBanner("Wither Boss Farmer")
    
    -- Initialize network
    if not Network.init() then
        print("ERROR: No modem found!")
        return
    end
    
    -- Wait for connection to central
    Worker.waitForCentralConnection(sharedState, TURTLE_NAME)
    
    -- Find farm computer
    print("Looking for wither_boss_farm...")
    context.farmComputerId = Network.lookup("wither_boss_farm")
    
    if not context.farmComputerId then
        print("ERROR: Could not find wither_boss_farm computer!")
        sendAlert("Could not find wither_boss_farm computer", "error")
        return
    end
    
    print("Found farm computer: " .. context.farmComputerId)
    
    -- Send initial telemetry
    sendTelemetry()
    
    -- Create command listener
    local commandListener = Worker.createCommandListener(sharedState, {
        sendAlert = sendAlert,
        sendTelemetry = sendTelemetry
    })
    
    -- Main loop function
    local function mainLoop()
        local lastTelemetry = os.epoch("utc")
        
        while not sharedState.stopRequested do
            -- Check if paused
            if sharedState.operatingMode == "paused" then
                print("Paused - waiting for resume...")
                sendTelemetry()
                sleep(5)
            else
                -- Check if we have required resources
                if not hasRequiredResources() then
                    local soulSandCount = turtle.getItemCount(SOUL_SAND_SLOT)
                    local skullCount = turtle.getItemCount(SKULL_SLOT)
                    
                    print("Insufficient resources!")
                    print("  Soul sand: " .. soulSandCount .. "/16")
                    print("  Skulls: " .. skullCount .. "/12")
                    
                    sendAlert("Insufficient resources (sand: " .. soulSandCount .. "/16, skulls: " .. skullCount .. "/12)", "warning")
                    status.lastError = "Waiting for resources"
                    sendTelemetry()
                    
                    -- Build steps will attempt to load resources
                    -- If chests are empty, suck will fail but that's okay
                    -- We'll check again after the cycle
                end
                
                -- Build step sequence (includes resource loading)
                local steps = buildSteps()
                print("Starting cycle with " .. #steps .. " atomic steps")
                
                -- Execute with automatic checkpointing
                local success, err = Executor.run(steps, context, "wither_farm_checkpoint.txt")
                
                if success then
                    -- Check if we actually got resources and completed the cycle
                    if hasRequiredResources() then
                        status.withersBuilt = status.withersBuilt + 4
                        status.cyclesCompleted = status.cyclesCompleted + 1
                        status.lastError = nil
                        print("Cycle complete! Total withers: " .. status.withersBuilt)
                        sendTelemetry()
                    else
                        -- Completed steps but didn't get resources
                        print("Cycle completed but insufficient resources for next run")
                        status.lastError = "Waiting for resources"
                        sendTelemetry()
                        sleep(60)  -- Wait before trying again
                    end
                else
                    status.lastError = tostring(err)
                    print("ERROR: " .. tostring(err))
                    sendAlert("Cycle failed: " .. tostring(err), "error")
                    sendTelemetry()
                    print("Checkpoint saved. Restart to resume.")
                    break
                end
            end
            
            -- Send periodic telemetry
            local now = os.epoch("utc")
            if (now - lastTelemetry) > (TELEMETRY_INTERVAL * 1000) then
                sendTelemetry()
                lastTelemetry = now
            end
        end
        
        print("Stopped by central computer")
        sendTelemetry()
    end
    
    -- Run main loop and command listener in parallel
    parallel.waitForAll(mainLoop, commandListener)
end

-- Run the program
main()
