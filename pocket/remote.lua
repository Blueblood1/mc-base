-- Pocket Computer Remote Control
-- Remote interface for central command system

local Network = require("network")
local UI = require("ui")
local Version = require("version")
local Updater = require("updater")

-- Try to load optional resource tracking
local ResourceTracker = nil
local Graph = nil

local success, module = pcall(require, "resource_tracker")
if success then ResourceTracker = module end

success, module = pcall(require, "graph")
if success then Graph = module end

-- Configuration
local CENTRAL_HOSTNAME = "central"
local TELEMETRY_INTERVAL = 5

-- Workers that cannot be paused (must match central computer)
local UNPAUSABLE_WORKERS = {
    ["Wither Boss Farm"] = true
}

-- State
local screen = nil
local tabBar = nil
local centralId = nil
local workers = {}
local resourceTracker = nil
local selectedResource = nil
local graphMode = "count"  -- "count" or "rate"
local stats = {
    totalWorkers = 0,
    activeWorkers = 0,
    pausedWorkers = 0
}

-- Send command to central computer
local function sendCommand(command, data)
    if not centralId then
        centralId = Network.lookup(CENTRAL_HOSTNAME)
    end
    
    if centralId ~= nil then
        data = data or {}
        data.command = command
        Network.send(centralId, Network.MSG_TYPES.COMMAND, data)
        return true
    else
        return false
    end
end

-- Toggle worker mode
local function toggleWorkerMode(workerId)
    -- Check if this worker can be paused
    local worker = workers[workerId]
    if worker and UNPAUSABLE_WORKERS[worker.name] then
        -- Don't send command for unpausable workers
        return
    end
    
    sendCommand("toggle_worker", {workerId = workerId})
    -- Request immediate status update
    sendCommand("report_status")
end

-- Request telemetry from central
local function requestTelemetry()
    if sendCommand("report_status") then
        -- Successfully sent
        return true
    else
        -- Try to reconnect
        centralId = Network.lookup(CENTRAL_HOSTNAME)
        return false
    end
end

-- Draw Control tab
local function drawControlTab()
    local w, h = screen:getSize()
    screen:clearButtons()
    
    -- Header info
    screen:setCursorPos(1, 3)
    screen:setTextColor(colors.cyan)
    screen:print("Workers: " .. stats.totalWorkers)
    screen:print("Active: " .. stats.activeWorkers)
    screen:print("Paused: " .. stats.pausedWorkers)
    
    -- Show connection status
    screen:setTextColor(colors.gray)
    if centralId then
        screen:print("Central: " .. tostring(centralId))
    else
        screen:print("Central: NONE")
    end
    
    if not centralId then
        screen:setTextColor(colors.red)
        screen:print("No central connection!")
    elseif stats.totalWorkers == 0 then
        screen:setTextColor(colors.yellow)
        screen:print("Waiting for data...")
    end
    
    screen:print("")
    screen:setTextColor(colors.white)
    
    local currentY = 8
    local maxY = h - 4
    
    -- Draw worker list (compact)
    for id, worker in pairs(workers) do
        if currentY >= maxY then
            break
        end
        
        local isUnpausable = UNPAUSABLE_WORKERS[worker.name]
        
        -- Worker name and status
        screen:setCursorPos(1, currentY)
        screen:setTextColor(colors.lightGray)
        screen:write("[" .. id .. "] ")
        
        screen:setTextColor(colors.white)
        local name = worker.name or ("Worker " .. id)
        if #name > 12 then
            name = name:sub(1, 12)
        end
        screen:write(name)
        
        -- Show if unpausable
        if isUnpausable then
            screen:setTextColor(colors.orange)
            screen:write(" [!]")
        end
        
        -- Status indicator (compact) - skip for unpausable workers
        if not isUnpausable then
            local statusColor = colors.green
            if worker.mode == "paused" then
                statusColor = colors.gray
            elseif worker.status == "error" then
                statusColor = colors.red
            elseif worker.status == "warning" then
                statusColor = colors.yellow
            end
            
            screen:setCursorPos(w - 5, currentY)
            screen:setTextColor(statusColor)
            screen:write(worker.mode == "paused" and "PAUSE" or "WORK")
        end
        
        -- Toggle button (disabled for unpausable workers)
        if isUnpausable then
            -- Show locked indicator
            screen:setCursorPos(w - 2, currentY)
            screen:setTextColor(colors.gray)
            screen:write("--")
        else
            -- Normal toggle button
            local btnColor = worker.mode == "paused" and colors.green or colors.red
            local btnText = worker.mode == "paused" and ">" or "||"
            local button = UI.Button:new(w - 2, currentY, 2, 1, btnText, function()
                toggleWorkerMode(id)
            end, btnColor, colors.white)
            screen:addButton(button)
        end
        
        currentY = currentY + 1
    end
    
    -- Bottom buttons
    local btnY = h - 2
    
    local refreshBtn = UI.Button:new(1, btnY, 8, 2, "REFRESH", function()
        local success = requestTelemetry()
        if not success then
            -- Show error on screen briefly
            screen:setCursorPos(1, btnY - 1)
            screen:setTextColor(colors.red)
            screen:write("No central!")
            sleep(1)
            updateDisplay()
        end
    end, colors.blue, colors.white)
    screen:addButton(refreshBtn)
    
    local quitBtn = UI.Button:new(w - 7, btnY, 7, 2, "QUIT", function()
        error("User quit")
    end, colors.red, colors.white)
    screen:addButton(quitBtn)
    
    screen:drawButtons()
