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
    -- Format 1: Table with custom interval (in seconds)
    {
        name = "mysticalagriculture:inferium_essence",
        interval = 60  -- Poll every 5 seconds
    },
    {
        name = "mysticalagriculture:certus_quartz_essence",
        interval = 60
    },
    
    -- Format 2: Simple string uses default interval (5 seconds)
    -- "minecraft:diamond",
    
    -- Example: Slow-growing items can use longer intervals
    -- {
    --     name = "minecraft:wheat",
    --     interval = 30  -- Only check every 30 seconds
    -- },
}

local DEFAULT_INTERVAL = 5  -- Default poll interval in seconds
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
    local bridge = peripheral.find("rs_bridge")
    if not bridge then
        print("ERROR: No RS Bridge found!")
        print("Please connect this computer to an RS Bridge")
        return nil
    end
    return bridge
end

-- Parse tracked items config into normalized format
local function parseTrackedItems()
    local items = {}
    for _, item in ipairs(TRACKED_ITEMS) do
        if type(item) == "string" then
            -- Simple string format, use default interval
            table.insert(items, {
                name = item,
                interval = DEFAULT_INTERVAL,
                lastPoll = 0
            })
        elseif type(item) == "table" and item.name then
            -- Table format with custom interval
            table.insert(items, {
                name = item.name,
                interval = item.interval or DEFAULT_INTERVAL,
                lastPoll = 0
            })
        end
    end
    return items
end

-- Send telemetry for items that need polling
local function sendTelemetry(rsBridge, trackedItems, now)
    if not sharedState.centralConnected then
        return
    end
    
    local itemsToPoll = {}
    local shouldSend = false
    
    -- Check which items need polling
    for _, item in ipairs(trackedItems) do
        local timeSinceLastPoll = (now - item.lastPoll) / 1000  -- Convert to seconds
        if timeSinceLastPoll >= item.interval then
            table.insert(itemsToPoll, item)
            item.lastPoll = now
            shouldSend = true
        end
    end
    
    if not shouldSend then
        return
    end
    
    local data = {
        name = WORKER_NAME,
        status = "active",
        resources = {}
    }
    
    -- Get counts for items that need polling
    for _, item in ipairs(itemsToPoll) do
        local rsItem = rsBridge.getItem({name = item.name})
        if rsItem then
            data.resources[item.name] = {
                count = rsItem.count,
                displayName = rsItem.displayName
            }
            Version.log("Polled " .. item.name .. ": " .. rsItem.count)
        else
            data.resources[item.name] = {
                count = 0,
                displayName = item.name
            }
            Version.log("Item not found: " .. item.name)
        end
    end
    
    if next(data.resources) then
        Version.log("Sending telemetry with " .. #itemsToPoll .. " items")
        Network.send(sharedState.centralId, Network.MSG_TYPES.TELEMETRY, data)
    end
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
    
    -- Parse tracked items configuration
    local trackedItems = parseTrackedItems()
    Version.log("Tracking " .. #trackedItems .. " items")
    
    -- Log intervals for each item
    for _, item in ipairs(trackedItems) do
        Version.log(item.name .. " -> " .. item.interval .. "s interval")
    end
    
    while not sharedState.stopRequested do
        local now = os.epoch("utc")
        
        -- Poll items based on their individual intervals
        if sharedState.operatingMode == "running" then
            sendTelemetry(rsBridge, trackedItems, now)
        end
        
        -- Check for commands from central
        local senderId, msgType, data = Network.receive(0.5)
        if senderId and msgType == Network.MSG_TYPES.COMMAND then
            if data.command == "report_status" then
                -- Force poll all items immediately
                for _, item in ipairs(trackedItems) do
                    item.lastPoll = 0
                end
                sendTelemetry(rsBridge, trackedItems, os.epoch("utc"))
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
