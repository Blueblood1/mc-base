-- Central Command Computer
-- Monitors and controls all turtles in the base

local Network = require("network")
local Updater = require("updater")

-- Configuration
local HOSTNAME = "central"
local TELEMETRY_INTERVAL = 30 -- Request telemetry every 30 seconds
local DISPLAY_REFRESH = 2 -- Refresh display every 2 seconds

-- Monitor setup
local monitor = nil
local useMonitor = false

-- Turtle registry
local turtles = {}

-- Status tracking
local stats = {
    totalTurtles = 0,
    activeTurtles = 0,
    alerts = {}
}

-- Initialize display
local function clearScreen()
    if useMonitor then
        monitor.clear()
        monitor.setCursorPos(1, 1)
    else
        term.clear()
        term.setCursorPos(1, 1)
    end
end

local function setTextColor(color)
    if useMonitor then
        monitor.setTextColor(color)
    else
        term.setTextColor(color)
    end
end

local function setCursorPos(x, y)
    if useMonitor then
        monitor.setCursorPos(x, y)
    else
        term.setCursorPos(x, y)
    end
end

local function write(text)
    if useMonitor then
        monitor.write(text)
    else
        term.write(text)
    end
end

local function print(text)
    if useMonitor then
        local x, y = monitor.getCursorPos()
        monitor.setCursorPos(1, y)
        monitor.write(text)
        monitor.setCursorPos(1, y + 1)
    else
        _G.print(text)
    end
end

-- Draw header
local function drawHeader()
    setTextColor(colors.yellow)
    print("=== CENTRAL COMMAND SYSTEM ===")
    print("Computer ID: " .. os.getComputerID())
    print("Time: " .. textutils.formatTime(os.time(), false))
    print("")
    setTextColor(colors.white)
end

-- Draw turtle status
local function drawTurtleStatus()
    setTextColor(colors.cyan)
    print("Connected Turtles: " .. stats.totalTurtles)
    print("Active: " .. stats.activeTurtles)
    print("")
    setTextColor(colors.white)
    
    for id, turtle in pairs(turtles) do
        local statusColor = colors.green
        if turtle.status == "error" or turtle.status == "blocked" then
            statusColor = colors.red
        elseif turtle.status == "warning" then
            statusColor = colors.yellow
        end
        
        setTextColor(colors.lightGray)
        write("[" .. id .. "] ")
        setTextColor(colors.white)
        write(turtle.name .. " - ")
        setTextColor(statusColor)
        print(turtle.status)
        
        if turtle.telemetry then
            setTextColor(colors.gray)
            local t = turtle.telemetry
            
            -- Fuel status
            if t.fuel then
                write("  Fuel: " .. t.fuel.percent .. "% ")
                if t.fuel.percent < 20 then
                    setTextColor(colors.red)
                    write("[LOW]")
                    setTextColor(colors.gray)
                end
                print("")
            end
            
            -- Task info
            if t.task then
                print("  Task: " .. (t.task.phase or "unknown"))
                if t.task.row and t.task.col then
                    print("  Position: Row " .. t.task.row .. ", Col " .. t.task.col)
                end
            end
            
            -- Last update
            if turtle.lastUpdate then
                local timeSince = math.floor((os.epoch("utc") - turtle.lastUpdate) / 1000)
                print("  Last update: " .. timeSince .. "s ago")
            end
            
            print("")
        end
    end
end

