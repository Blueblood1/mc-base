# Version System

## Overview

The build number system automatically increments with each commit and is displayed on all programs.

## Files

- `VERSION` - Contains the current build number (single integer)
- `libs/version.lua` - Library for fetching and displaying version info
- `.git/hooks/pre-commit` - Git hook that auto-increments build on commit (bash)
- `.git/hooks/pre-commit.ps1` - PowerShell version of the hook

## How It Works

1. When you commit, the pre-commit hook runs
2. It reads the current build number from `VERSION`
3. Increments it by 1
4. Writes the new number back to `VERSION`
5. Adds `VERSION` to the commit

## Usage in Programs

### Central Computer
```lua
local Version = require("version")

-- Print banner on startup
Version.printBanner("Central Command System v2")

-- Show in UI
screen:print("Build: " .. Version.get())
```

### Turtles
```lua
-- Try to load version (optional, won't fail if missing)
local Version = nil
pcall(function()
    Version = require("version")
end)

-- Print banner if available
if Version then
    Version.printBanner("Tree Farmer")
end
```

## Git Hook Setup

### On Windows with Git Bash
The `.git/hooks/pre-commit` bash script should work automatically.

### On Windows with PowerShell
If the bash hook doesn't work, you can manually run:
```powershell
.\.git\hooks\pre-commit.ps1
```

Or configure Git to use PowerShell hooks:
```powershell
git config core.hooksPath .git/hooks
```

### Manual Version Increment
If hooks don't work, you can manually increment:
```bash
# Read current version
$version = Get-Content VERSION
# Increment
$newVersion = [int]$version + 1
# Save
$newVersion | Out-File VERSION -NoNewline
# Commit
git add VERSION
git commit -m "Increment build number"
```

## Version Display

All programs will show:
```
=================================
Program Name
Build: 42
=================================
```

This helps you verify:
- Which version is running
- If updates were successful
- Troubleshoot version mismatches

## Current Build

The current build number is: **1**

This will auto-increment on your next commit!
