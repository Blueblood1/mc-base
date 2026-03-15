-- RS NBT Filter Computer
-- Continuously scans Refined Storage for items with NBT data
-- and exports them to an adjacent chest

local Network = require("network")
local Updater = require("updater")
local Version = require("version")
local Worker = require("worker")

-- ============================================
-- CONFIGURATION
-- ============================================
local SCAN_INTERVAL = 5          -- Seconds between scans
local EXPORT_CHEST_SIDE = "top"  -- Side the output chest is on (top/bottom/left/right/front/back)
local WORKER_NAME = "RS NBT Filter"

-- Optional: only filter NBT items matching these item names.
-- Leave empty to catch ALL items with NBT data.
local ITEM_NAME_FILTER = {
    -- "minecraft:enchanted_book",
    -- "minecraft:potion",
}
-- ============================================

-- Shared state
local sharedState = {
    centralId = nil,
    centralConnected = false,
    operatingMode = "running",
    stopRequested = false
}

-- Stats
local stats = {
    totalMoved = 0,
    lastScanCount = 0,
    lastScanTime = "never"
}

local function findRSBridge()
    local bridge = peripheral.find("rs_bridge")
    if not bridge then
        Version.log("ERROR: No RS Bridge found!")
        return nil
    end
    return bridge
end

local function hasNBT(item)
    -- nbt is an MD5 hash string per AP docs, e.g. "ae70053c97f877de546b0248b9ddf525"
    if item.nbt == nil then return false end
    if type(item.nbt) == "string" then
        return item.nbt ~= ""
    end
    return false
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
            name = WORKER_NAME,
            message = message,
            level = level or "info"
        })
    end
end

local function sendTelemetry()
    if not sharedState.centralConnected then return end
    Network.send(sharedState.centralId, Network.MSG_TYPES.TELEMETRY, {
        name = WORKER_NAME,
        status = sharedState.operatingMode,
        totalMoved = stats.totalMoved,
        lastScanCount = stats.lastScanCount,
        lastScanTime = stats.lastScanTime
    })
end

-- Export a single NBT item to the adjacent chest.
local function exportItem(bridge, item)
    local filter = {
        name = item.name,
        count = item.count,
        nbt = item.nbt
    }
    local moved = bridge.exportItem(filter, EXPORT_CHEST_SIDE)
    return moved and moved > 0
end

local function scanAndFilter(bridge)
    local items = bridge.getItems()
    if not items then
        Version.log("WARNING: getItems() returned nil")
        return
    end

    Version.log("Scan: " .. #items .. " total items in RS")

    -- Debug: print all fields of the first 3 items so we can see the data structure
    for i = 1, math.min(3, #items) do
        local item = items[i]
        Version.log("Item[" .. i .. "] fields:")
        for k, v in pairs(item) do
            Version.log("  " .. tostring(k) .. " = " .. tostring(v))
        end
    end

    local nbtItems = {}
    local nbtCount = 0
    for _, item in ipairs(items) do
        if hasNBT(item) then
            nbtCount = nbtCount + 1
            if nameFilterMatches(item.name) then
                table.insert(nbtItems, item)
                Version.log("  NBT match: " .. item.name .. " nbt=" .. tostring(item.nbt))
            else
                Version.log("  NBT (filtered out): " .. item.name)
            end
        end
    end

    if nbtCount == 0 then
        Version.log("No NBT items found this scan")
    end

    stats.lastScanCount = #nbtItems
    stats.lastScanTime = tostring(os.epoch("local") / 1000)

    if #nbtItems == 0 then
        return
    end

    Version.log("Exporting " .. #nbtItems .. " NBT item type(s)...")

    for _, item in ipairs(nbtItems) do
        local ok = exportItem(bridge, item)
        if ok then
            Version.log("Exported: " .. item.name .. " x" .. item.count)
            stats.totalMoved = stats.totalMoved + item.count
        else
            Version.log("WARN: Failed to export " .. item.name .. " (chest full?)")
            sendAlert("Failed to export " .. item.name .. " - chest may be full", "warning")
        end
    end

    sendTelemetry()
end

local function mainLoop()
    local bridge = findRSBridge()
    if not bridge then return end

    print(bridge)

    Version.log("RS Bridge found. Scanning every " .. SCAN_INTERVAL .. "s")
    Version.log("Exporting NBT items to: " .. EXPORT_CHEST_SIDE)
    sendAlert(WORKER_NAME .. " started")

    while not sharedState.stopRequested do
        if sharedState.operatingMode == "running" then
            local ok, err = pcall(scanAndFilter, bridge)
            if not ok then
                Version.log("ERROR during scan: " .. tostring(err))
                sendAlert("Scan error: " .. tostring(err), "error")
            end
        end

        -- Sleep in small increments so stop requests are noticed quickly
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
        if result.success then
            updated = true
        end
    end
    if updated then
        Version.log("Updates applied, rebooting in 3 seconds...")
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
