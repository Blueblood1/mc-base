-- RS NBT Filter Computer
-- Scans RS items by extracting one at a time into a scan chest,
-- inspecting with CC's inventory API, then routing NBT items to
-- a separate chest. Results are cached to file to survive reboots.

local Network = require("network")
local Updater = require("updater")
local Version = require("version")
local Worker = require("worker")

-- ============================================
-- CONFIGURATION
-- ============================================
local SCAN_CHEST_SIDE = "top"    -- Chest to pull 1 item into for inspection
local NBT_CHEST_SIDE  = "back"   -- Chest to export confirmed NBT items into
local SCAN_INTERVAL   = 10       -- Seconds between full scans
local CACHE_FILE      = "nbt_cache.json"
local WORKER_NAME     = "RS NBT Filter"
-- ============================================

local sharedState = {
    centralId = nil,
    centralConnected = false,
    operatingMode = "running",
    stopRequested = false
}

-- Cache: item name -> true (has NBT) or false (no NBT)
local nbtCache = {}

-- ============================================
-- Cache persistence
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
        local count = 0
        for _ in pairs(nbtCache) do count = count + 1 end
        Version.log("Loaded cache: " .. count .. " known item types")
    else
        Version.log("WARNING: Failed to parse cache, starting fresh")
    end
end

-- ============================================
-- Peripheral helpers
-- ============================================
local function findRSBridge()
    local bridge = peripheral.find("rs_bridge")
    if not bridge then
        Version.log("ERROR: No RS Bridge found!")
    end
    return bridge
end

local function getChest(side)
    local chest = peripheral.wrap(side)
    if not chest then
        Version.log("ERROR: No inventory found on " .. side)
    end
    return chest
end

-- ============================================
-- NBT detection via CC inventory API
-- ============================================
local function chestHasNBTItem(chest)
    for slot = 1, chest.size() do
        local detail = chest.getItemDetail(slot)
        if detail then
            -- getItemDetail returns nbt as a table if present
            if detail.nbt and type(detail.nbt) == "table" and next(detail.nbt) then
                return true, detail
            end
        end
    end
    return false, nil
end

local function clearChest(bridge, chest, side)
    -- Import everything back from the scan chest into RS
    for slot = 1, chest.size() do
        local detail = chest.getItemDetail(slot)
        if detail then
            bridge.importItem({name = detail.name, count = detail.count}, side)
        end
    end
end

-- ============================================
-- Main scan logic
-- ============================================
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

local function scanAndFilter(bridge, scanChest, nbtChest)
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

    -- Step 1: scan unknown items one at a time
    for _, item in ipairs(unknown) do
        Version.log("Scanning: " .. item.name)

        -- Export 1 into scan chest
        local moved = bridge.exportItem({name = item.name, count = 1}, SCAN_CHEST_SIDE)
        if not moved or moved == 0 then
            Version.log("  Could not extract " .. item.name .. ", skipping")
        else
            sleep(0.2) -- let inventory update

            local hasNBT, detail = chestHasNBTItem(scanChest)
            if hasNBT then
                Version.log("  NBT detected: " .. item.name)
                nbtCache[item.name] = true
                table.insert(toExport, item)
            else
                Version.log("  No NBT: " .. item.name)
                nbtCache[item.name] = false
            end

            -- Return the sample back to RS
            clearChest(bridge, scanChest, SCAN_CHEST_SIDE)
            sleep(0.1)
        end

        saveCache()
    end

    -- Step 2: export all stacks of confirmed NBT items to nbt chest
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

    local scanChest = getChest(SCAN_CHEST_SIDE)
    if not scanChest then return end

    local nbtChest = getChest(NBT_CHEST_SIDE)
    if not nbtChest then return end

    loadCache()

    Version.log("Ready. Scan chest: " .. SCAN_CHEST_SIDE .. " | NBT chest: " .. NBT_CHEST_SIDE)
    sendAlert(WORKER_NAME .. " started")

    while not sharedState.stopRequested do
        if sharedState.operatingMode == "running" then
            local ok, err = pcall(scanAndFilter, bridge, scanChest, nbtChest)
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

-- ============================================
-- Boot
-- ============================================
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
