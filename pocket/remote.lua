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
    ["Wither Boss Farm"] = true,
    ["RS Monitor"] = true
}

-- State
local screen = nil
local tabBar = nil
local centralId = nil
local workers = {}
local resourceTracker = nil
local selectedResource = nil
local selectedWorker = nil  -- worker ID for command panel
local graphMode = "count"  -- "count" or "rate"
local stats = {
    totalWorkers = 0,
    activeWorkers = 0,
    pausedWorkers = 0
}

-- Forward declaration
local updateDisplay

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

-- Draw per-worker command panel (full screen on pocket)
local function drawWorkerPanel(id)
    local worker = workers[id]
    if not worker then selectedWorker = nil; return end

    local w, h = screen:getSize()
    screen:clearButtons()

    -- Header
    screen:setCursorPos(1, 3)
    screen:setTextColor(colors.yellow)
    local name = worker.name or ("Worker " .. id)
    screen:print(("[%d] %s"):format(id, name):sub(1, w))

    -- Info
    screen:setTextColor(colors.white)
    screen:print("Status: " .. (worker.status or "unknown"))
    screen:print("Mode:   " .. (worker.mode or "unknown"))

    if worker.telemetry and worker.telemetry.fuel then
        local f = worker.telemetry.fuel
        screen:print("Fuel:   " .. f.level .. " (" .. f.percent .. "%)")
    end

    if worker.telemetry and worker.telemetry.task then
        local t = worker.telemetry.task
        local taskStr = t.phase or "idle"
        if t.farm then taskStr = taskStr .. " farm " .. t.farm end
        screen:print("Task:   " .. taskStr:sub(1, w - 8))
    end

    screen:print("")
    screen:setTextColor(colors.gray)
    screen:print("--- Commands ---")

    local btnY = 10
    local isUnpausable = UNPAUSABLE_WORKERS[worker.name]

    -- UPDATE
    local updateBtn = UI.Button:new(1, btnY, w, 2, "UPDATE (reload config)", function()
        sendCommand("send_worker_command", {workerId = id, workerCommand = "update"})
        table.insert(stats and stats.alerts or {}, "Update sent to " .. name)
        selectedWorker = nil
        updateDisplay()
    end, colors.blue, colors.white)
    screen:addButton(updateBtn)

    -- STATUS
    local statusBtn = UI.Button:new(1, btnY + 3, w, 2, "REQUEST STATUS", function()
        sendCommand("send_worker_command", {workerId = id, workerCommand = "report_status"})
        selectedWorker = nil
        updateDisplay()
    end, colors.green, colors.white)
    screen:addButton(statusBtn)

    -- STOP / START
    if not isUnpausable then
        local mode = worker.mode or "running"
        local btnColor = mode == "paused" and colors.green or colors.red
        local btnText = mode == "paused" and "START WORKER" or "STOP WORKER"
        local toggleBtn = UI.Button:new(1, btnY + 6, w, 2, btnText, function()
            toggleWorkerMode(id)
            selectedWorker = nil
            updateDisplay()
        end, btnColor, colors.white)
        screen:addButton(toggleBtn)
    end

    -- BACK
    local backBtn = UI.Button:new(1, h - 2, w, 2, "< BACK", function()
        selectedWorker = nil
        updateDisplay()
    end, colors.lightGray, colors.black)
    screen:addButton(backBtn)

    screen:drawButtons()
end

