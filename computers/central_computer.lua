-- Central Command Computer v3
-- Monitors turtles + Resource Tracking with graphs

local Network = require("network")
local Updater = require("updater")

-- Try to load optional libraries (may not exist on first run)
local UI = nil
local State = nil
local Version = nil
local ResourceTracker = nil
local Graph = nil

local success, module = pcall(require, "ui")
if success then UI = module end

success, module = pcall(require, "state")
if success then State = module end

success, module = pcall(require, "version")
if success then Version = module end

success, module = pcall(require, "resource_tracker")
if success then ResourceTracker = module end

success, module = pcall(require, "graph")
if success then Graph = module end

-- If critical libraries are missing, show error and exit
if not UI or not State then
    print("ERROR: Missing required libraries!")
    print("Please run the updater to download:")
    if not UI then print("  - ui.lua") end
    if not State then print("  - state.lua") end
    print("")
    print("Run: shell.run('updater')")
    print("Or use the installer")
    return
end

-- Configuration
local HOSTNAME = "central"
local TELEMETRY_INTERVAL = 30
local DISPLAY_REFRESH = 2

-- Workers that cannot be paused (critical infrastructure)
local UNPAUSABLE_WORKERS = {
    ["Wither Boss Farm"] = true,  -- Door controller must always be running
    ["RS Monitor"] = true  -- RS Monitor must always run
}

-- State
local screen = nil
local turtles = {}
local centralState = {}
local resourceTracker = nil
local rsMonitorId = nil
local currentTab = 1  -- 1 = Workers, 2 = Resources
local selectedResource = nil

local stats = {
    totalTurtles = 0,
    activeTurtles = 0,
    pausedTurtles = 0,
    alerts = {},
    criticalWorkersMissing = {}
}

-- Check for critical workers
local function checkCriticalWorkers()
    stats.criticalWorkersMissing = {}
    
    for workerName, _ in pairs(UNPAUSABLE_WORKERS) do
        local found = false
        for id, turtle in pairs(turtles) do
            if turtle.name == workerName then
                found = true
                local timeSinceUpdate = os.epoch("utc") - turtle.lastUpdate
                if timeSinceUpdate > 60000 then
                    table.insert(stats.criticalWorkersMissing, workerName .. " (OFFLINE)")
                end
                break
            end
        end
        
        if not found then
            table.insert(stats.criticalWorkersMissing, workerName .. " (NOT FOUND)")
        end
    end
end

-- Toggle turtle mode
local function toggleTurtleMode(turtleId)
    local turtleName = turtles[turtleId] and turtles[turtleId].name or ("Turtle " .. turtleId)
    
    if UNPAUSABLE_WORKERS[turtleName] then
        table.insert(stats.alerts, os.date("%H:%M:%S") .. " - Cannot pause " .. turtleName .. " (critical)")
        return
    end
    
    local newMode = State.toggleTurtleMode(centralState, turtleId)
    
    Network.send(turtleId, Network.MSG_TYPES.COMMAND, {
        command = "set_mode",
        mode = newMode
    })
    
    table.insert(stats.alerts, os.date("%H:%M:%S") .. " - " .. turtleName .. " " .. newMode)
end

