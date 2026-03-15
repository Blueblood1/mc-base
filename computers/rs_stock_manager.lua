-- RS Stock Manager
-- Maintains minimum stock levels by requesting autocrafting via RS Bridge.

local Network = require("network")
local Updater = require("updater")
local Version = require("version")
local Worker = require("worker")

-- ============================================
-- CONFIGURATION - Edit stock requirements here
-- ============================================
local STOCK_ITEMS = {
    -- { name = "item:id", min = amount }
    -- { name = "thermal:diamond_dust", min = 256 }
}

local CHECK_INTERVAL = 30   -- Seconds between stock checks
local WORKER_NAME    = "RS Stock Manager"
-- ============================================

local sharedState = {
    centralId = nil,
    centralConnected = false,
    operatingMode = "running",
    stopRequested = false
}

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

local function sendTelemetry(statuses)
    if not sharedState.centralConnected then return end
    Network.send(sharedState.centralId, Network.MSG_TYPES.TELEMETRY, {
        name = WORKER_NAME,
        status = sharedState.operatingMode,
        stock = statuses
    })
end

local function checkAndRestock(bridge)
    local statuses = {}

    for _, item in ipairs(STOCK_ITEMS) do
        local rsItem = bridge.getItem({name = item.name})
        local current = rsItem and rsItem.count or 0
        local needed  = item.min - current

        local status = {
            name    = item.name,
            current = current,
            min     = item.min,
            ok      = current >= item.min
        }

        if needed > 0 then
            -- Check if already crafting to avoid duplicate requests
            local crafting = bridge.isItemCrafting({name = item.name})
            if crafting then
                Version.log(item.name .. ": " .. current .. "/" .. item.min .. " (crafting...)")
                status.crafting = true
            else
                Version.log(item.name .. ": " .. current .. "/" .. item.min .. " - requesting " .. needed)
                local ok = bridge.craftItem({name = item.name, count = needed})
                if ok then
                    Version.log("  Craft requested ok")
                    status.crafting = true
                else
                    Version.log("  WARN: Craft request failed (no pattern?)")
                    sendAlert("Cannot craft " .. item.name .. " - no pattern?", "warning")
                    status.error = "no_pattern"
                end
            end
        else
            Version.log(item.name .. ": " .. current .. "/" .. item.min .. " ok")
        end

        table.insert(statuses, status)
    end

    sendTelemetry(statuses)
end

local function mainLoop()
    local bridge = findRSBridge()
    if not bridge then return end

    Version.log("Monitoring " .. #STOCK_ITEMS .. " item(s)")
    sendAlert(WORKER_NAME .. " started")

    while not sharedState.stopRequested do
        if sharedState.operatingMode == "running" then
            local ok, err = pcall(checkAndRestock, bridge)
            if not ok then
                Version.log("ERROR: " .. tostring(err))
                sendAlert("Error: " .. tostring(err), "error")
            end
        end

        local elapsed = 0
        while elapsed < CHECK_INTERVAL and not sharedState.stopRequested do
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
        sendTelemetry = function() checkAndRestock(findRSBridge()) end
    })

    parallel.waitForAll(mainLoop, commandListener)

    Version.log("Shutting down...")
    Network.close()
end

main()