-- Draw Control tab
local function drawControlTab()
    local w, h = screen:getSize()

    -- If a worker is selected, show its command panel instead
    if selectedWorker then
        drawWorkerPanel(selectedWorker)
        return
    end

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

    local currentY = 9
    local maxY = h - 4

    -- Draw worker list - each row is tappable to open command panel
    for id, worker in pairs(workers) do
        if currentY >= maxY then break end

        local isUnpausable = UNPAUSABLE_WORKERS[worker.name]

        screen:setCursorPos(1, currentY)
        screen:setTextColor(colors.lightGray)
        screen:write("[" .. id .. "] ")

        screen:setTextColor(colors.white)
        local name = worker.name or ("Worker " .. id)
        screen:write(name:sub(1, w - 10))

        if isUnpausable then
            screen:setTextColor(colors.orange)
            screen:write(" !")
        end

        -- Status indicator
        local statusColor = colors.green
        if worker.mode == "paused" then statusColor = colors.gray
        elseif worker.status == "error" then statusColor = colors.red end

        screen:setCursorPos(w - 6, currentY)
        screen:setTextColor(statusColor)
        screen:write(worker.mode == "paused" and "STP" or "RUN")

        -- Small tap button at right edge to open command panel
        local rowBtn = UI.Button:new(w - 2, currentY, 3, 1, "[>]", function()
            selectedWorker = id
            updateDisplay()
        end, colors.cyan, colors.black)
        screen:addButton(rowBtn)

        currentY = currentY + 1
    end

    -- Bottom buttons
    local btnY = h - 2

    local refreshBtn = UI.Button:new(1, btnY, 8, 2, "REFRESH", function()
        local ok = requestTelemetry()
        if not ok then
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
    elseif selectedResource then
        -- Full-screen graph view for selected resource
        local info = ResourceTracker.getResourceInfo(resourceTracker, selectedResource)
        if info then
            -- Show resource name and stats at top
            screen:setCursorPos(1, 3)
            screen:setTextColor(colors.white)
            screen:print(info.displayName:sub(1, w))
            
            screen:setCursorPos(1, 4)
            screen:setTextColor(colors.cyan)
            screen:write("Count: " .. string.format("%d", info.count or 0))
            
            local flowRate = info.flowRate or 0
            local rateColor = flowRate >= 0 and colors.green or colors.red
            screen:setCursorPos(1, 5)
            screen:setTextColor(rateColor)
            screen:write("Rate: " .. string.format("%+.0f/m", flowRate))
            
            -- Time span label
            screen:setCursorPos(1, 6)
            screen:setTextColor(colors.gray)
            screen:write("Last 2 min")
            
            -- Draw full-screen graph
            local graphY = 7
            local graphHeight = h - graphY - 3
            
            if graphHeight > 5 then
                local graphData = graphMode == "rate" and info.rateHistory or info.history
                local graphTitle = graphMode == "rate" and "Rate (items/min)" or "Count"
                
                -- Use only last 20 points for pocket computer (about 2 minutes)
                local limitedData = {}
                local startIdx = math.max(1, #graphData - 19)
                for i = startIdx, #graphData do
                    table.insert(limitedData, graphData[i])
                end
                
                if #limitedData > 0 then
                    Graph.drawLineGraph(
                        screen.output,
                        1, graphY,
                        w, graphHeight,
                        limitedData,
                        {
                            title = graphTitle,
                            color = colors.lime,
                            showGrid = false
                        }
                    )
                else
                    screen:setCursorPos(1, graphY)
                    screen:setTextColor(colors.gray)
                    screen:print("No data yet...")
                end
            end
        end
    else
        -- Show resource list (compact for narrow screen)
        local currentY = 3
        
        for i, itemName in ipairs(trackedItems) do
            if currentY >= h - 4 then break end
            
            local info = ResourceTracker.getResourceInfo(resourceTracker, itemName)
            if info then
                -- Line 1: Name
                screen:setCursorPos(1, currentY)
                screen:setTextColor(colors.white)
                local displayName = info.displayName:sub(1, w - 3)
                screen:write(displayName)
                
                -- View button on same line
                local viewBtn = UI.Button:new(w - 1, currentY, 1, 1, ">", function()
                    selectedResource = itemName
                    updateDisplay()
                end, colors.blue, colors.white)
                screen:addButton(viewBtn)
                
                currentY = currentY + 1
                
                -- Line 2: Count and Rate
                screen:setCursorPos(1, currentY)
                screen:setTextColor(colors.cyan)
                screen:write(string.format("%d", info.count or 0))
                
                local flowRate = info.flowRate or 0
                local rateColor = flowRate >= 0 and colors.green or colors.red
                screen:setCursorPos(w - 6, currentY)
                screen:setTextColor(rateColor)
                screen:write(string.format("%+.0f/m", flowRate))
                
                currentY = currentY + 1
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
    else
        -- Clear button when viewing list
        local clearBtn = UI.Button:new(1, btnY, 6, 2, "CLEAR", function()
            if ResourceTracker and fs.exists(ResourceTracker.DATA_FILE) then
                fs.delete(ResourceTracker.DATA_FILE)
                resourceTracker = ResourceTracker.new()
            end
            updateDisplay()
        end, colors.orange, colors.white)
        screen:addButton(clearBtn)
    end
    
    local quitBtn = UI.Button:new(w - 7, btnY, 7, 2, "QUIT", function()
        error("User quit")
    end, colors.red, colors.white)
    screen:addButton(quitBtn)
    
    screen:drawButtons()
end

-- Update display based on active tab
updateDisplay = function()
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
