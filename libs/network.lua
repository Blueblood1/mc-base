-- Network Library for Turtle/Computer Communication
-- Handles modem communication, message protocols, and networking

local Network = {}

-- Protocol constants
Network.PROTOCOL = "BASECONTROL"
Network.MSG_TYPES = {
    TELEMETRY = "telemetry",
    COMMAND = "command",
    RESPONSE = "response",
    HEARTBEAT = "heartbeat",
    ALERT = "alert"
}

-- Initialize network (opens modem on specified side or searches for one)
function Network.init(side)
    if side then
        if peripheral.getType(side) == "modem" then
            rednet.open(side)
            return true
        end
    else
        -- Auto-detect modem
        for _, s in ipairs({"left", "right", "top", "bottom", "front", "back"}) do
            if peripheral.getType(s) == "modem" then
                rednet.open(s)
                return true
            end
        end
    end
    return false
end

-- Send a message to a specific computer
function Network.send(targetId, msgType, data)
    local message = {
        type = msgType,
        timestamp = os.epoch("utc"),
        data = data
    }
    rednet.send(targetId, message, Network.PROTOCOL)
end

-- Broadcast a message to all computers
function Network.broadcast(msgType, data)
    local message = {
        type = msgType,
        timestamp = os.epoch("utc"),
        data = data
    }
    rednet.broadcast(message, Network.PROTOCOL)
end

-- Receive a message (with optional timeout)
function Network.receive(timeout)
    local senderId, message, protocol = rednet.receive(Network.PROTOCOL, timeout)
    if senderId then
        return senderId, message.type, message.data, message.timestamp
    end
    return nil
end

-- Host a service with a hostname
function Network.host(hostname)
    rednet.host(Network.PROTOCOL, hostname)
end

-- Lookup a service by hostname
function Network.lookup(hostname)
    return rednet.lookup(Network.PROTOCOL, hostname)
end

-- Close network
function Network.close()
    rednet.close()
end

return Network
