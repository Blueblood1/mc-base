-- RS NBT Report Computer
-- Scans Refined Storage and reports what percentage of item types
-- and total item counts have NBT data (components field).

local Network = require("network")
local Updater = require("updater")
local Version = require("version")
local Worker = require("worker")

-- ============================================
-- CONFIGURATION
-- ============================================
local SCAN_INTERVAL  = 30    -- Seconds between scans
local NBT_CHEST_SIDE = "top" -- Side of chest to export NBT items into (relative to RS Bridge)
local WORKER_NAME    = "RS NBT Report"
-- ============================================

local sharedState = {
    centralId = nil,
    centralConnected = false,
    operatingMode = "running",
    stopRequested = false
}

local lastReport = nil

local function findRSBridge()
    local bridge = peripheral.find("rs_bridge")
    if not bridge then Version.log("ERROR: No RS Bridge found!") end
    return bridge
end

local function sendAlert(message, level)
    if sharedState.centralConnected then
        Network.send(sharedState.centralId, Network.MSG_TYPES.ALERT, {
            name = WORKER_NAME, message = message, level = level or "info"
        })
    end
end

local function sendTelemetry()
    if not sharedState.centralConnected or not lastReport then return end
    Network.send(sharedState.centralId, Network.MSG_TYPES.TELEMETRY, {
        name = WORKER_NAME,
        status = sharedState.operatingMode,
        report = lastReport
    })
end

local function printReport(report)
    term.clear()
    term.setCursorPos(1, 1)
    Version.printBanner(WORKER_NAME)
    print("")
    print("=== NBT Item Report ===")
    print("")
    print("Item types:  " .. report.nbtTypes .. " / " .. report.totalTypes ..
          " (" .. report.typePercent .. "%)")
    print("Total items: " .. report.nbtCount .. " / " .. report.totalCount ..
          " (" .. report.countPercent .. "%)")
    print("")
    print("Top NBT item types:")
    for i, item in ipairs(report.topItems) do
        print("  " .. i .. ". " .. item.name .. " x" .. item.count)
        if i >= 10 then break end
    end
    print("")
    print("Last scan: " .. report.time)
    print("Next scan in " .. SCAN_INTERVAL .. "s")
end

local function scan(bridge)
    local items = bridge.getItems()
    if not items then
        Version.log("WARNING: getItems() returned nil")
        return
    end

    local totalTypes = #items
    local totalCount = 0
    local nbtTypes   = 0
    local nbtCount   = 0
    local nbtItems   = {}

    for _, item in ipairs(items) do
        totalCount = totalCount + item.count
        if item.components and next(item.components) ~= nil then
            nbtTypes = nbtTypes + 1
            nbtCount = nbtCount + item.count
            table.insert(nbtItems, item)
        end
    end

    -- Sort top NBT items by count descending
    table.sort(nbtItems, function(a, b) return a.count > b.count end)

    local typePercent  = totalTypes > 0 and math.floor(nbtTypes / totalTypes * 100) or 0
    local countPercent = totalCount > 0 and math.floor(nbtCount / totalCount * 100) or 0

    -- Format time
    local epoch = os.epoch("local")
    local s = math.floor(epoch / 1000)
    local time = string.format("%02d:%02d:%02d", math.floor(s/3600)%24, math.floor(s%3600/60), s%60)

    lastReport = {
        totalTypes    = totalTypes,
        nbtTypes      = nbtTypes,
        typePercent   = typePercent,
        totalCount    = totalCount,
        nbtCount      = nbtCount,
        countPercent  = countPercent,
        topItems      = nbtItems,
        time          = time
    }

    printReport(lastReport)

    -- Export all NBT items to the chest
    for _, item in ipairs(nbtItems) do
        local remaining = item.count
        while remaining > 0 do
            local moved = bridge.exportItem({name = item.name, count = remaining}, NBT_CHEST_SIDE)
            if moved and moved > 0 then
                Version.log("Exported: " .. item.name .. " x" .. moved)
                remaining = remaining - moved
            else
                Version.log("Chest full, waiting...")
                sleep(5)
            end
        end
    end

    sendTelemetry()
end

local function mainLoop()
    local bridge = findRSBridge()
    if not bridge then return end

    sendAlert(WORKER_NAME .. " started")

    while not sharedState.stopRequested do
        if sharedState.operatingMode == "running" then
            local ok, err = pcall(scan, bridge)
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
