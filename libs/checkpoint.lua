-- Checkpoint Management Library
-- Handles persistent state checkpointing for workers (turtles/computers)
-- Allows recovery from crashes by resuming from last checkpoint

local Checkpoint = {}

-- Default checkpoint file name (can be overridden)
Checkpoint.DEFAULT_FILE = "checkpoint.txt"

-- Initialize checkpoint system with custom filename
function Checkpoint.init(filename)
    Checkpoint.filename = filename or Checkpoint.DEFAULT_FILE
end

-- Save checkpoint to file
-- state: table containing checkpoint data
function Checkpoint.save(state)
    local filename = Checkpoint.filename or Checkpoint.DEFAULT_FILE
    
    -- Add timestamp
    state.timestamp = os.epoch("utc")
    
    local file = fs.open(filename, "w")
    file.write(textutils.serialize(state))
    file.close()
end

-- Load checkpoint from file
-- Returns: checkpoint table or nil if no checkpoint exists
function Checkpoint.load()
    local filename = Checkpoint.filename or Checkpoint.DEFAULT_FILE
    
    if not fs.exists(filename) then
        return nil
    end
    
    local file = fs.open(filename, "r")
    local data = file.readAll()
    file.close()
    
    return textutils.unserialize(data)
end

-- Clear checkpoint file (call when cycle completes successfully)
function Checkpoint.clear()
    local filename = Checkpoint.filename or Checkpoint.DEFAULT_FILE
    
    if fs.exists(filename) then
        fs.delete(filename)
    end
end

-- Check if checkpoint exists
function Checkpoint.exists()
    local filename = Checkpoint.filename or Checkpoint.DEFAULT_FILE
    return fs.exists(filename)
end

-- Get checkpoint age in seconds
function Checkpoint.getAge()
    local state = Checkpoint.load()
    if not state or not state.timestamp then
        return nil
    end
    
    local now = os.epoch("utc")
    return (now - state.timestamp) / 1000
end

return Checkpoint
