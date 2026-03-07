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

- [ ] 5. Refactor `turtles/cow_feeder.lua` to use new patterns
  - [ ] 5.1 Replace `TurtleLib.createCommandListener()` with `Worker.createCommandListener()`
  - [ ] 5.2 Replace `TurtleLib.waitForCentralConnection()` with `Worker.waitForCentralConnection()`
  - [ ] 5.3 Calculate cycle fuel requirement (CYCLE_FUEL_REQUIREMENT = 125)
  - [ ] 5.4 Add `TurtleLib.ensureFuelForCycle()` call at start of mainLoop
  - [ ] 5.5 Remove inline `refuel()` calls from navigateGrid and returnHome
  - [ ] 5.6 Remove `checkFuelLock()` function (replaced by ensureFuelForCycle)
  - [ ] 5.7 Update `loadFuel()` to use `TurtleLib.loadFuelFromChestWithCleanup()`
  - [ ] 5.8 Add `sendTelemetry()` call in returnHome after clearing state

## Phase 5: Update Tree Farmer

- [ ] 6. Refactor `turtles/tree_farmer.lua` to use new patterns
  - [ ] 6.1 Replace `TurtleLib.createCommandListener()` with `Worker.createCommandListener()`
  - [ ] 6.2 Replace `TurtleLib.waitForCentralConnection()` with `Worker.waitForCentralConnection()`
  - [ ] 6.3 Calculate cycle fuel requirement (CYCLE_FUEL_REQUIREMENT = 75)
  - [ ] 6.4 Add `TurtleLib.ensureFuelForCycle()` call at start of mainLoop
  - [ ] 6.5 Remove inline `refuel()` calls from work functions
  - [ ] 6.6 Remove `checkFuelLock()` function (replaced by ensureFuelForCycle)
  - [ ] 6.7 Update `loadFuel()` to use `TurtleLib.loadFuelFromChestWithCleanup()`
  - [ ] 6.8 Add `sendTelemetry()` call after depositItems completes

## Phase 6: Documentation & Cleanup

- [ ] 7. Update documentation
  - [ ] 7.1 Update README.md with new fuel lock pattern
  - [ ] 7.2 Update `.kiro/steering/networking.md` with Worker library examples
  - [ ] 7.3 Document fuel requirements for each turtle type
  - [ ] 7.4 Update README.md "Adding New Turtles" section to reference Worker library

- [ ] 8. Code cleanup
  - [ ] 8.1 Remove commented-out old code
  - [ ] 8.2 Verify consistent code style
  - [ ] 8.3 Verify all error messages are clear and helpful
  - [ ] 8.4 Verify all log messages are consistent
