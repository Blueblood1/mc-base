-- Auto-start central computer on boot
-- This file should be renamed to startup.lua on the central computer

print("Auto-starting Central Command System...")
print("Checking for updates...")

-- Update before running
local Updater = require("lib_updater")
Updater.updateLocal()

print("Starting central computer...")
shell.run("central_computer")