-- Draw Workers tab
local function drawWorkersTab()
    screen:clear()
    screen:clearButtons()
    
    checkCriticalWorkers()
    
    -- Header
    screen:setTextColor(colors.yellow)
    screen:print("=== WORKERS ===")
    local buildInfo = Version and (" | Build: " .. Version.get()) or ""
    screen:print("Computer ID: " .. os.getComputerID() .. buildInfo)
    screen:print("")
    
    -- Stats
    screen:setTextColor(colors.cyan)
    screen:print("Connected: " .. stats.totalTurtles .. " | Active: " .. stats.activeTurtles .. " | Paused: " .. stats.pausedTurtles)
    
    if #stats.criticalWorkersMissing > 0 then
        screen:setTextColor(colors.red)
        screen:print("CRITICAL: " .. table.concat(stats.criticalWorkersMissing, ", "))
    end
    
    screen:print("")
    screen:setTextColor(colors.white)
    
    local currentY = 7
    local screenWidth, screenHeight = screen:getSize()
    
    -- Draw turtle list
    for id, turtle in pairs(turtles) do
        if currentY >= screenHeight - 8 then break end
        
        local mode = State.getTurtleMode(centralState, id)
        local statusColor = colors.green
        local isUnpausable = UNPAUSABLE_WORKERS[turtle.name]
        
        if mode == "paused" then
            statusColor = colors.gray
        elseif turtle.status == "error" then
            statusColor = colors.red
        elseif turtle.status == "warning" then
            statusColor = colors.yellow
        end
        
        screen:setCursorPos(1, currentY)
        screen:setTextColor(colors.lightGray)
        screen:write("[" .. id .. "] ")
        screen:setTextColor(colors.white)
        screen:write(turtle.name)
        
        if isUnpausable then
            screen:setTextColor(colors.orange)
            screen:write(" [CRITICAL]")
        end
        
        if not isUnpausable then
            screen:setCursorPos(25, currentY)
            screen:setTextColor(statusColor)
            screen:write(mode == "paused" and "PAUSED" or turtle.status:upper())
        end
        
        -- Control button
        if isUnpausable then
            screen:setCursorPos(screenWidth - 8, currentY)
            screen:setTextColor(colors.gray)
            screen:setBackgroundColor(colors.lightGray)
            screen:write(" LOCKED ")
            screen:setBackgroundColor(colors.black)
        else
            local buttonColor = mode == "paused" and colors.green or colors.red
            local buttonText = mode == "paused" and "START" or "STOP"
            local button = UI.Button:new(screenWidth - 8, currentY, 7, 1, buttonText, function()
                toggleTurtleMode(id)
            end, buttonColor, colors.white)
            screen:addButton(button)
        end
        
        currentY = currentY + 2
    end
    
    -- Bottom buttons
    local buttonY = screenHeight - 3
    
    local updateBtn = UI.Button:new(2, buttonY, 10, 2, "UPDATE", function()
        Network.broadcast(Network.MSG_TYPES.COMMAND, {command = "update"})
        table.insert(stats.alerts, os.date("%H:%M:%S") .. " - Update broadcast")
    end, colors.blue, colors.white)
    screen:addButton(updateBtn)
    
    local refreshBtn = UI.Button:new(14, buttonY, 10, 2, "REFRESH", function()
        Network.broadcast(Network.MSG_TYPES.COMMAND, {command = "report_status"})
    end, colors.green, colors.white)
    screen:addButton(refreshBtn)
    
    -- Only show Resources button if libraries are loaded
    if ResourceTracker and Graph then
        local resourcesBtn = UI.Button:new(26, buttonY, 12, 2, "RESOURCES", function()
            currentTab = 2
        end, colors.purple, colors.white)
        screen:addButton(resourcesBtn)
    end
    
    local quitBtn = UI.Button:new(40, buttonY, 8, 2, "QUIT", function()
        error("User quit")
    end, colors.red, colors.white)
    screen:addButton(quitBtn)
    
    screen:drawButtons()
end

-- Draw Resources tab
local function drawResourcesTab()
    if not ResourceTracker or not Graph then
        currentTab = 1
        return
    end
    
    screen:clear()
    screen:clearButtons()
    
    screen:setTextColor(colors.yellow)
    screen:print("=== RESOURCE TRACKING ===")
    screen:print("")
    
    local screenWidth, screenHeight = screen:getSize()
    local trackedItems = ResourceTracker.getTrackedItems(resourceTracker)
    
    if #trackedItems == 0 then
        screen:setTextColor(colors.gray)
        screen:print("No resources tracked")
        screen:print("")
        screen:setTextColor(colors.white)
        screen:print("Resources will appear here when")
        screen:print("RS Monitor starts reporting data")
    else
        -- Show resource list
        local currentY = 4
        
        for i, itemName in ipairs(trackedItems) do
            if currentY >= screenHeight - 10 then break end
            
            local info = ResourceTracker.getResourceInfo(resourceTracker, itemName)
            if info then
                screen:setCursorPos(1, currentY)
                screen:setTextColor(colors.white)
                screen:write(info.displayName:sub(1, 25))
                
                screen:setCursorPos(27, currentY)
                screen:setTextColor(colors.cyan)
                screen:write(string.format("%d", info.count or 0))
                
                screen:setCursorPos(38, currentY)
                local flowRate = info.flowRate or 0
                local rateColor = flowRate >= 0 and colors.green or colors.red
                screen:setTextColor(rateColor)
                screen:write(string.format("%+.1f/min", flowRate))
                
                -- View button
                local viewBtn = UI.Button:new(screenWidth - 8, currentY, 7, 1, "VIEW", function()
                    selectedResource = itemName
                end, colors.blue, colors.white)
                screen:addButton(viewBtn)
                
                currentY = currentY + 1
            end
        end
        
        -- Show graph if resource selected
        if selectedResource then
            local info = ResourceTracker.getResourceInfo(resourceTracker, selectedResource)
            if info and #info.history > 0 then
                local graphY = math.min(currentY + 2, screenHeight - 15)
                local graphHeight = screenHeight - graphY - 5
                
                Graph.drawLineGraph(
                    screen.output,
                    1, graphY,
                    screenWidth, graphHeight,
                    info.history,
                    {
                        title = info.displayName,
                        color = colors.lime,
                        showGrid = true
                    }
                )
            end
        end
    end
    
    -- Bottom buttons
    local buttonY = screenHeight - 3
    
    local backBtn = UI.Button:new(2, buttonY, 10, 2, "WORKERS", function()
        currentTab = 1
        selectedResource = nil
    end, colors.blue, colors.white)
    screen:addButton(backBtn)
    
    local quitBtn = UI.Button:new(14, buttonY, 8, 2, "QUIT", function()
        error("User quit")
    end, colors.red, colors.white)
    screen:addButton(quitBtn)
    
    screen:drawButtons()
