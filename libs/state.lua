-- State Management Library
-- Handles persistent state storage for central computer

local State = {}

State.STATE_FILE = "central_state.txt"

-- Load state from file
function State.load()
    if fs.exists(State.STATE_FILE) then
        local file = fs.open(State.STATE_FILE, "r")
        local data = file.readAll()
        file.close()
        return textutils.unserialize(data) or {}
    end
    return {}
end

-- Save state to file
function State.save(state)
    local file = fs.open(State.STATE_FILE, "w")
    file.write(textutils.serialize(state))
    file.close()
end

-- Get turtle mode (running or paused)
function State.getTurtleMode(state, turtleId)
    if not state.turtleModes then
        state.turtleModes = {}
    end
    return state.turtleModes[turtleId] or "running"
end

-- Set turtle mode
function State.setTurtleMode(state, turtleId, mode)
    if not state.turtleModes then
        state.turtleModes = {}
    end
    state.turtleModes[turtleId] = mode
    State.save(state)
end

-- Toggle turtle mode
function State.toggleTurtleMode(state, turtleId)
    local currentMode = State.getTurtleMode(state, turtleId)
    local newMode = currentMode == "running" and "paused" or "running"
    State.setTurtleMode(state, turtleId, newMode)
    return newMode
end

return State
