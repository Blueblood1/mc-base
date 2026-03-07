-- Pocket Computer Remote Control
-- Remote interface for central command system

local Network = require("network")
local UI = require("ui")
local Version = require("version")
local Updater = require("updater")

-- Configuration
local CENTRAL_HOSTNAME = "central"
local TELEMETRY_INTERVAL = 5

-- State
local screen = nil
local tabBar = nil
local centralId = nil
local workers = {}
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
        
        -- Status indicator (compact)
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
        
        -- Toggle button (small)
        local btnColor = worker.mode == "paused" and colors.green or colors.red
        local btnText = worker.mode == "paused" and ">" or "||"
        local button = UI.Button:new(w - 2, currentY, 2, 1, btnText, function()
            toggleWorkerMode(id)
        end, btnColor, colors.white)
        screen:addButton(button)
        
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
    screen:clearButtons()
    screen:setCursorPos(1, 3)
    screen:setTextColor(colors.yellow)
    screen:print("Status Tab")
    screen:setTextColor(colors.white)
    screen:print("")
    screen:print("Coming soon...")
    
    local w, h = screen:getSize()
    local quitBtn = UI.Button:new(w - 7, h - 2, 7, 2, "QUIT", function()
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
    end
    
    screen:setTextColor(colors.white)
end

-- Process worker data from central
local function processWorkerData(data)
    -- This would come from central computer
    -- For now, we'll handle it when we get telemetry
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
    
    -- Create tab bar
    local w, h = screen:getSize()
    tabBar = UI.TabBar:new(1, 2, w, {"Control", "Status"})
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
            local event, param1, param2, param3 = os.pullEvent("rednet_message")
            local senderId, msgType, data = Network.receive(0)
            if senderId then
                handleMessage(senderId, msgType, data)
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
