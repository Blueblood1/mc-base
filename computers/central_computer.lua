-- Central Command Computer v2
-- Monitors and controls all turtles with touch screen support

local Network = require("network")
local Updater = require("updater")

-- Try to load optional libraries (may not exist on first run)
local UI = nil
local State = nil
local Version = nil

local success, module = pcall(require, "ui")
if success then UI = module end

success, module = pcall(require, "state")
if success then State = module end

success, module = pcall(require, "version")
if success then Version = module end

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

-- State
local screen = nil
local turtles = {}
local centralState = {}
local stats = {
    totalTurtles = 0,
    activeTurtles = 0,
    pausedTurtles = 0,
    alerts = {}
}

-- Send command to set turtle mode
local function setTurtleMode(turtleId, mode)
    State.setTurtleMode(centralState, turtleId, mode)
    Network.send(turtleId, Network.MSG_TYPES.COMMAND, {
        command = "set_mode",
        mode = mode
    })
    
    local turtleName = turtles[turtleId] and turtles[turtleId].name or ("Turtle " .. turtleId)
    table.insert(stats.alerts, os.date("%H:%M:%S") .. " - " .. turtleName .. " set to " .. mode)
end

-- Toggle turtle mode
local function toggleTurtleMode(turtleId)
    local newMode = State.toggleTurtleMode(centralState, turtleId)
    
    print("DEBUG: Sending set_mode=" .. newMode .. " to turtle " .. turtleId)
    
    Network.send(turtleId, Network.MSG_TYPES.COMMAND, {
        command = "set_mode",
        mode = newMode
    })
    
    local turtleName = turtles[turtleId] and turtles[turtleId].name or ("Turtle " .. turtleId)
    table.insert(stats.alerts, os.date("%H:%M:%S") .. " - " .. turtleName .. " " .. newMode)
end

