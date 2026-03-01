-- Turtle Utility Library
-- Common functions for turtle operations and state management

local TurtleLib = {}

-- Get fuel level and percentage
function TurtleLib.getFuelStatus()
    local level = turtle.getFuelLevel()
    local limit = turtle.getFuelLimit()
    local percent = (level / limit) * 100
    
    return {
        level = level,
        limit = limit,
        percent = math.floor(percent)
    }
end

-- Get inventory status
function TurtleLib.getInventoryStatus()
    local slots = {}
    local emptySlots = 0
    
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item then
            slots[i] = {
                name = item.name,
                count = item.count
            }
        else
            emptySlots = emptySlots + 1
        end
    end
    
    return {
        slots = slots,
        emptySlots = emptySlots,
        totalSlots = 16
    }
end

-- Check if a specific item exists in inventory
function TurtleLib.hasItem(itemName, minCount)
    minCount = minCount or 1
    local total = 0
    
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and item.name == itemName then
            total = total + item.count
        end
    end
    
    return total >= minCount, total
end

-- Smart refuel - refuels from a specific slot if fuel is low
function TurtleLib.smartRefuel(fuelSlot, threshold)
    threshold = threshold or 100
    local fuel = turtle.getFuelLevel()
    
    if fuel < threshold then
        turtle.select(fuelSlot)
        if turtle.getItemCount(fuelSlot) > 0 then
            turtle.refuel(1)
            return true
        end
        return false
    end
    return true
end

-- Load fuel from chest with lava bucket support
-- Loads fuel until target percentage is reached
-- Uses all inventory slots temporarily, then returns unused items
-- direction: "front", "right", "left", "top", "bottom"
-- targetPercent: stop when fuel reaches this percentage (default 80)
function TurtleLib.loadFuelFromChest(direction, targetPercent)
    targetPercent = targetPercent or 80
    
    -- Turn to face the chest
    if direction == "right" then
        turtle.turnRight()
    elseif direction == "left" then
        turtle.turnLeft()
    elseif direction == "back" then
        turtle.turnRight()
        turtle.turnRight()
    end
    
    -- Step 1: Fill entire inventory with fuel from chest
    for slot = 1, 16 do
        turtle.select(slot)
        if direction == "top" then
            turtle.suckUp()
        elseif direction == "bottom" then
            turtle.suckDown()
        else
            turtle.suck()
        end
    end
    
    -- Step 2: Consume fuel from inventory until we hit target
    local fuel = TurtleLib.getFuelStatus()
    local success = false
    
    for slot = 1, 16 do
        if fuel.percent >= targetPercent then
            break
        end
        
        turtle.select(slot)
        local item = turtle.getItemDetail(slot)
        
        if item then
            if item.name == "minecraft:lava_bucket" then
                -- Use all lava buckets in this slot
                local count = item.count
                for i = 1, count do
                    if fuel.percent >= targetPercent then
                        break
                    end
                    turtle.refuel(1)
                    success = true
                    fuel = TurtleLib.getFuelStatus()
                end
            elseif item.name ~= "minecraft:bucket" then
                -- Try regular fuel (coal, etc), but skip empty buckets
                local count = turtle.getItemCount(slot)
                for i = 1, count do
                    if fuel.percent >= targetPercent then
                        break
                    end
                    if not turtle.refuel(1) then
                        break -- Not fuel
                    end
                    success = true
                    fuel = TurtleLib.getFuelStatus()
                end
            end
            -- If it's an empty bucket (minecraft:bucket), skip it
        end
    end
    
    -- Step 3: Return everything back to chest
    for slot = 1, 16 do
        turtle.select(slot)
        if turtle.getItemCount(slot) > 0 then
            if direction == "top" then
                turtle.dropUp()
            elseif direction == "bottom" then
                turtle.dropDown()
            else
                turtle.drop()
            end
        end
    end
    
    -- Turn back to original direction
    if direction == "right" then
        turtle.turnLeft()
    elseif direction == "left" then
        turtle.turnRight()
    elseif direction == "back" then
        turtle.turnRight()
        turtle.turnRight()
    end
    
    return success, fuel.percent
end

-- Get turtle label or ID
function TurtleLib.getIdentifier()
    return os.getComputerLabel() or "turtle_" .. os.getComputerID()
end

return TurtleLib
