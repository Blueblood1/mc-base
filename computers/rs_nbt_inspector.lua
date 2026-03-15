-- RS NBT Inspector
-- Adjacent to the scan chest. Receives check_item requests from the
-- orchestrator, inspects the chest contents for NBT, and responds.

local Network = require("network")
local Updater = require("updater")
local Version = require("version")

-- ============================================
-- CONFIGURATION
-- ============================================
local CHEST_SIDE  = "top"   -- Side the scan chest is on
local WORKER_NAME = "RS NBT Inspector"
local HOST_NAME   = "nbt_inspector"
-- ============================================

local function getChest()
    local chest = peripheral.wrap(CHEST_SIDE)
    if not chest then
        Version.log("ERROR: No chest found on " .. CHEST_SIDE)
    end
    return chest
end

local function chestHasNBT(chest)
    for slot = 1, chest.size() do
        local detail = chest.getItemDetail(slot)
        if detail then
            Version.log("  Slot " .. slot .. ": " .. detail.name)
            if detail.nbt and type(detail.nbt) == "table" and next(detail.nbt) then
                Version.log("  NBT found in slot " .. slot)
                return true
            end
        end
    end
    return false
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
    Network.host(HOST_NAME)
    Version.log("Hosting as: " .. HOST_NAME)

    local chest = getChest()
    if not chest then return end

    Version.log("Ready, waiting for requests...")

    while true do
        local event, p1, p2, p3 = os.pullEvent()

        if event == "rednet_message" then
            if p3 == Network.PROTOCOL and type(p2) == "table" then
                if p2.type == Network.MSG_TYPES.COMMAND then
                    local data = p2.data
                    if data and data.command == "check_item" then
                        Version.log("Checking: " .. tostring(data.itemName))
                        sleep(0.2) -- let chest settle

                        local hasNBT = chestHasNBT(chest)
                        Version.log("Result: hasNBT=" .. tostring(hasNBT))

                        Network.send(p1, Network.MSG_TYPES.RESPONSE, {
                            itemName = data.itemName,
                            hasNBT = hasNBT
                        })
                    end
                end
            end
        end
    end
end

main()