end

-- Update display
local function updateDisplay()
    if currentTab == 1 then
        drawWorkersTab()
    elseif currentTab == 2 then
        drawResourcesTab()
    end
end

-- Process telemetry
local function processTelemetry(turtleId, data)
    if not turtles[turtleId] then
        turtles[turtleId] = {
            name = data.name or ("Turtle " .. turtleId),
            status = "active",
            telemetry = {},
            lastUpdate = 0
        }
        stats.totalTurtles = stats.totalTurtles + 1
        
        -- Track RS Monitor
        if data.name == "RS Monitor" then
            rsMonitorId = turtleId
        end
        
        local mode = State.getTurtleMode(centralState, turtleId)
        Network.send(turtleId, Network.MSG_TYPES.COMMAND, {
            command = "set_mode",
            mode = mode
        })
    end
    
    local turtle = turtles[turtleId]
    turtle.name = data.name or turtle.name
    turtle.telemetry = data
    turtle.lastUpdate = os.epoch("utc")
    turtle.status = data.status or "active"
    
    -- Update resource tracking
    if ResourceTracker and data.resources then
        for itemName, itemData in pairs(data.resources) do
            if not resourceTracker.resources[itemName] then
                ResourceTracker.addItem(resourceTracker, itemName, itemData.displayName)
            end
            ResourceTracker.update(resourceTracker, itemName, itemData.count)
        end
        ResourceTracker.save(resourceTracker)
    end
    
    -- Update counts
    stats.activeTurtles = 0
    stats.pausedTurtles = 0
    for id, t in pairs(turtles) do
        local mode = State.getTurtleMode(centralState, id)
        if mode == "paused" then
            stats.pausedTurtles = stats.pausedTurtles + 1
        else
            stats.activeTurtles = stats.activeTurtles + 1
        end
    end
end

-- Handle messages
local function handleMessage(senderId, msgType, data)
    if msgType == Network.MSG_TYPES.TELEMETRY then
        processTelemetry(senderId, data)
    elseif msgType == Network.MSG_TYPES.COMMAND then
        if data.command == "request_mode" then
            local mode = State.getTurtleMode(centralState, senderId)
            Network.send(senderId, Network.MSG_TYPES.COMMAND, {
                command = "set_mode",
                mode = mode
            })
        elseif data.command == "toggle_worker" and data.workerId then
            toggleTurtleMode(data.workerId)
            
            -- Send updated worker list back to requester
            local workerData = {}
            for id, turtle in pairs(turtles) do
                workerData[id] = {
                    name = turtle.name,
                    status = turtle.status,
                    mode = State.getTurtleMode(centralState, id)
                }
            end
            
            Network.send(senderId, Network.MSG_TYPES.TELEMETRY, {
                workers = workerData
            })
        elseif data.command == "report_status" then
            -- Send worker list to requester
            local workerData = {}
            for id, turtle in pairs(turtles) do
                workerData[id] = {
                    name = turtle.name,
                    status = turtle.status,
                    mode = State.getTurtleMode(centralState, id)
                }
            end
            
            Network.send(senderId, Network.MSG_TYPES.TELEMETRY, {
                workers = workerData
            })
        end
    elseif msgType == Network.MSG_TYPES.HEARTBEAT then
        if turtles[senderId] then
            turtles[senderId].lastUpdate = os.epoch("utc")
        end
    elseif msgType == Network.MSG_TYPES.ALERT then
        if not turtles[senderId] then
            turtles[senderId] = {
                name = data.name or ("Turtle " .. senderId),
                status = "alert",
                telemetry = {},
                lastUpdate = os.epoch("utc")
            }
            stats.totalTurtles = stats.totalTurtles + 1
            
            local mode = State.getTurtleMode(centralState, senderId)
            Network.send(senderId, Network.MSG_TYPES.COMMAND, {
                command = "set_mode",
                mode = mode
            })
        end
        
        if data.name then
            turtles[senderId].name = data.name
        end
        
        if turtles[senderId].status ~= "error" then
            turtles[senderId].status = "alert"
        end
        
        local turtleName = turtles[senderId].name
        table.insert(stats.alerts, os.date("%H:%M:%S") .. " - " .. turtleName .. ": " .. data.message)
    end
