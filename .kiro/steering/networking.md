---
inclusion: always
---

# Networking Architecture and Best Practices

## Overview

Our automation system uses ComputerCraft's rednet API for communication between devices. The architecture follows a hub-and-spoke model with the central computer as the hub and all workers (turtles, computers, pocket computers) as spokes.

## Network Protocol

- **Protocol Name**: `BASECONTROL`
- **Library**: `libs/network.lua`
- **DNS**: Uses rednet's built-in DNS for service discovery

## Message Types

```lua
Network.MSG_TYPES = {
    TELEMETRY = "telemetry",  -- Status updates from workers
    COMMAND = "command",       -- Commands to/from central
    RESPONSE = "response",     -- Responses to commands
    HEARTBEAT = "heartbeat",   -- Keep-alive messages
    ALERT = "alert"           -- Error/warning notifications
}
```

## Architecture

### Central Computer (Hub)
- Hosts DNS name: `"central"`
- Receives telemetry from all workers
- Sends commands to workers
- Maintains state for all workers
- Single source of truth for worker modes

### Workers (Spokes)
- Turtles (pig_feeder, cow_feeder, tree_farmer)
- Computers (wither_mob_farm)
- Pocket computers (remote control)
- All workers lookup central via DNS
- Send telemetry periodically
- Receive commands from central

## Critical Networking Lessons Learned

### 1. Event-Driven Message Handling

**WRONG WAY** (causes message loss):
```lua
elseif event == "rednet_message" then
    local senderId, msgType, data = Network.receive(0)  -- FAILS!
    if senderId then
        handleMessage(senderId, msgType, data)
    end
end
```

**RIGHT WAY** (read from event parameters):
```lua
elseif event == "rednet_message" then
    -- param1 = sender ID
    -- param2 = message table
    -- param3 = protocol string
    
    if param3 == Network.PROTOCOL then
        if type(param2) == "table" then
            handleMessage(param1, param2.type, param2.data)
        end
    end
end
```

**Why**: When a `rednet_message` event fires, the message has already been consumed by the rednet API. Calling `rednet.receive(protocol, 0)` tries to receive a NEW message with a 0 timeout, which returns nil because there's no new message in the queue. The message data is in the event parameters.

### 2. Parallel Event Loops

For devices that need to handle both network messages and other events (UI, timers, etc.), use `parallel.waitForAll`:

```lua
local function messageListener()
    while true do
        local event, param1, param2, param3 = os.pullEvent()
        if event == "rednet_message" then
            -- Handle message from event params
        end
    end
end

local function uiLoop()
    while true do
        local event, param1, param2, param3 = os.pullEvent()
        if event == "timer" then
            -- Handle timer
        elseif event == "mouse_click" then
            -- Handle UI
        end
    end
end

parallel.waitForAll(messageListener, uiLoop)
```

**Important**: Both functions must call `os.pullEvent()` without filtering to avoid event starvation.

### 3. DNS Lookup Timing

When looking up the central computer:
```lua
local centralId = Network.lookup("central")
```

This may return immediately or take a moment. The lookup uses the DNS protocol, which can generate additional rednet messages. These DNS messages should not interfere with your application messages because they use a different protocol.

### 4. Message Structure

All messages sent via `Network.send()` are wrapped in a table:
```lua
{
    type = msgType,           -- e.g., "command", "telemetry"
    timestamp = os.epoch("utc"),
    data = data               -- Your actual data
}
```

When receiving from event parameters, access like:
- `param2.type` - message type
- `param2.data` - your data
- `param2.timestamp` - when sent

### 5. Blocking Operations

**NEVER** call slow operations in message handlers:
```lua
-- BAD: Blocks message processing
local function handleMessage(senderId, msgType, data)
    processTelemetry(senderId, data)
    updateDisplay()  -- SLOW! Blocks other messages
end

-- GOOD: Let periodic refresh handle display
local function handleMessage(senderId, msgType, data)
    processTelemetry(senderId, data)
    -- Display updates on timer, not here
end
```

Drawing to monitors can be slow. Handle messages quickly and update displays on a periodic timer (every 2 seconds is fine).

### 6. Worker Communication Pattern

Workers should:
1. Initialize network with `Network.init()`
2. Use `Worker.waitForCentralConnection(state, workerName)` to connect
3. Create command listener with `Worker.createCommandListener(state, callbacks)`
4. Run command listener in parallel with main loop
5. Send periodic telemetry (every 10-30 seconds)

**Example using Worker library:**
```lua
local Worker = require("worker")
local Network = require("network")
local Version = require("version")

local sharedState = {
    centralId = nil,
    centralConnected = false,
    operatingMode = "running",
    stopRequested = false
}

local function main()
    -- Initialize network
    Network.init()
    
    -- Wait for connection to central
    Worker.waitForCentralConnection(sharedState, "My Worker")
    
    -- Send initial telemetry
    sendTelemetry()
    
    -- Create command listener (uses event-driven message handling)
    local commandListener = Worker.createCommandListener(sharedState, {
        sendAlert = sendAlert,
        sendTelemetry = sendTelemetry,
        onModeChange = onModeChange  -- Optional callback
    })
    
    -- Run in parallel
    parallel.waitForAll(mainLoop, commandListener)
end
```

The Worker library handles:
- DNS lookup and connection retry logic
- Event-driven message handling (no blocking receives)
- Command processing (set_mode, report_status, update, stop)
- Mode change notifications

### 7. Central Computer Pattern

Central computer should:
1. Initialize network with `Network.init()`
2. Host DNS name: `Network.host("central")`
3. Handle messages in event loop (read from event params)
4. Respond immediately to commands
5. Update display on periodic timer, not in message handler
6. Maintain state for all workers

## Common Pitfalls

1. **Using `Network.receive(0)` after `rednet_message` event** - Always fails
2. **Filtering events with `os.pullEvent("rednet_message")`** - Causes event starvation in parallel loops
3. **Blocking operations in message handlers** - Delays responses
4. **Not handling timeouts** - Workers should default to safe state
5. **Forgetting protocol check** - Always verify `param3 == Network.PROTOCOL`

## Testing Network Communication

To verify messages are being sent/received:
1. Check computer IDs match (sender/receiver)
2. Verify protocol is "BASECONTROL"
3. Check message structure (must be table with type/data)
4. Use temporary logging to trace message flow
5. Test with simple ping/pong before complex logic

## Performance Considerations

- Telemetry interval: 10-30 seconds (don't spam)
- Display refresh: 2 seconds (fast enough, not too fast)
- Command timeout: 5 seconds (reasonable for response)
- DNS lookup: May take 1-2 seconds on first call

## Example: Complete Message Handler

```lua
-- In main event loop
elseif event == "rednet_message" then
    -- Read from event parameters
    local senderId = param1
    local message = param2
    local protocol = param3
    
    -- Verify protocol
    if protocol == Network.PROTOCOL then
        -- Verify message structure
        if type(message) == "table" and message.type and message.data then
            -- Handle quickly, no blocking operations
            handleMessage(senderId, message.type, message.data)
        end
    end
end
```

## Summary

The key to reliable networking in ComputerCraft:
1. Read messages from event parameters, not `receive()`
2. Handle messages quickly without blocking
3. Use parallel loops for multi-tasking
4. Always verify protocol before processing
5. Default to safe states on timeouts
