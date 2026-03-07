# Network Communication Refactoring

## Overview

Refactor the ComputerCraft automation system to improve reliability and consistency in network communication patterns. The codebase currently has inconsistent message handling, duplicate code, and patterns that don't follow the established networking best practices documented in networking.md.

## User Stories

### US-1: Consistent Message Handling
**As a** system maintainer  
**I want** all devices to use event-driven message handling consistently  
**So that** messages are never lost and the system is more reliable

**Acceptance Criteria:**
- 1.1: All devices read messages from event parameters, not from `Network.receive()` after `rednet_message` event
- 1.2: Blocking `Network.receive()` calls are only used in dedicated command listener functions with timeouts
- 1.3: The wither mob farm uses the same event-driven pattern as central computer and pocket remote
- 1.4: All message handlers verify protocol before processing

### US-2: Reusable Command Listeners
**As a** developer adding new workers  
**I want** a standardized command listener implementation  
**So that** I don't duplicate code and all workers behave consistently

**Acceptance Criteria:**
- 2.1: A new `libs/worker.lua` library provides `Worker.createCommandListener()` for all worker types
- 2.2: All turtle workers use `Worker.createCommandListener()` helper
- 2.3: Computer workers (wither mob farm) use `Worker.createCommandListener()` helper
- 2.4: No inline command listener implementations exist in worker files
- 2.5: Command listeners handle all standard commands: `report_status`, `set_mode`, `update`, `stop`
- 2.6: `TurtleLib.createCommandListener()` is removed from turtle.lua (moved to Worker library)

### US-3: Standardized Connection Initialization
**As a** worker device  
**I want** a consistent way to connect to central and get my initial mode  
**So that** startup behavior is predictable and reliable

**Acceptance Criteria:**
- 3.1: A new `libs/worker.lua` library provides `Worker.waitForCentralConnection()` for all worker types
- 3.2: All workers (turtles and computers) use `Worker.waitForCentralConnection()`
- 3.3: Connection logic includes timeout handling with sensible defaults (5 seconds)
- 3.4: Workers default to safe state (paused) if connection fails
- 3.5: Connection process logs progress clearly
- 3.6: `TurtleLib.waitForCentralConnection()` is removed from turtle.lua (moved to Worker library)

### US-4: Proactive Fuel Lock Management
**As a** turtle worker  
**I want** to ensure I have enough fuel before starting work  
**So that** I never get stuck mid-cycle and can always return home safely

**Acceptance Criteria:**
- 4.1: `TurtleLib` provides `ensureFuelForCycle()` that takes a minimum fuel requirement parameter
- 4.2: Turtles calculate their cycle fuel requirements (e.g., pig feeder needs fuel for 9x9 grid + descent/ascent)
- 4.3: If fuel is below the minimum, turtle enters fuel lock and waits for refueling
- 4.4: Fuel lock sends telemetry and alerts to central computer
- 4.5: Once fuel is sufficient, turtle automatically exits fuel lock and continues
- 4.6: No fuel checking is needed during work loops (only at cycle start)
- 4.7: `TurtleLib` provides `loadFuelFromChestWithCleanup()` that handles item cleanup before/after fueling
- 4.8: All three turtle workers use the new fuel lock pattern
- 4.9: Inline `refuel()` calls during loops are removed (no longer needed)

### US-5: Consistent Telemetry Patterns
**As a** central computer  
**I want** workers to send telemetry immediately on state changes  
**So that** the display shows accurate status within the 2-second refresh window

**Acceptance Criteria:**
- 5.1: Workers always send telemetry immediately after mode changes (running ↔ paused)
- 5.2: Workers always send telemetry immediately after phase changes (idle → descending → navigating → ascending → idle)
- 5.3: Workers send periodic telemetry on a timer (10-30 second intervals) as a heartbeat
- 5.4: Central computer never updates display in message handlers (keeps processing fast)
- 5.5: Central computer updates display on periodic timer (2 second interval)
- 5.6: Central computer processes `rednet_message` events immediately to update internal state
- 5.7: Maximum display lag is 2 seconds (the display refresh interval)

## Technical Context

### Current Issues

1. **Wither Mob Farm Message Handling**: Uses blocking `Network.receive()` in command listener instead of event-driven approach
2. **Duplicate Command Listeners**: Pig and cow feeders have inline implementations instead of using helper
3. **Inconsistent Connection Logic**: Each worker has slightly different connection initialization
4. **Duplicate Fuel Code**: Three turtles have nearly identical fuel management functions
5. **Delayed Telemetry Display**: Central computer waits for timer to update display instead of updating immediately when telemetry arrives
6. **Missing Phase Change Telemetry**: Workers don't always send telemetry when changing work phases

### Architecture

- **Hub-and-Spoke**: Central computer is hub, all workers are spokes
- **Protocol**: `BASECONTROL` using ComputerCraft's rednet API
- **Message Types**: `telemetry`, `command`, `alert`, `heartbeat`, `response`
- **DNS**: Central computer hosts as `"central"`, workers lookup via DNS

### Files Affected

- **New File**: `libs/worker.lua` - Shared worker utilities for all device types
- `computers/wither_mob_farm.lua` - Fix message handling, use Worker helpers
- `turtles/pig_feeder.lua` - Use Worker and TurtleLib helper functions
- `turtles/cow_feeder.lua` - Use Worker and TurtleLib helper functions
- `turtles/tree_farmer.lua` - Migrate to Worker helpers, use TurtleLib fuel functions
- `libs/turtle.lua` - Add fuel management helpers, deprecate worker-specific functions
- `libs/network.lua` - No changes needed (already provides core networking)

## Dependencies

- Must maintain backward compatibility with existing state files
- Must not break existing worker behavior during refactoring
- Should follow patterns documented in `.kiro/steering/networking.md`

## Success Metrics

- All workers use consistent message handling patterns
- Code duplication reduced by at least 50% in worker files
- No message loss during normal operations
- All workers can reconnect to central after network interruption
- Fuel management code consolidated into library functions

## Out of Scope

- Changing the network protocol or message structure
- Adding new features or commands
- Performance optimization beyond fixing blocking calls
- UI/display improvements
- Adding new worker types
