-- UI Library for Touch Controls and Display
-- Provides reusable UI components for monitors and terminals

local UI = {}

-- Button class
UI.Button = {}
UI.Button.__index = UI.Button

function UI.Button:new(x, y, width, height, text, callback, color, textColor)
    local button = {
        x = x,
        y = y,
        width = width,
        height = height,
        text = text,
        callback = callback,
        color = color or colors.gray,
        textColor = textColor or colors.white,
        enabled = true
    }
    setmetatable(button, UI.Button)
    return button
end

function UI.Button:draw(output)
    if not self.enabled then
        output.setBackgroundColor(colors.black)
        output.setTextColor(colors.gray)
    else
        output.setBackgroundColor(self.color)
        output.setTextColor(self.textColor)
    end
    
    -- Draw button background
    for dy = 0, self.height - 1 do
        output.setCursorPos(self.x, self.y + dy)
        output.write(string.rep(" ", self.width))
    end
    
    -- Draw centered text
    local textY = self.y + math.floor(self.height / 2)
    local textX = self.x + math.floor((self.width - #self.text) / 2)
    output.setCursorPos(textX, textY)
    output.write(self.text)
    
    -- Reset colors
    output.setBackgroundColor(colors.black)
    output.setTextColor(colors.white)
end

function UI.Button:isClicked(clickX, clickY)
    return clickX >= self.x and clickX < self.x + self.width and
           clickY >= self.y and clickY < self.y + self.height
end

function UI.Button:click()
    if self.enabled and self.callback then
        self.callback()
    end
end

-- Screen wrapper to handle both monitor and terminal
UI.Screen = {}
UI.Screen.__index = UI.Screen

function UI.Screen:new(monitor)
    local screen = {
        output = monitor or term,
        isMonitor = monitor ~= nil,
        buttons = {}
    }
    setmetatable(screen, UI.Screen)
    return screen
end

function UI.Screen:clear()
    self.output.setBackgroundColor(colors.black)
    self.output.clear()
    self.output.setCursorPos(1, 1)
end

function UI.Screen:setTextColor(color)
    self.output.setTextColor(color)
end

function UI.Screen:setBackgroundColor(color)
    self.output.setBackgroundColor(color)
end

function UI.Screen:setCursorPos(x, y)
    self.output.setCursorPos(x, y)
end

function UI.Screen:write(text)
    self.output.write(text)
end

function UI.Screen:print(text)
    self.output.write(text)
    local x, y = self.output.getCursorPos()
    self.output.setCursorPos(1, y + 1)
end

function UI.Screen:getSize()
    return self.output.getSize()
end

function UI.Screen:addButton(button)
    table.insert(self.buttons, button)
end

function UI.Screen:drawButtons()
    for _, button in ipairs(self.buttons) do
        button:draw(self.output)
    end
end

function UI.Screen:handleClick(x, y)
    for _, button in ipairs(self.buttons) do
        if button:isClicked(x, y) then
            button:click()
            return true
        end
    end
    return false
end

function UI.Screen:clearButtons()
    self.buttons = {}
end

-- Helper function to draw a box
function UI.drawBox(output, x, y, width, height, color)
    output.setBackgroundColor(color or colors.gray)
    for dy = 0, height - 1 do
        output.setCursorPos(x, y + dy)
        output.write(string.rep(" ", width))
    end
    output.setBackgroundColor(colors.black)
end

-- Helper function to draw text centered in a box
function UI.drawCenteredText(output, x, y, width, text, textColor, bgColor)
    output.setBackgroundColor(bgColor or colors.black)
    output.setTextColor(textColor or colors.white)
    local textX = x + math.floor((width - #text) / 2)
    output.setCursorPos(textX, y)
    output.write(text)
    output.setBackgroundColor(colors.black)
    output.setTextColor(colors.white)
end

-- Tab Bar class
UI.TabBar = {}
UI.TabBar.__index = UI.TabBar

function UI.TabBar:new(x, y, width, tabs)
    local tabBar = {
        x = x,
        y = y,
        width = width,
        tabs = tabs or {},
        activeTab = 1,
        onTabChange = nil
    }
    setmetatable(tabBar, UI.TabBar)
    return tabBar
end

function UI.TabBar:addTab(name)
    table.insert(self.tabs, name)
end

function UI.TabBar:draw(output)
    local tabWidth = math.floor(self.width / #self.tabs)
    
    for i, tabName in ipairs(self.tabs) do
        local tabX = self.x + (i - 1) * tabWidth
        local isActive = (i == self.activeTab)
        
        -- Draw tab background
        output.setBackgroundColor(isActive and colors.gray or colors.black)
        output.setTextColor(isActive and colors.white or colors.lightGray)
        output.setCursorPos(tabX, self.y)
        
        -- Center text in tab
        local padding = math.floor((tabWidth - #tabName) / 2)
        local tabText = string.rep(" ", padding) .. tabName .. string.rep(" ", tabWidth - padding - #tabName)
        output.write(tabText)
    end
    
    -- Reset colors
    output.setBackgroundColor(colors.black)
    output.setTextColor(colors.white)
end

function UI.TabBar:handleClick(clickX, clickY)
    if clickY ~= self.y then
        return false
    end
    
    local tabWidth = math.floor(self.width / #self.tabs)
    
    for i = 1, #self.tabs do
        local tabX = self.x + (i - 1) * tabWidth
        if clickX >= tabX and clickX < tabX + tabWidth then
            if self.activeTab ~= i then
                self.activeTab = i
                if self.onTabChange then
                    self.onTabChange(i, self.tabs[i])
                end
            end
            return true
        end
    end
    
    return false
end

function UI.TabBar:getActiveTab()
    return self.activeTab, self.tabs[self.activeTab]
end

return UI
