-- Pocket Computer Touch Test
-- Simple script to test touch screen functionality

term.clear()
term.setCursorPos(1, 1)

print("=== POCKET COMPUTER TEST ===")
print("")
print("Screen size:")
local w, h = term.getSize()
print("Width: " .. w)
print("Height: " .. h)
print("")
print("Device type:")
if pocket then
    print("✓ Pocket Computer detected")
else
    print("✗ Not a pocket computer")
end
print("")
print("Touch test:")
print("Tap anywhere on screen")
print("Press 'q' to quit")
print("")

local touchCount = 0

while true do
    local event, param1, param2, param3 = os.pullEvent()
    
    if event == "mouse_click" then
        touchCount = touchCount + 1
        local button = param1
        local x = param2
        local y = param3
        
        term.setCursorPos(1, 15)
        term.clearLine()
        print("Touch #" .. touchCount)
        print("Button: " .. button)
        print("X: " .. x .. ", Y: " .. y)
        
    elseif event == "key" then
        if param1 == keys.q then
            break
        end
    end
end

term.clear()
term.setCursorPos(1, 1)
print("Test complete!")
print("Total touches: " .. touchCount)
