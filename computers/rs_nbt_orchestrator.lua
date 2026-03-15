-- RS NBT Orchestrator
-- Adjacent to RS Bridge. Exports items one at a time to scan chest,
-- asks Inspector computer to check for NBT, then routes accordingly.

local Network = require("network")
local Updater = require("updater")
local Version = require("version")
local Worker = require("worker")

-- ============================================
-- CONFIGURATION
-- ============================================
local SCAN_CHEST_SIDE = "top"   -- Side scan chest is on (relative to RS Bridge)
local NBT_CHEST_SIDE  = "back"  -- Side NBT output chest is on (relative to RS Bridge)
local SCAN_INTERVAL   = 10      -- Seconds between full scans
local CACHE_FILE      = "nbt_cache.json"
local INSPECTOR_HOST  = "nbt_inspector"
local RESPONSE_TIMEOUT = 10     -- Seconds to wait for inspector response
local WORKER_NAME     = "RS NBT Orchestrator"
-- ============================================

local sharedState = {
    centralId = nil,
    centralConnected = false,
    operatingMode = "running",
    stopRequested = false
}

local nbtCache = {}  -- item name -> true/false

-- ============================================
-- Cache
-- ============================================
local function saveCache()
    local f = fs.open(CACHE_FILE, "w")
    f.write(textutils.serialiseJSON(nbtCache))
    f.close()
end

local function loadCache()
    if not fs.exists(CACHE_FILE) then return end
    local f = fs.open(CACHE_FILE, "r")
    local data = f.readAll()
    f.close()
    local ok, result = pcall(textutils.unserialiseJSON, data)
    if ok and type(result) == "table" then
        nbtCache = result
        local n = 0
        for _ in pairs(nbtCache) do n = n + 1 end
        Version.log("Cache loaded: " .. n .. " known item types")
    end
end

-- ============================================
-- Peripherals
-- ============================================
local function findRSBridge()
    local bridge = peripheral.find("rs_bridge")
    if not bridge then Version.log("ERROR: No RS Bridge found!") end
    return bridge
end

-- ============================================
-- Network helpers
-- ============================================
local function sendAlert(message, level)
    if sharedState.centralConnected then
        Network.send(sharedState.centralId, Network.MSG_TYPES.ALERT, {
            name = WORKER_NAME, message = message, level = level or "info"
        })
    end
end

local function sendTelemetry()
    if not sharedState.centralConnected then return end
    local nbtCount, cleanCount = 0, 0
    for _, v in pairs(nbtCache) do
        if v then nbtCount = nbtCount + 1 else cleanCount = cleanCount + 1 end
    end
    Network.send(sharedState.centralId, Network.MSG_TYPES.TELEMETRY, {
        name = WORKER_NAME,
        status = sharedState.operatingMode,
        knownNBT = nbtCount,
        knownClean = cleanCount
    })
end

-- Ask inspector to check the item currently in the scan chest.
-- Returns true/false/nil (nil = timeout or error)
local function askInspector(inspectorId, itemName)
    Network.send(inspectorId, Network.MSG_TYPES.COMMAND, {
        command = "check_item",
        itemName = itemName
    })

    local timer = os.startTimer(RESPONSE_TIMEOUT)
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "timer" and p1 == timer then
            Version.log("WARN: Inspector timed out for " .. itemName)
            return nil
        elseif event == "rednet_message" then
            if p3 == Network.PROTOCOL and type(p2) == "table" then
                if p2.type == Network.MSG_TYPES.RESPONSE and p2.data then
                    if p2.data.itemName == itemName then
                        os.cancelTimer(timer)
                        return p2.data.hasNBT
                    end
                end
            end
        end
    end
end

-- ============================================
-- Main scan
-- ============================================
local function scanAndFilter(bridge, inspectorId)
    local items = bridge.getItems()
    if not items then
        Version.log("WARNING: getItems() returned nil")
        return
    end

    local unknown, toExport = {}, {}
    for _, item in ipairs(items) do
        local cached = nbtCache[item.name]
        if cached == nil then
            table.insert(unknown, item)
        elseif cached == true then
            table.insert(toExport, item)
        end
    end

    Version.log("Scan: " .. #items .. " types | " .. #unknown .. " unknown | " .. #toExport .. " to export")

    -- Step 1: scan unknowns
    for _, item in ipairs(unknown) do
        Version.log("Scanning: " .. item.name)

        local moved = bridge.exportItem({name = item.name, count = 1}, SCAN_CHEST_SIDE)
        if not moved or moved == 0 then
            Version.log("  Could not extract " .. item.name .. ", skipping")
        else
            sleep(0.3)

            local hasNBT = askInspector(inspectorId, item.name)

            if hasNBT == nil then
                -- Timeout: import back and skip, will retry next scan
                Version.log("  No response, returning item to RS")
                bridge.importItem({name = item.name, count = 1}, SCAN_CHEST_SIDE)
            else
                Version.log("  " .. item.name .. " hasNBT=" .. tostring(hasNBT))
                nbtCache[item.name] = hasNBT
                saveCache()

                -- Always import back first
                bridge.importItem({name = item.name, count = 1}, SCAN_CHEST_SIDE)
                sleep(0.1)

                if hasNBT then
                    table.insert(toExport, item)
                end
            end
        end
    end

    -- Step 2: export confirmed NBT items to NBT chest
    for _, item in ipairs(toExport) do
        local moved = bridge.exportItem({name = item.name, count = item.count}, NBT_CHEST_SIDE)
        if moved and moved > 0 then
            Version.log("Exported NBT item: " .. item.name .. " x" .. moved)
        else
            Version.log("WARN: Could not export " .. item.name .. " (nbt chest full?)")
            sendAlert("NBT chest may be full - " .. item.name, "warning")
        end
    end
end

local function mainLoop()
    local bridge = findRSBridge()
    if not bridge then return end

    loadCache()

    -- Look up inspector
    Version.log("Looking up inspector...")
    local inspectorId = nil
    while not inspectorId do
        inspectorId = Network.lookup(INSPECTOR_HOST)
        if not inspectorId then
            Version.log("Waiting for inspector to come online...")
            sleep(3)
        end
    end
    Version.log("Inspector found: #" .. inspectorId)
    sendAlert(WORKER_NAME .. " started")

    while not sharedState.stopRequested do
        if sharedState.operatingMode == "running" then
            local ok, err = pcall(scanAndFilter, bridge, inspectorId)
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
