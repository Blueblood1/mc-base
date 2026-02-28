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

-- Get turtle label or ID
function TurtleLib.getIdentifier()
    return os.getComputerLabel() or "turtle_" .. os.getComputerID()
end

return TurtleLib