end

-- Draw Status tab (placeholder)
local function drawStatusTab()
    if not ResourceTracker or not Graph then
        screen:clearButtons()
        screen:setCursorPos(1, 3)
        screen:setTextColor(colors.yellow)
        screen:print("Resources Tab")
        screen:setTextColor(colors.white)
        screen:print("")
        screen:print("Resource tracking")
        screen:print("libraries not loaded")
        
        local w, h = screen:getSize()
        local quitBtn = UI.Button:new(w - 7, h - 2, 7, 2, "QUIT", function()
            error("User quit")
        end, colors.red, colors.white)
        screen:addButton(quitBtn)
        screen:drawButtons()
        return
    end
    
    local w, h = screen:getSize()
    screen:clearButtons()
    
    local trackedItems = ResourceTracker.getTrackedItems(resourceTracker)
    
    if #trackedItems == 0 then
        screen:setCursorPos(1, 3)
        screen:setTextColor(colors.gray)
        screen:print("No resources tracked")
    else
        -- Show resource list
        local currentY = 3
        
        for i, itemName in ipairs(trackedItems) do
            if currentY >= h - 6 then break end
            
            local info = ResourceTracker.getResourceInfo(resourceTracker, itemName)
            if info then
                screen:setCursorPos(1, currentY)
                screen:setTextColor(colors.white)
                local displayName = info.displayName:sub(1, 15)
                screen:write(displayName)
                
                screen:setCursorPos(17, currentY)
                screen:setTextColor(colors.cyan)
                screen:write(string.format("%d", info.count or 0))
                
                screen:setCursorPos(23, currentY)
                local flowRate = info.flowRate or 0
                local rateColor = flowRate >= 0 and colors.green or colors.red
                screen:setTextColor(rateColor)
                screen:write(string.format("%+.0f", flowRate))
                
                -- View button
                local viewBtn = UI.Button:new(w - 2, currentY, 2, 1, ">", function()
                    selectedResource = itemName
                    updateDisplay()
                end, colors.blue, colors.white)
                screen:addButton(viewBtn)
                
                currentY = currentY + 1
            end
        end
        
        -- Show graph if resource selected
        if selectedResource then
            local info = ResourceTracker.getResourceInfo(resourceTracker, selectedResource)
            if info then
                local graphY = currentY + 1
                local graphHeight = h - graphY - 3
                
                if graphHeight > 5 then
                    -- Choose data based on graph mode
                    local graphData = graphMode == "rate" and info.rateHistory or info.history
                    local graphTitle = graphMode == "rate" 
                        and (info.displayName:sub(1, 12) .. " /min") 
                        or info.displayName:sub(1, 15)
                    
                    if #graphData > 0 then
                        Graph.drawLineGraph(
                            screen.output,
                            1, graphY,
                            w, graphHeight,
                            graphData,
                            {
                                title = graphTitle,
                                color = colors.lime,
                                showGrid = false  -- Less clutter on small screen
                            }
                        )
                    end
                end
            end
        end
    end
    
    -- Bottom buttons
    local btnY = h - 2
    
    if selectedResource then
        -- Back button
        local backBtn = UI.Button:new(1, btnY, 5, 2, "BACK", function()
            selectedResource = nil
            updateDisplay()
        end, colors.blue, colors.white)
        screen:addButton(backBtn)
        
        -- Graph mode toggles
        local countBtn = UI.Button:new(7, btnY, 6, 2, "COUNT", function()
            graphMode = "count"
            updateDisplay()
        end, graphMode == "count" and colors.green or colors.gray, colors.white)
        screen:addButton(countBtn)
        
        local rateBtn = UI.Button:new(14, btnY, 5, 2, "RATE", function()
            graphMode = "rate"
            updateDisplay()
        end, graphMode == "rate" and colors.green or colors.gray, colors.white)
        screen:addButton(rateBtn)
    end
    
    local quitBtn = UI.Button:new(w - 7, btnY, 7, 2, "QUIT", function()
        error("User quit")
    end, colors.red, colors.white)
    screen:addButton(quitBtn)
    
    screen:drawButtons()
end

