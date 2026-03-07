# Network Communication Refactoring - Tasks

## Phase 1: Create Worker Library

- [x] 1. Create `libs/worker.lua` with shared worker utilities
  - [x] 1.1 Implement `Worker.waitForCentralConnection(state, workerName)`
  - [x] 1.2 Implement `Worker.createCommandListener(state, callbacks)`
  - [x] 1.3 Add proper error handling and logging
  - [x] 1.4 Add documentation comments

- [x] 2. Enhance `libs/turtle.lua` with fuel management
  - [x] 2.1 Implement `TurtleLib.ensureFuelForCycle(minimumFuel, fuelChestDirection, sendTelemetry, sendAlert)`
  - [x] 2.2 Implement `TurtleLib.loadFuelFromChestWithCleanup(fuelDirection, cleanupDirections, targetPercent)`
  - [x] 2.3 Remove `TurtleLib.createCommandListener()` (moved to Worker library)
  - [x] 2.4 Remove `TurtleLib.waitForCentralConnection()` (moved to Worker library)
  - [x] 2.5 Add documentation comments

## Phase 2: Update Wither Mob Farm

- [x] 3. Refactor `computers/wither_mob_farm.lua` message handling
  - [x] 3.1 Replace custom `createCommandListener()` with `Worker.createCommandListener()`
  - [x] 3.2 Replace custom `waitForCentralConnection()` with `Worker.waitForCentralConnection()`
  - [x] 3.3 Remove blocking `Network.receive()` call from command listener

## Phase 3: Update Pig Feeder

- [x] 4. Refactor `turtles/pig_feeder.lua` to use new patterns
  - [x] 4.1 Replace `TurtleLib.createCommandListener()` with `Worker.createCommandListener()`
  - [x] 4.2 Replace `TurtleLib.waitForCentralConnection()` with `Worker.waitForCentralConnection()`
  - [x] 4.3 Calculate cycle fuel requirement (CYCLE_FUEL_REQUIREMENT = 115)
  - [x] 4.4 Add `TurtleLib.ensureFuelForCycle()` call at start of mainLoop
  - [x] 4.5 Remove inline `refuel()` calls from navigateGrid and returnHome
  - [x] 4.6 Remove `checkFuelLock()` function (replaced by ensureFuelForCycle)
  - [x] 4.7 Update `loadFuel()` to use `TurtleLib.loadFuelFromChestWithCleanup()`
  - [x] 4.8 Add `sendTelemetry()` call in returnHome after clearing state

## Phase 4: Update Cow Feeder

- [x] 5. Refactor `turtles/cow_feeder.lua` to use new patterns
  - [x] 5.1 Replace `TurtleLib.createCommandListener()` with `Worker.createCommandListener()`
  - [x] 5.2 Replace `TurtleLib.waitForCentralConnection()` with `Worker.waitForCentralConnection()`
  - [x] 5.3 Calculate cycle fuel requirement (CYCLE_FUEL_REQUIREMENT = 125)
  - [x] 5.4 Add `TurtleLib.ensureFuelForCycle()` call at start of mainLoop
  - [x] 5.5 Remove inline `refuel()` calls from navigateGrid and returnHome
  - [x] 5.6 Remove `checkFuelLock()` function (replaced by ensureFuelForCycle)
  - [x] 5.7 Update `loadFuel()` to use `TurtleLib.loadFuelFromChestWithCleanup()`
  - [x] 5.8 Add `sendTelemetry()` call in returnHome after clearing state

## Phase 5: Update Tree Farmer

- [x] 6. Refactor `turtles/tree_farmer.lua` to use new patterns
  - [x] 6.1 Replace `TurtleLib.createCommandListener()` with `Worker.createCommandListener()`
  - [x] 6.2 Replace `TurtleLib.waitForCentralConnection()` with `Worker.waitForCentralConnection()`
  - [x] 6.3 Calculate cycle fuel requirement (CYCLE_FUEL_REQUIREMENT = 150)
  - [x] 6.4 Add `TurtleLib.ensureFuelForCycle()` call at start of mainLoop
  - [x] 6.5 Remove inline `refuel()` calls from work functions
  - [x] 6.6 Remove `checkFuelLock()` function (replaced by ensureFuelForCycle)
  - [x] 6.7 Update `loadFuel()` to use `TurtleLib.loadFuelFromChestWithCleanup()`
  - [x] 6.8 Add `sendTelemetry()` call in harvestTree after clearing state
  - [x] 6.9 Fix resume logic to handle all phases (planting, growing, harvesting, depositing)
  - [x] 6.10 Replace custom log() function with Version.log() for consistent timestamps
  - [x] 6.11 Fix Worker.createCommandListener to use event-driven message handling

## Phase 6: Documentation & Cleanup

- [x] 7. Update documentation
  - [x] 7.1 Update README.md with new fuel lock pattern
  - [x] 7.2 Update `.kiro/steering/networking.md` with Worker library examples
  - [x] 7.3 Document fuel requirements for each turtle type
  - [x] 7.4 Create `.kiro/steering/adding-workers.md` comprehensive guide

- [x] 8. Code cleanup
  - [x] 8.1 Remove commented-out old code (none found)
  - [x] 8.2 Verify consistent code style
  - [x] 8.3 Verify all error messages are clear and helpful
  - [x] 8.4 Verify all log messages are consistent

## Summary

✅ All tasks complete! 

All workers now use:
- Worker library for connection and command handling
- Event-driven message handling (no blocking receives)
- Proactive fuel management (check before cycle, not during)
- Consistent telemetry patterns (send on phase changes)
- Proper resume logic for interrupted cycles

Documentation updated:
- README.md includes fuel requirements and new patterns
- networking.md includes Worker library examples
- New adding-workers.md provides comprehensive guide for creating new workers
