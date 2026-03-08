-- Sheep Farmer (Step-Based with Atomic Actions)
-- Feeds wheat to sheep in a 14x11 grid pattern

local Executor = require("executor")
local Network = require("network")
local Version = require("version")
local Worker = require("worker")
local TurtleLib = require("turtle")
local Updater = require("updater")

-- Configuration
local TURTLE_NAME = "Sheep Farmer"
local FUEL_SLOT = 1
local WHEAT_SLOT = 2
local SHEARS_SLOT = 3
local TELEMETRY_INTERVAL = 30
local CYCLE_FUEL_REQUIREMENT = 100  -- 2 up + 1 forward + (14 rows * ~11 moves) + return path + 2 down = ~180 moves, use 100 as safe estimate

-- Shared context
local context = {}

-- Shared state for command listener
local sharedState = {
    centralId = nil,
    centralConnected = false,
    operatingMode = "running",
    stopRequested = false
}

-- Status tracking
local status = {
    cyclesCompleted = 0,
    lastError = nil
}

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
    
    local telemetryData = {
        name = os.getComputerLabel() or (TURTLE_NAME .. " #" .. os.getComputerID()),
        status = sharedState.operatingMode == "paused" and "idle" or "working",
        fuel = TurtleLib.getFuelStatus(),
        inventory = TurtleLib.getInventoryStatus(),
        task = {
            phase = sharedState.operatingMode == "paused" and "paused" or "farming",
            cyclesCompleted = status.cyclesCompleted
        },
        stats = {
            cyclesCompleted = status.cyclesCompleted
        }
    }
    
    if sharedState.centralId then
        Network.send(sharedState.centralId, Network.MSG_TYPES.TELEMETRY, telemetryData)
    else
        Network.broadcast(Network.MSG_TYPES.TELEMETRY, telemetryData)
    end
end

-- Custom action: Use shears downwards
local function useShearsDown(step, ctx)
    turtle.select(SHEARS_SLOT)
    turtle.placeDown()
    return true
end

-- Custom action: Place wheat downwards (only if we have wheat)
local function placeWheatDown(step, ctx)
    -- Only use wheat if we have it (ctx.hasWheat will be set during resource loading)
    if ctx and ctx.hasWheat then
        turtle.select(WHEAT_SLOT)
        turtle.placeDown()
    end
    return true
end

-- Build the step sequence with atomic actions only
local function buildSteps()
    local steps = {}
    
    -- Helper to add step
    local function add(step)
        table.insert(steps, step)
    end
    
    -- ===== LOAD FUEL =====
    add({action = "refuel_to_level", targetLevel = 2000, slot = FUEL_SLOT, chestSide = "right", log = "Checking fuel..."})
    
    -- ===== LOAD SHEARS =====
    -- Check if we have shears
    add({action = "function", log = "Checking shears...", func = function(ctx)
        turtle.select(SHEARS_SLOT)
        local itemDetail = turtle.getItemDetail()
        
        if not itemDetail or itemDetail.count == 0 then
            -- No shears, need to get them from chest above wheat chest (left side, up)
            ctx.needShears = true
        else
            ctx.needShears = false
        end
        return true
    end})
    
    -- Load shears from chest above wheat chest if needed
    add({action = "turn", direction = "left"})
    add({action = "move", direction = "up"})  -- Ascend to reach upper chest
    add({action = "function", func = function(ctx)
        if ctx.needShears then
            turtle.select(SHEARS_SLOT)
            turtle.suck(1)  -- Take 1 pair of shears from chest in front
        end
        return true
    end})
    add({action = "move", direction = "down"})  -- Descend back to starting level
    
    -- ===== LOAD WHEAT =====
    add({action = "select", slot = WHEAT_SLOT, log = "Loading wheat..."})
    add({action = "suck", side = "front"})
    add({action = "turn", direction = "right"})
    
    -- Check if we have wheat (optional - can still shear without wheat)
    add({action = "function", func = function(ctx)
        local wheatCount = turtle.getItemCount(WHEAT_SLOT)
        if wheatCount == 0 then
            ctx.hasWheat = false
            print("No wheat available - will only shear sheep")
        else
            ctx.hasWheat = true
            print("Wheat loaded - will shear and breed sheep")
        end
        return true
    end})
    
    -- ===== START FARMING =====
    -- Ascend twice
    add({action = "move", direction = "up", log = "Ascending to sheep pen..."})
    add({action = "move", direction = "up"})
    
    -- Move forward once to be above the first sheep position
    add({action = "move", direction = "forward"})
    
    -- Process 14 rows
    for row = 1, 14 do
        local isOddRow = (row % 2 == 1)
        
        if row == 1 then
            add({action = "function", log = "Starting row " .. row .. "...", func = function() return true end})
        else
            add({action = "function", log = "Row " .. row .. "...", func = function() return true end})
        end
        
        -- For each position in the row, use shears then place wheat down, then move forward
        -- Row 1: 11 forward moves (12 positions total including start)
        -- Rows 2-14: 10 forward moves (11 positions total)
        local forwardMoves = (row == 1) and 11 or 10
        
        for i = 1, forwardMoves do
            -- Use shears down at current position
            add({action = "function", func = useShearsDown})
            -- Place wheat down at current position
            add({action = "function", func = placeWheatDown})
            -- Move forward
            add({action = "move", direction = "forward"})
        end
        
        -- Use shears and place wheat at the final position of this row
        add({action = "function", func = useShearsDown})
        add({action = "function", func = placeWheatDown})
        
        -- At end of row, move to next row (except on last row)
        if row < 14 then
            if isOddRow then
                -- Odd row: turn left, move forward to next row, turn left to face back
                add({action = "turn", direction = "left"})
                add({action = "move", direction = "forward"})
                add({action = "turn", direction = "left"})
            else
                -- Even row: turn right, move forward to next row, turn right to face back  
                add({action = "turn", direction = "right"})
                add({action = "move", direction = "forward"})
                add({action = "turn", direction = "right"})
            end
        end
    end
    
    -- ===== RETURN TO START =====
    add({action = "function", log = "Returning to start...", func = function() return true end})
    
    -- After row 14 (even row), we're at the far end facing toward the start
    -- Turn left once
    add({action = "turn", direction = "left"})
    
    -- Move forward 13 times to get back to starting column
    for i = 1, 13 do
        add({action = "move", direction = "forward"})
    end
    
    -- Now right next to start, turn right
    add({action = "turn", direction = "right"})
    
    -- Move forward twice
    add({action = "move", direction = "forward"})
    add({action = "move", direction = "forward"})
    
    -- Turn 180 degrees
    add({action = "turn", direction = "right"})
    add({action = "turn", direction = "right"})
    
    -- Descend twice to return to starting position
    add({action = "move", direction = "down"})
    add({action = "move", direction = "down"})
    
    -- ===== DEPOSIT WOOL =====
    add({action = "turn", direction = "right", log = "Depositing wool..."})
    add({action = "move", direction = "up"})  -- Ascend to reach upper chest
    
    -- Deposit all items except fuel, wheat, and shears
    add({action = "function", func = function(ctx)
        for slot = 4, 16 do
            turtle.select(slot)
            local itemDetail = turtle.getItemDetail()
            if itemDetail then
                turtle.drop()  -- Drop into chest in front
            end
        end
        return true
    end})
    
    add({action = "move", direction = "down"})  -- Descend back to starting level
    add({action = "turn", direction = "left"})  -- Turn back to original orientation
    
    return steps