-- Update display based on active tab
local function updateDisplay()
    screen:clear()
    
    -- Draw header
    screen:setTextColor(colors.yellow)
    screen:print("=== REMOTE CONTROL ===")
    
    -- Draw tab bar
    tabBar:draw(screen.output)
    
    -- Draw active tab content
    local activeTab, tabName = tabBar:getActiveTab()
    
    if tabName == "Control" then
        drawControlTab()
    elseif tabName == "Status" then
        drawStatusTab()
    elseif tabName == "Resources" then
        drawStatusTab()  -- Resources use the status tab function
    end
    
    screen:setTextColor(colors.white)
end

-- Process worker data from central
local function processWorkerData(data)
    -- Handle worker list
    if data.workers then
        local count = 0
        for _ in pairs(data.workers) do
            count = count + 1
        end
        
        if Version then
            Version.log("Received " .. count .. " workers from central")
        end
        
        workers = data.workers
        
        -- Update stats
        stats.totalWorkers = 0
        stats.activeWorkers = 0
        stats.pausedWorkers = 0
        
        for id, worker in pairs(workers) do
            stats.totalWorkers = stats.totalWorkers + 1
            if worker.mode == "paused" then
                stats.pausedWorkers = stats.pausedWorkers + 1
            else
                stats.activeWorkers = stats.activeWorkers + 1
            end
        end
        
        updateDisplay()
    end
    
    -- Handle resource data
    if ResourceTracker and data.resources then
        for itemName, itemData in pairs(data.resources) do
            if not resourceTracker.resources[itemName] then
                ResourceTracker.addItem(resourceTracker, itemName, itemData.displayName)
            end
            ResourceTracker.update(resourceTracker, itemName, itemData.count)
        end
        ResourceTracker.save(resourceTracker)
        updateDisplay()
    end
end

-- Handle incoming messages
local function handleMessage(senderId, msgType, data)
    if msgType == Network.MSG_TYPES.TELEMETRY then
        -- Handle telemetry from central
        processWorkerData(data)
    end
end

-- Main
local function main()
    term.clear()
    term.setCursorPos(1, 1)
    
    if Version then
        Version.printBanner("Pocket Remote Control")
    else
        print("=== Pocket Remote Control ===")
    end
    
    -- Check if pocket computer
    if not pocket then
        print("ERROR: This must run on a pocket computer!")
        return
    end
    
    print("")
    print("Initializing...")
    
    -- Initialize network
    if not Network.init() then
        print("ERROR: No modem found!")
        return
    end
    
    print("Network initialized")
    
    -- Find central computer
    print("Looking for central computer...")
    centralId = Network.lookup(CENTRAL_HOSTNAME)
    
    if not centralId then
        print("WARNING: Central computer not found")
        print("Will retry in background...")
    else
        print("Found central: " .. centralId)
    end
    
    sleep(2)
    
    -- Initialize UI
    screen = UI.Screen:new()
    
    -- Load resource tracker if available
    if ResourceTracker then
        resourceTracker = ResourceTracker.load()
        print("Resource tracking enabled")
    end
    
    -- Create tab bar
    local w, h = screen:getSize()
    local tabs = ResourceTracker and {"Control", "Resources"} or {"Control", "Status"}
    tabBar = UI.TabBar:new(1, 2, w, tabs)
    tabBar.onTabChange = function(index, name)
        updateDisplay()
    end
    
    -- Request initial data
    requestTelemetry()
    
    -- Initial display
    updateDisplay()
    
    -- Main loop with parallel message handling
    local function messageListener()
        while true do
            local event, param1, param2, param3 = os.pullEvent()
            if event == "rednet_message" then
                -- param1 = sender ID
                -- param2 = message
                -- param3 = protocol
                
                if param3 == Network.PROTOCOL then
                    -- Message is for our protocol
                    if type(param2) == "table" then
                        handleMessage(param1, param2.type, param2.data)
                    end
                end
            end
        end
    end
    
    local function uiLoop()
        local lastTelemetryRequest = os.epoch("utc")
        local checkTimer = os.startTimer(0.5)
        
        while true do
            local event, param1, param2, param3 = os.pullEvent()
            
            if event == "timer" and param1 == checkTimer then
                local now = os.epoch("utc")
                
                -- Periodic telemetry request
                if (now - lastTelemetryRequest) > (TELEMETRY_INTERVAL * 1000) then
                    requestTelemetry()
                    lastTelemetryRequest = now
                end
                
                checkTimer = os.startTimer(0.5)
                
            elseif event == "mouse_click" then
                local x, y = param2, param3
                
                -- Check tab bar first
                if tabBar:handleClick(x, y) then
                    -- Tab changed, display already updated
                else
                    -- Check buttons
                    screen:handleClick(x, y)
                end
            end
        end
    end
    
    -- Run both loops in parallel
    parallel.waitForAll(messageListener, uiLoop)
end

-- Run
local success, err = pcall(main)
if not success then
    term.clear()
    term.setCursorPos(1, 1)
    if err ~= "Terminated" and err ~= "User quit" then
        print("Error: " .. tostring(err))
    else
        print("Remote control closed")
    end
end

Network.close()