-- Draw alerts
local function drawAlerts()
    if #stats.alerts > 0 then
        setTextColor(colors.red)
        print("=== ALERTS ===")
        setTextColor(colors.white)
        for i = math.max(1, #stats.alerts - 5), #stats.alerts do
            print(stats.alerts[i])
        end
    end
end

-- Update display
local function updateDisplay()
    clearScreen()
    drawHeader()
    drawTurtleStatus()
    drawAlerts()
    
    setTextColor(colors.gray)
    print("")
    print("Commands: [U]pdate All | [Q]uit")
    setTextColor(colors.white)
end

-- Process telemetry from turtle
local function processTelemetry(turtleId, data)
    if not turtles[turtleId] then
        turtles[turtleId] = {
            name = data.name or ("Turtle " .. turtleId),
            status = "active",
            telemetry = {},
            lastUpdate = 0
        }
        stats.totalTurtles = stats.totalTurtles + 1
    end
    
    local turtle = turtles[turtleId]
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
    
    -- Update active count
    stats.activeTurtles = 0
    for _, t in pairs(turtles) do
        if t.status == "active" or t.status == "working" then
            stats.activeTurtles = stats.activeTurtles + 1
        end
    end
end

-- Handle incoming messages
local function handleMessage(senderId, msgType, data)
    if msgType == Network.MSG_TYPES.TELEMETRY then
        processTelemetry(senderId, data)
        updateDisplay()
    elseif msgType == Network.MSG_TYPES.HEARTBEAT then
        if turtles[senderId] then
            turtles[senderId].lastUpdate = os.epoch("utc")
        end
    elseif msgType == Network.MSG_TYPES.ALERT then
        local turtleName = turtles[senderId] and turtles[senderId].name or ("Turtle " .. senderId)
        table.insert(stats.alerts, os.date("%H:%M:%S") .. " - " .. turtleName .. ": " .. data.message)
        updateDisplay()
    end
end

-- Request telemetry from all turtles
local function requestTelemetry()
    Network.broadcast(Network.MSG_TYPES.COMMAND, {
        command = "report_status"
    })
end

-- Send update command to all turtles
local function sendUpdateCommand()
    table.insert(stats.alerts, os.date("%H:%M:%S") .. " - Broadcasting update command to all turtles")
    Network.broadcast(Network.MSG_TYPES.COMMAND, {
        command = "update"
    })
end

-- Send update command to specific turtle
local function sendUpdateToTurtle(turtleId)
    local turtleName = turtles[turtleId] and turtles[turtleId].name or ("Turtle " .. turtleId)
    table.insert(stats.alerts, os.date("%H:%M:%S") .. " - Sending update command to " .. turtleName)
    Network.send(turtleId, Network.MSG_TYPES.COMMAND, {
        command = "update"
    })
end

-- Main loop
local function main()
    term.clear()
    term.setCursorPos(1, 1)
    print("Initializing Central Command System...")
    
    -- Check for updates on startup
    print("Checking for updates...")
    local Updater = require("lib_updater")
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
        print("Press any key to cancel reboot")
        local timer = os.startTimer(3)
        local event, param = os.pullEvent()
        if event == "timer" and param == timer then
            os.reboot()
        else
            print("Reboot cancelled, continuing...")
        end
    else
        print("System up to date")
    end
    
    sleep(1)
    
    -- Check for monitor
    for _, side in ipairs({"top", "bottom", "left", "right", "front", "back"}) do
        if peripheral.getType(side) == "monitor" then
            monitor = peripheral.wrap(side)
            useMonitor = true
            monitor.setTextScale(0.5)
            print("Monitor found on " .. side)
            break
        end
    end
    
    if not useMonitor then
        print("No monitor found, using terminal")
    end
    
    -- Initialize network
    if not Network.init() then
        print("Error: No modem found!")
        return
    end
    
    -- Host service
    Network.host(HOSTNAME)
    print("Network initialized. Hosting as '" .. HOSTNAME .. "'")
    print("Computer ID: " .. os.getComputerID())
    print("")
    print("Waiting for turtles to connect...")
    sleep(2)
    
    -- Initial telemetry request
    requestTelemetry()
    
    -- Initial display
    updateDisplay()
    
    -- Main loop with auto-refresh
    local lastTelemetryRequest = os.epoch("utc")
    local lastDisplayUpdate = os.epoch("utc")
    
    while true do
        -- Check for messages (non-blocking with 0.5 second timeout)
        local senderId, msgType, data = Network.receive(0.5)
        if senderId then
            handleMessage(senderId, msgType, data)
        end
        
        local now = os.epoch("utc")
        
        -- Periodic telemetry request
        if (now - lastTelemetryRequest) > (TELEMETRY_INTERVAL * 1000) then
            requestTelemetry()
            lastTelemetryRequest = now
        end
        
        -- Auto-refresh display
        if (now - lastDisplayUpdate) > (DISPLAY_REFRESH * 1000) then
            updateDisplay()
            lastDisplayUpdate = now
        end
        
        -- Check for user input (non-blocking)
        local event, param = os.pullEvent()
        if event == "key" then
            if param == keys.q then
                break
            elseif param == keys.u then
                -- Update all turtles
                sendUpdateCommand()
                updateDisplay()
            elseif param == keys.r then
                -- Manual refresh
                requestTelemetry()
                updateDisplay()
            end
        elseif event == "char" then
            -- Handle number keys for individual turtle updates
            local num = tonumber(param)
            if num then
                -- Find turtle by index
                local index = 0
                for id, _ in pairs(turtles) do
                    index = index + 1
                    if index == num then
                        sendUpdateToTurtle(id)
                        updateDisplay()
                        break
                    end
                end
            end
        end
    end
    
    print("Shutting down...")
    Network.close()
end

-- Run
main()
