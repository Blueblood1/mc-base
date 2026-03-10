-- RS Monitor Computer
-- Polls Refined Storage and sends resource data to central computer

local Network = require("network")
local Updater = require("updater")
local Version = require("version")
local Worker = require("worker")

-- ============================================
-- CONFIGURATION - Edit items to track here
-- ============================================
local TRACKED_ITEMS = {
    -- Mystical Agriculture
    "mysticalagriculture:inferium_essence",
    "mysticalagriculture:prudentium_essence",
    "mysticalagriculture:tertium_essence",
    "mysticalagriculture:imperium_essence",
    "mysticalagriculture:supremium_essence",
    
    -- Add more items here in format: "modid:item_name"
    -- Examples:
    -- "minecraft:diamond",
    -- "minecraft:iron_ingot",
    -- "thermal:iron_gear",
}

local POLL_INTERVAL = 5  -- Poll RS every 5 seconds
local WORKER_NAME = "RS Monitor"
-- ============================================

-- Shared state
local sharedState = {
    centralId = nil,
    centralConnected = false,
    operatingMode = "running",
    stopRequested = false
}

-- Find RS Bridge
local function findRSBridge()
    local bridge = peripheral.find("rsBridge")
    if not bridge then
        print("ERROR: No RS Bridge found!")
        print("Please connect this computer to an RS Bridge")
        return nil
    end
    return bridge
end

-- Send telemetry
local function sendTelemetry(rsBridge, trackedItems)
    if not sharedState.centralConnected then
        return
    end
    
    local data = {
        name = WORKER_NAME,
        status = "active",
        resources = {}
    }
    
    -- Get counts for tracked items
    for _, itemName in ipairs(trackedItems) do
        local item = rsBridge.getItem({name = itemName})
        if item then
            data.resources[itemName] = {
                count = item.amount,
                displayName = item.displayName
            }
        else
            data.resources[itemName] = {
                count = 0,
                displayName = itemName
            }
        end
    end
    
    Network.send(sharedState.centralId, Network.MSG_TYPES.TELEMETRY, data)
end

-- Send alert
local function sendAlert(message, level)
    if sharedState.centralConnected then
        Network.send(sharedState.centralId, Network.MSG_TYPES.ALERT, {
            name = WORKER_NAME,
            message = message,
            level = level or "info"
        })
    end
end

-- Main loop
local function mainLoop()
    local rsBridge = findRSBridge()
    if not rsBridge then
        return
    end
    
    Version.log("RS Bridge found, starting monitoring...")
    sendAlert("RS Monitor started")
    
    -- Use configured tracked items
    local trackedItems = TRACKED_ITEMS
    local lastPoll = 0
    
    while not sharedState.stopRequested do
        local now = os.epoch("utc")
        
        -- Poll RS at interval
        if (now - lastPoll) >= (POLL_INTERVAL * 1000) then
            if sharedState.operatingMode == "running" then
                sendTelemetry(rsBridge, trackedItems)
            end
            lastPoll = now
        end
        
        -- Check for commands from central
        local senderId, msgType, data = Network.receive(0.5)
        if senderId and msgType == Network.MSG_TYPES.COMMAND then
            if data.command == "report_status" then
                sendTelemetry(rsBridge, trackedItems)
            end
        end
        
        sleep(0.1)
    end
end

-- Main
local function main()
    term.clear()
    term.setCursorPos(1, 1)
    
    if Version then
        Version.printBanner(WORKER_NAME)
    else
        print("=================================")
        print(WORKER_NAME)
        print("=================================")
    end
    print("")
    
    -- Check for updates
    Version.log("Checking for updates...")
    local results = Updater.updateLocal()
    local updated = false
    for filename, result in pairs(results) do
        if result.success then
            Version.log("Updated: " .. filename)
            updated = true
        end
    end
    
    if updated then
        Version.log("Updates applied, rebooting in 3 seconds...")
        sleep(3)
        os.reboot()
    end
    
    -- Initialize network
    Network.init()
    Version.log("Network initialized")
    
    -- Wait for central connection
    Worker.waitForCentralConnection(sharedState, WORKER_NAME)
    
    -- Create command listener
    local commandListener = Worker.createCommandListener(sharedState, {
        sendAlert = sendAlert,
        sendTelemetry = function()
            -- Telemetry sent in main loop
        end
    })
    
    -- Run in parallel
    parallel.waitForAll(mainLoop, commandListener)
    
    Version.log("Shutting down...")
    Network.close()
end

-- Run
main()