-- Update display
local function updateDisplay()
    screen:clear()
    screen:clearButtons()
    
    -- Header
    screen:setTextColor(colors.yellow)
    screen:print("=== CENTRAL COMMAND SYSTEM ===")
    local buildInfo = Version and (" | Build: " .. Version.get()) or ""
    screen:print("Computer ID: " .. os.getComputerID() .. buildInfo)
    screen:print("Time: " .. os.date("%H:%M:%S"))
    screen:print("")
    
    -- Stats
    screen:setTextColor(colors.cyan)
    screen:print("Connected: " .. stats.totalTurtles .. " | Active: " .. stats.activeTurtles .. " | Paused: " .. stats.pausedTurtles)
    screen:print("")
    screen:setTextColor(colors.white)
    
    local currentY = 8
    local screenWidth, screenHeight = screen:getSize()
    
    -- Draw turtle list with control buttons
    for id, turtle in pairs(turtles) do
        if currentY >= screenHeight - 8 then
            break -- Don't overflow screen
        end
        
        local mode = State.getTurtleMode(centralState, id)
        local statusColor = colors.green
        
        if mode == "paused" then
            statusColor = colors.gray
        elseif turtle.status == "error" or turtle.status == "blocked" then
            statusColor = colors.red
        elseif turtle.status == "warning" then
            statusColor = colors.yellow
        end
        
        -- Turtle info
        screen:setCursorPos(1, currentY)
        screen:setTextColor(colors.lightGray)
        screen:write("[" .. id .. "] ")
        screen:setTextColor(colors.white)
        screen:write(turtle.name)
        
        -- Status indicator
        screen:setCursorPos(25, currentY)
        screen:setTextColor(statusColor)
        screen:write(mode == "paused" and "PAUSED" or turtle.status)
        
        -- Start/Stop button
        local buttonColor = mode == "paused" and colors.green or colors.red
        local buttonText = mode == "paused" and "START" or "STOP"
        local button = UI.Button:new(screenWidth - 8, currentY, 7, 1, buttonText, function()
            toggleTurtleMode(id)
            updateDisplay()
        end, buttonColor, colors.white)
        screen:addButton(button)
        
        currentY = currentY + 1
        
        -- Telemetry details
        if turtle.telemetry and mode ~= "paused" then
            screen:setTextColor(colors.gray)
            
            if turtle.telemetry.fuel then
                screen:setCursorPos(3, currentY)
                screen:write("Fuel: " .. turtle.telemetry.fuel.percent .. "%")
                if turtle.telemetry.fuel.percent < 20 then
                    screen:setTextColor(colors.red)
                    screen:write(" [LOW]")
                    screen:setTextColor(colors.gray)
                end
                currentY = currentY + 1
            end
            
            if turtle.telemetry.task and turtle.telemetry.task.phase then
                screen:setCursorPos(3, currentY)
                screen:write("Task: " .. turtle.telemetry.task.phase)
                currentY = currentY + 1
            end
            
            currentY = currentY + 1
        else
            currentY = currentY + 2
        end
    end
    
    -- Control buttons at bottom
    local buttonY = screenHeight - 3
    
    local updateBtn = UI.Button:new(2, buttonY, 10, 2, "UPDATE", function()
        sendUpdateCommand()
        updateDisplay()
    end, colors.blue, colors.white)
    screen:addButton(updateBtn)
    
    local refreshBtn = UI.Button:new(14, buttonY, 10, 2, "REFRESH", function()
        requestTelemetry()
        updateDisplay()
    end, colors.green, colors.white)
    screen:addButton(refreshBtn)
    
    local quitBtn = UI.Button:new(26, buttonY, 8, 2, "QUIT", function()
        error("User quit")
    end, colors.red, colors.white)
    screen:addButton(quitBtn)
    
    -- Draw all buttons
    screen:drawButtons()
    
    -- Alerts section
    if #stats.alerts > 0 then
        screen:setCursorPos(1, buttonY - 5)
        screen:setTextColor(colors.red)
        screen:print("=== RECENT ALERTS ===")
        screen:setTextColor(colors.white)
        for i = math.max(1, #stats.alerts - 2), #stats.alerts do
            screen:print(stats.alerts[i])
        end
    end
    
    screen:setTextColor(colors.white)
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
        
        -- Send current mode to new turtle
        local mode = State.getTurtleMode(centralState, turtleId)
        Network.send(turtleId, Network.MSG_TYPES.COMMAND, {
            command = "set_mode",
            mode = mode
        })
    end
    
    local turtle = turtles[turtleId]
    
    if data.name then
        turtle.name = data.name
    end
    
    turtle.telemetry = data
    turtle.lastUpdate = os.epoch("utc")
    turtle.status = data.status or "active"
    
    -- Check for issues
    if data.fuel and data.fuel.percent < 10 then
        turtle.status = "error"
        table.insert(stats.alerts, os.date("%H:%M:%S") .. " - " .. turtle.name .. ": Critical fuel!")
    elseif data.fuel and data.fuel.percent < 20 then
        turtle.status = "warning"
    end
    
    -- Update counts
    stats.activeTurtles = 0
    stats.pausedTurtles = 0
    for id, t in pairs(turtles) do
        local mode = State.getTurtleMode(centralState, id)
        if mode == "paused" then
            stats.pausedTurtles = stats.pausedTurtles + 1
        elseif t.status == "active" or t.status == "working" then
            stats.activeTurtles = stats.activeTurtles + 1
        end
    end
end

-- Handle incoming messages
local function handleMessage(senderId, msgType, data)
    if msgType == Network.MSG_TYPES.TELEMETRY then
        processTelemetry(senderId, data)
        updateDisplay()
    elseif msgType == Network.MSG_TYPES.COMMAND then
        -- Handle request_mode from turtles
        if data.command == "request_mode" then
            local mode = State.getTurtleMode(centralState, senderId)
            
            Network.send(senderId, Network.MSG_TYPES.COMMAND, {
                command = "set_mode",
                mode = mode
            })
            
            local turtleName = data.name or ("Turtle " .. senderId)
            table.insert(stats.alerts, os.date("%H:%M:%S") .. " - " .. turtleName .. " requested mode: " .. mode)
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
            
            -- Send initial mode to new turtle
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
        updateDisplay()
    end
end

-- Request telemetry
function requestTelemetry()
    Network.broadcast(Network.MSG_TYPES.COMMAND, {
        command = "report_status"
    })
end

-- Send update command
function sendUpdateCommand()
    table.insert(stats.alerts, os.date("%H:%M:%S") .. " - Broadcasting update command")
    Network.broadcast(Network.MSG_TYPES.COMMAND, {
        command = "update"
    })
end

-- Main
local function main()
    term.clear()
    term.setCursorPos(1, 1)
    
    -- Print version banner if available
    if Version then
        Version.printBanner("Central Command System v2")
    else
        print("=================================")
        print("Central Command System v2")
        print("=================================")
    end
    print("")
    
    -- Load state
    centralState = State.load()
    print("State loaded")
    
    -- Check for updates
    print("Checking for updates...")
    local results = Updater.updateLocal()
    local updated = false
    for filename, result in pairs(results) do
        if result.success then
            print("Updated: " .. filename)
            updated = true
        end
    end
    
    if updated then
        print("Updates applied, rebooting in 3 seconds...")
        print("Press any key to cancel")
        local timer = os.startTimer(3)
        local event, param = os.pullEvent()
        if event == "timer" and param == timer then
            os.reboot()
        end
    end
    
    sleep(1)
    
    -- Check for monitor
    local monitorSide = nil
    for _, side in ipairs({"top", "bottom", "left", "right", "front", "back"}) do
        if peripheral.getType(side) == "monitor" then
            monitorSide = side
            print("Monitor found on " .. side)
            break
        end
    end
    
    if monitorSide then
        local mon = peripheral.wrap(monitorSide)
        mon.setTextScale(0.5)
        screen = UI.Screen:new(mon)
    else
        print("No monitor found, using terminal")
        screen = UI.Screen:new()
    end
    
    -- Initialize network
    if not Network.init() then
        print("Error: No modem found!")
        return
    end
    
    Network.host(HOSTNAME)
    print("Network initialized")
    sleep(1)
    
    -- Initial telemetry request
    requestTelemetry()
    
    -- Initial display
    updateDisplay()
    
    -- Main loop
    local lastTelemetryRequest = os.epoch("utc")
    local lastDisplayUpdate = os.epoch("utc")
    
    -- Start a timer for periodic checks
    local checkTimer = os.startTimer(0.5)
    
    while true do
        -- Wait for any event
        local event, param1, param2, param3 = os.pullEvent()
        
        -- Handle timer for periodic tasks
        if event == "timer" and param1 == checkTimer then
            -- Check for network messages
            while true do
                local senderId, msgType, data = Network.receive(0)
                if not senderId then break end
                handleMessage(senderId, msgType, data)
            end
            
            local now = os.epoch("utc")
            
            -- Periodic telemetry
            if (now - lastTelemetryRequest) > (TELEMETRY_INTERVAL * 1000) then
                requestTelemetry()
                lastTelemetryRequest = now
            end
            
            -- Auto-refresh display
            if (now - lastDisplayUpdate) > (DISPLAY_REFRESH * 1000) then
                updateDisplay()
                lastDisplayUpdate = now
            end
            
            -- Restart timer
            checkTimer = os.startTimer(0.5)
            
        -- Handle rednet messages
        elseif event == "rednet_message" then
            -- Process the message that triggered this event
            local senderId, msgType, data = Network.receive(0)
            if senderId then
                handleMessage(senderId, msgType, data)
            end
            
        -- Handle monitor touch
        elseif event == "monitor_touch" then
            local x, y = param2, param3
            screen:handleClick(x, y)
            
        -- Handle terminal mouse click
        elseif event == "mouse_click" then
            local x, y = param2, param3
            screen:handleClick(x, y)
            
        -- Handle keyboard
        elseif event == "key" and param1 == keys.q then
            break
        end
    end
    
    print("Shutting down...")
    Network.close()
end

-- Run
main()
