-- Resource Tracker Library
-- Tracks item quantities over time and calculates flow rates

local ResourceTracker = {}

ResourceTracker.DATA_FILE = "resource_data.txt"
ResourceTracker.MAX_HISTORY = 720  -- 1 hour at 5-second intervals

-- Create a new tracker
function ResourceTracker.new()
    local tracker = {
        resources = {},  -- {itemName -> {history = {{time, count}}, lastCount, lastTime}}
        trackedItems = {}  -- List of item names to track
    }
    return tracker
end

-- Load tracker from file
function ResourceTracker.load()
    if fs.exists(ResourceTracker.DATA_FILE) then
        local file = fs.open(ResourceTracker.DATA_FILE, "r")
        local data = file.readAll()
        file.close()
        local loaded = textutils.unserialize(data)
        if loaded then
            return loaded
        end
    end
    return ResourceTracker.new()
end

-- Save tracker to file
function ResourceTracker.save(tracker)
    local file = fs.open(ResourceTracker.DATA_FILE, "w")
    file.write(textutils.serialize(tracker))
    file.close()
end

-- Add an item to track
function ResourceTracker.addItem(tracker, itemName, displayName)
    if not tracker.resources[itemName] then
        tracker.resources[itemName] = {
            displayName = displayName or itemName,
            history = {},
            lastCount = 0,
            lastTime = 0
        }
        table.insert(tracker.trackedItems, itemName)
        ResourceTracker.save(tracker)
    end
end

-- Remove an item from tracking
function ResourceTracker.removeItem(tracker, itemName)
    tracker.resources[itemName] = nil
    for i, name in ipairs(tracker.trackedItems) do
        if name == itemName then
            table.remove(tracker.trackedItems, i)
            break
        end
    end
    ResourceTracker.save(tracker)
end

-- Update item count
function ResourceTracker.update(tracker, itemName, count)
    local resource = tracker.resources[itemName]
    if not resource then
        return
    end
    
    local now = os.epoch("utc")
    
    -- Add to history
    table.insert(resource.history, {time = now, count = count})
    
    -- Trim history to max size
    while #resource.history > ResourceTracker.MAX_HISTORY do
        table.remove(resource.history, 1)
    end
    
    resource.lastCount = count
    resource.lastTime = now
end

-- Calculate flow rate (items per minute)
function ResourceTracker.getFlowRate(tracker, itemName, windowSeconds)
    windowSeconds = windowSeconds or 60  -- Default 1 minute
    
    local resource = tracker.resources[itemName]
    if not resource or #resource.history < 2 then
        return 0
    end
    
    local now = os.epoch("utc")
    local windowStart = now - (windowSeconds * 1000)
    
    -- Find first data point in window
    local startIdx = nil
    for i = #resource.history, 1, -1 do
        if resource.history[i].time <= windowStart then
            startIdx = i
            break
        end
    end
    
    -- If we don't have data going back the full window, use oldest available
    if not startIdx then
        startIdx = 1
    end
    
    local startData = resource.history[startIdx]
    local endData = resource.history[#resource.history]
    
    -- Check if data is valid
    if not startData or not endData or not startData.count or not endData.count then
        return 0
    end
    
    local timeDiff = (endData.time - startData.time) / 1000  -- Convert to seconds
    if timeDiff == 0 then
        return 0
    end
    
    local countDiff = endData.count - startData.count
    
    -- Extrapolate to full minute if we have less than a minute of data
    if timeDiff < windowSeconds then
        -- Calculate rate per second, then multiply by 60 for per minute
        local ratePerSecond = countDiff / timeDiff
        return ratePerSecond * 60
    else
        -- We have a full window, calculate normally
        local rate = (countDiff / timeDiff) * 60  -- Items per minute
        return rate
    end
end

-- Get current count
function ResourceTracker.getCount(tracker, itemName)
    local resource = tracker.resources[itemName]
    if resource then
        return resource.lastCount
    end
    return 0
end

-- Get history for graphing (returns last N points)
function ResourceTracker.getHistory(tracker, itemName, maxPoints)
    maxPoints = maxPoints or 60
    
    local resource = tracker.resources[itemName]
    if not resource then
        return {}
    end
    
    local history = {}
    local startIdx = math.max(1, #resource.history - maxPoints + 1)
    
    for i = startIdx, #resource.history do
        table.insert(history, {
            time = resource.history[i].time,
            count = resource.history[i].count
        })
    end
    
    return history
end

-- Get all tracked items
function ResourceTracker.getTrackedItems(tracker)
    return tracker.trackedItems
end

-- Get resource info
function ResourceTracker.getResourceInfo(tracker, itemName)
    local resource = tracker.resources[itemName]
    if not resource then
        return nil
    end
    
    return {
        displayName = resource.displayName,
        count = resource.lastCount,
        flowRate = ResourceTracker.getFlowRate(tracker, itemName, 60),
        history = ResourceTracker.getHistory(tracker, itemName, 60)
    }
end

return ResourceTracker