end

-- Install startup script
local function installStartup()
    if not fs.exists("startup") and not fs.exists("startup.lua") then
        Version.log("Installing startup file...")
        local file = fs.open("startup.lua", "w")
        file.write('-- Auto-start Sheep Farmer on boot\n')
        file.write('print("Checking for updates...")\n')
        file.write('local Updater = require("updater")\n')
        file.write('Updater.updateLocal()\n')
        file.write('print("Starting Sheep Farmer...")\n')
        file.write('shell.run("sheep_farmer")\n')
        file.close()
        Version.log("Startup file installed!")
    end
end

-- Main program
local function main()
    Version.printBanner("Sheep Farmer")
    
    -- Initialize network
    if not Network.init() then
        Version.log("Error: No modem found!")
        return
    end
    
    -- Set computer label
    if not os.getComputerLabel() then
        os.setComputerLabel(TURTLE_NAME .. "_" .. os.getComputerID())
    end
    
    -- Install startup script
    installStartup()
    
    -- Wait for connection to central
    Worker.waitForCentralConnection(sharedState, TURTLE_NAME)
    
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
            TurtleLib.checkPauseState(sharedState, sendTelemetry)
            
            Version.log("Starting cycle...")
            
            -- Proactive fuel check
            TurtleLib.ensureFuelForCycle(CYCLE_FUEL_REQUIREMENT, "right", sendAlert, sendTelemetry)
            TurtleLib.checkPauseState(sharedState, sendTelemetry)
            
            -- Build step sequence
            local steps = buildSteps()
            Version.log("Generated " .. #steps .. " atomic steps")
            
            -- Execute with automatic checkpointing
            local success, err = Executor.run(steps, context, "sheep_farm_checkpoint.txt")
            
            if success then
                -- Cycle completed successfully
                status.cyclesCompleted = status.cyclesCompleted + 1
                status.lastError = nil
                Version.log("Cycle complete! Total cycles: " .. status.cyclesCompleted)
                sendTelemetry()
                
                -- Wait before next cycle
                Version.log("Waiting 60 seconds before next cycle...")
                sleep(60)
            else
                -- Cycle failed - checkpoint saved automatically
                local errStr = tostring(err)
                Version.log("Cycle failed: " .. errStr)
                
                -- Send alert and telemetry
                sendAlert(errStr)
                status.lastError = errStr
                sendTelemetry()
                
                -- Wait before retrying
                Version.log("Waiting 60 seconds before retry...")
                sleep(60)
            end
            
            -- Send periodic telemetry
            local now = os.epoch("utc")
            if (now - lastTelemetry) > (TELEMETRY_INTERVAL * 1000) then
                sendTelemetry()
                lastTelemetry = now
            end
        end
        
        Version.log("Stopped by central computer")
        sendTelemetry()
    end
    
    -- Run main loop and command listener in parallel with error handling
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

-- Run the program
main()