end

-- Main
local function main()
    term.clear()
    term.setCursorPos(1, 1)
    
    if Version then
        Version.printBanner("Central Command v3 - Resource Tracking")
    else
        print("=================================")
        print("Central Command v3")
        print("=================================")
    end
    print("")
    
    -- Load state
    centralState = State.load()
    if ResourceTracker then
        resourceTracker = ResourceTracker.load()
        Version.log("Resource tracker loaded")
    end
    Version.log("State loaded")
    
    -- Check for updates
    Version.log("Checking for updates...")
    local results = Updater.updateLocal()
    local updated = false
    for filename, result in pairs(results) do
        if result.success then
            Version.log("Updated: " .. filename)
            updated = true
        end
    end
    
    if updated then
        Version.log("Updates applied, rebooting in 3 seconds...")
        sleep(3)
        os.reboot()
    end
    
    sleep(1)
    
    -- Check for monitor
    local monitorSide = nil
    for _, side in ipairs({"top", "bottom", "left", "right", "front", "back"}) do
        if peripheral.getType(side) == "monitor" then
            monitorSide = side
            Version.log("Monitor found on " .. side)
            break
        end
    end
    
    if monitorSide then
        local mon = peripheral.wrap(monitorSide)
        mon.setTextScale(0.5)
        screen = UI.Screen:new(mon)
    else
        Version.log("No monitor found, using terminal")
        screen = UI.Screen:new()
    end
    
    -- Initialize network
    if not Network.init() then
        Version.log("Error: No modem found!")
        return
    end
    
    Network.host(HOSTNAME)
    Version.log("Network initialized")
    sleep(1)
    
    -- Request telemetry
    Network.broadcast(Network.MSG_TYPES.COMMAND, {command = "report_status"})
    
    updateDisplay()
    
    -- Main loop
    local lastTelemetryRequest = os.epoch("utc")
    local lastDisplayUpdate = os.epoch("utc")
    local checkTimer = os.startTimer(0.5)
    
    while true do
        local event, param1, param2, param3 = os.pullEvent()
        
        if event == "timer" and param1 == checkTimer then
            while true do
                local senderId, msgType, data = Network.receive(0)
                if not senderId then break end
                handleMessage(senderId, msgType, data)
            end
            
            local now = os.epoch("utc")
            
            if (now - lastTelemetryRequest) > (TELEMETRY_INTERVAL * 1000) then
                Network.broadcast(Network.MSG_TYPES.COMMAND, {command = "report_status"})
                lastTelemetryRequest = now
            end
            
            if (now - lastDisplayUpdate) > (DISPLAY_REFRESH * 1000) then
                updateDisplay()
                lastDisplayUpdate = now
            end
            
            checkTimer = os.startTimer(0.5)
            
        elseif event == "rednet_message" then
            if param3 == Network.PROTOCOL then
                if type(param2) == "table" then
                    handleMessage(param1, param2.type, param2.data)
                end
            end
            
        elseif event == "monitor_touch" or event == "mouse_click" then
            local x, y = param2, param3
            screen:handleClick(x, y)
            updateDisplay()
            
        elseif event == "key" and param1 == keys.q then
            break
        end
    end
    
    Version.log("Shutting down...")
    Network.close()
end

main()
