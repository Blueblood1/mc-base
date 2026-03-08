-- Step Executor Library
-- Generic step-based execution system with automatic checkpointing and recovery

local Executor = {}

local Checkpoint = require("checkpoint")
local Network = require("network")

-- Action handlers
local actionHandlers = {}

-- Register an action handler
function Executor.registerAction(actionType, handler)
    actionHandlers[actionType] = handler
end

-- Execute a single step
-- Returns: success (boolean), error message (string or nil)
local function executeStep(step, context)
    local handler = actionHandlers[step.action]
    
    if not handler then
        return false, "Unknown action: " .. tostring(step.action)
    end
    
    -- Call handler with step data and context
    local success, err = handler(step, context)
    
    return success, err
end

-- Execute a sequence of steps with automatic checkpointing
-- steps: array of step definitions
-- context: shared context object (state, IDs, etc.)
-- checkpointFile: filename for checkpoint storage
-- checkpointSteps: array of step numbers to checkpoint at (optional, defaults to all)
function Executor.run(steps, context, checkpointFile, checkpointSteps)
    -- Initialize checkpoint system
    Checkpoint.init(checkpointFile or "executor_checkpoint.txt")
    
    -- Initialize orientation tracking (0 = forward, 1 = right, 2 = back, 3 = left)
    context.facing = 0
    
    -- Load checkpoint or start from beginning
    local startStep = 1
    local checkpoint = Checkpoint.load()
    
    if checkpoint and checkpoint.step then
        startStep = checkpoint.step
        context.facing = checkpoint.facing or 0
        
        print("Resuming from step " .. startStep .. " of " .. #steps)
        print("Facing: " .. context.facing .. " (0=forward, 1=right, 2=back, 3=left)")
        
        -- Check if this was a movement action that might not have completed
        if checkpoint.fuelBefore then
            local currentFuel = turtle.getFuelLevel()
            if currentFuel == checkpoint.fuelBefore then
                -- Fuel unchanged - movement didn't happen, will retry
                print("Movement didn't complete, retrying step " .. startStep)
            else
                -- Fuel changed - movement succeeded, skip to next step
                print("Movement completed, continuing from step " .. (startStep + 1))
                startStep = startStep + 1
            end
        end
    else
        print("Starting from beginning (" .. #steps .. " steps)")
    end
    
    -- Execute steps
    for i = startStep, #steps do
        local step = steps[i]
        
        -- Determine if this is a movement action that needs fuel tracking
        local isMovement = (step.action == "move")
        local fuelBefore = nil
        
        if isMovement then
            fuelBefore = turtle.getFuelLevel()
        end
        
        -- Save checkpoint BEFORE executing step
        -- Only save at designated checkpoint steps (or all if not specified)
        if not checkpointSteps or checkpointSteps[i] then
            Checkpoint.save({
                step = i,
                facing = context.facing,
                fuelBefore = fuelBefore  -- nil for non-movement actions
            })
        end
        
        -- Log step
        if step.log then
            print(step.log)
        end
        
        -- Execute step with retry logic
        local maxRetries = step.retries or 3
        local success = false
        local err = nil
        
        for attempt = 1, maxRetries do
            success, err = executeStep(step, context)
            
            if success then
                break
            else
                print("Step " .. i .. " failed (attempt " .. attempt .. "/" .. maxRetries .. "): " .. tostring(err))
                if attempt < maxRetries then
                    sleep(1)  -- Wait before retry
                end
            end
        end
        
        -- Check if step failed after all retries
        if not success then
            print("ERROR: Step " .. i .. " failed after " .. maxRetries .. " attempts")
            print("Error: " .. tostring(err))
            
            -- Save checkpoint at failed step for manual recovery
            Checkpoint.save({
                step = i,
                error = err,
                facing = context.facing,
                fuelBefore = fuelBefore
            })
            
            return false, "Step " .. i .. " failed: " .. tostring(err)
        end
    end
    
    -- All steps completed successfully
    print("All steps completed successfully!")
    Checkpoint.clear()
    
    return true
end

-- Built-in action handlers

-- Move action
actionHandlers["move"] = function(step, context)
    local direction = step.direction or "forward"
    local count = step.count or 1
    
    for i = 1, count do
        local success = false
        
        if direction == "forward" then
            success = turtle.forward()
        elseif direction == "back" then
            success = turtle.back()
        elseif direction == "up" then
            success = turtle.up()
        elseif direction == "down" then
            success = turtle.down()
        else
            return false, "Invalid direction: " .. direction
        end
        
        if not success then
            return false, "Failed to move " .. direction .. " (step " .. i .. "/" .. count .. ")"
        end
    end
    
    return true
end

-- Turn action
actionHandlers["turn"] = function(step, context)
    local direction = step.direction or "right"
    local count = step.count or 1
    
    for i = 1, count do
        if direction == "right" then
            turtle.turnRight()
            -- Update facing: 0=forward, 1=right, 2=back, 3=left
            context.facing = (context.facing + 1) % 4
        elseif direction == "left" then
            turtle.turnLeft()
            context.facing = (context.facing - 1) % 4
            if context.facing < 0 then context.facing = context.facing + 4 end
        else
            return false, "Invalid turn direction: " .. direction
        end
    end
    
    return true
end

-- Place action
actionHandlers["place"] = function(step, context)
    local slot = step.slot
    local side = step.side or "front"
    
    if not slot then
        return false, "No slot specified for place action"
    end
    
    turtle.select(slot)
    
    local success = false
    if side == "front" then
        success = turtle.place()
    elseif side == "up" then
        success = turtle.placeUp()
    elseif side == "down" then
        success = turtle.placeDown()
    else
        return false, "Invalid side: " .. side
    end
    
    if not success then
        return false, "Failed to place block from slot " .. slot
    end
    
    return true
end

-- Dig action
actionHandlers["dig"] = function(step, context)
    local side = step.side or "front"
    
    local success = false
    if side == "front" then
        success = turtle.dig()
    elseif side == "up" then
        success = turtle.digUp()
    elseif side == "down" then
        success = turtle.digDown()
    else
        return false, "Invalid side: " .. side
    end
    
    -- Digging air is not a failure
    return true
end

-- Network send action (for door commands, etc.)
actionHandlers["network_send"] = function(step, context)
    local targetId = step.targetId or context.farmComputerId
    local msgType = step.msgType or Network.MSG_TYPES.COMMAND
    local data = step.data
    
    if not targetId then
        return false, "No target ID specified"
    end
    
    if not data then
        return false, "No data specified"
    end
    
    Network.send(targetId, msgType, data)
    
    return true
end

-- Wait/sleep action
actionHandlers["wait"] = function(step, context)
    local duration = step.duration or 1
    sleep(duration)
    return true
end

-- Select slot action
actionHandlers["select"] = function(step, context)
    local slot = step.slot
    
    if not slot then
        return false, "No slot specified"
    end
    
    turtle.select(slot)
    return true
end

-- Suck items action
actionHandlers["suck"] = function(step, context)
    local side = step.side or "front"
    local amount = step.amount or 64
    
    local success = false
    if side == "front" then
        success = turtle.suck(amount)
    elseif side == "up" then
        success = turtle.suckUp(amount)
    elseif side == "down" then
        success = turtle.suckDown(amount)
    else
        return false, "Invalid side: " .. side
    end
    
    if not success then
        return false, "Failed to suck items from " .. side
    end
    
    return true
end

-- Custom function action (for complex logic)
actionHandlers["function"] = function(step, context)
    if not step.func then
        return false, "No function specified"
    end
    
    return step.func(context)
end

return Executor
