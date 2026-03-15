-- RS Mass Exporter
-- Continuously exports everything from the RS network into the chest below.

local Version = require("version")
local Updater = require("updater")

-- ============================================
-- CONFIGURATION
-- ============================================
local EXPORT_SIDE = "bottom" -- Side the output chest is on (relative to RS Bridge)
local WORKER_NAME = "RS Mass Exporter"
-- ============================================

local function findRSBridge()
    local bridge = peripheral.find("rs_bridge")
    if not bridge then Version.log("ERROR: No RS Bridge found!") end
    return bridge
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

    local bridge = findRSBridge()
    if not bridge then return end

    Version.log("Exporting to: " .. EXPORT_SIDE)
    Version.log("Running...")

    while true do
        local items = bridge.getItems()
        if items and #items > 0 then
            for _, item in ipairs(items) do
                bridge.exportItem({name = item.name, count = item.count}, EXPORT_SIDE)
            end
        end
    end
end

main()
