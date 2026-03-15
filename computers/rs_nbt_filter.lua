-- RS NBT Filter Computer
-- Scans Refined Storage for items with NBT data (via components field)
-- and exports them to an adjacent chest.

local Network = require("network")
local Updater = require("updater")
local Version = require("version")
local Worker = require("worker")

-- ============================================
-- CONFIGURATION
-- ============================================
local NBT_CHEST_SIDE = "top"   -- Side NBT output chest is on (relative to RS Bridge)
local SCAN_INTERVAL  = 10      -- Seconds between scans
local WORKER_NAME    = "RS NBT Filter"

-- Optional: restrict to specific item names. Empty = catch all NBT items.
local ITEM_NAME_FILTER = {
    -- "minecraft:enchanted_book",
}
-- ============================================

local sharedState = {
    centralId = nil,
    centralConnected = false,
    operatingMode = "running",
    stopRequested = false
}

local stats = { totalMoved = 0 }

local function findRSBridge()
    local bridge = peripheral.find("rs_bridge")
    if not bridge then Version.log("ERROR: No RS Bridge found!") end
    return bridge
end

local function hasComponents(item)
    return item.components ~= nil and next(item.components) ~= nil
end

local function nameFilterMatches(itemName)
    if #ITEM_NAME_FILTER == 0 then return true end
    for _, name in ipairs(ITEM_NAME_FILTER) do
        if itemName == name then return true end
    end
    return false
end

local function sendAlert(message, level)
    if sharedState.centralConnected then
        Network.send(sharedState.centralId, Network.MSG_TYPES.ALERT, {
            name = WORKER_NAME, message = message, level = level or "info"
        })
    end
end

local function sendTelemetry()
    if not sharedState.centralConnected then return end
    Network.send(sharedState.centralId, Network.MSG_TYPES.TELEMETRY, {
        name = WORKER_NAME,
        status = sharedState.operatingMode,
        totalMoved = stats.totalMoved
    })
end

local function scanAndFilter(bridge)
    local items = bridge.getItems()
    if not items then
        Version.log("WARNING: getItems() returned nil")
        return
    end

    local nbtItems = {}
    for _, item in ipairs(items) do
        if hasComponents(item) and nameFilterMatches(item.name) then
            table.insert(nbtItems, item)
        end
    end

    Version.log("Scan: " .. #items .. " types, " .. #nbtItems .. " with components")

    for _, item in ipairs(nbtItems) do
        local moved = bridge.exportItem({name = item.name, count = item.count}, NBT_CHEST_SIDE)
        if moved and moved > 0 then
            Version.log("Exported: " .. item.name .. " x" .. moved)
            stats.totalMoved = stats.totalMoved + moved
        else
            Version.log("WARN: Could not export " .. item.name .. " (chest full?)")
            sendAlert("NBT chest may be full - " .. item.name, "warning")
        end
    end

    if #nbtItems > 0 then
        sendTelemetry()
    end
end

local function mainLoop()
    local bridge = findRSBridge()
    if not bridge then return end

    Version.log("Ready. Exporting NBT items to: " .. NBT_CHEST_SIDE)
    sendAlert(WORKER_NAME .. " started")

    while not sharedState.stopRequested do
        if sharedState.operatingMode == "running" then
            local ok, err = pcall(scanAndFilter, bridge)
            if not ok then
                Version.log("ERROR: " .. tostring(err))
                sendAlert("Scan error: " .. tostring(err), "error")
            end
        end

        local elapsed = 0
        while elapsed < SCAN_INTERVAL and not sharedState.stopRequested do
            sleep(0.5)
            elapsed = elapsed + 0.5
        end
    end
end

local function main()
    term.clear()
    term.setCursorPos(1, 1)
    Version.printBanner(WORKER_NAME)
    print("")

    Version.log("Checking for updates...")
    local results = Updater.updateLocal()
    local updated = false
    for _, result in pairs(results) do
        if result.success then updated = true end
    end
    if updated then
        Version.log("Updates applied, rebooting...")
        sleep(3)
        os.reboot()
    end

    Network.init()
    Version.log("Network initialized")

    Worker.waitForCentralConnection(sharedState, WORKER_NAME)

    local commandListener = Worker.createCommandListener(sharedState, {
        sendAlert = sendAlert,
        sendTelemetry = sendTelemetry
    })

    parallel.waitForAll(mainLoop, commandListener)

    Version.log("Shutting down...")
    Network.close()
end

main()
