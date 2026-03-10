-- Graph Library for Drawing Charts
-- Simple line graph rendering for monitors

local Graph = {}

-- Draw a line graph
function Graph.drawLineGraph(output, x, y, width, height, data, options)
    options = options or {}
    local color = options.color or colors.green
    local bgColor = options.bgColor or colors.black
    local axisColor = options.axisColor or colors.gray
    local showGrid = options.showGrid ~= false
    local title = options.title
    
    -- Clear graph area
    output.setBackgroundColor(bgColor)
    for dy = 0, height - 1 do
        output.setCursorPos(x, y + dy)
        output.write(string.rep(" ", width))
    end
    
    -- Draw title
    if title then
        output.setTextColor(colors.white)
        output.setCursorPos(x, y)
        output.write(title:sub(1, width))
    end
    
    -- Need at least 2 data points
    if #data < 2 then
        output.setTextColor(colors.gray)
        output.setCursorPos(x + math.floor(width / 2) - 7, y + math.floor(height / 2))
        output.write("No data")
        return
    end
    
    -- Find min/max values
    local minVal = data[1].count
    local maxVal = data[1].count
    for _, point in ipairs(data) do
        if point.count < minVal then minVal = point.count end
        if point.count > maxVal then maxVal = point.count end
    end
    
    -- Add some padding to range
    local range = maxVal - minVal
    if range == 0 then range = 1 end
    local padding = range * 0.1
    minVal = minVal - padding
    maxVal = maxVal + padding
    range = maxVal - minVal
    
    -- Draw grid
    if showGrid then
        output.setTextColor(axisColor)
        output.setBackgroundColor(bgColor)
        
        -- Horizontal lines
        for i = 0, 4 do
            local gridY = y + 2 + math.floor((height - 3) * i / 4)
            if gridY < y + height then
                output.setCursorPos(x, gridY)
                output.write(string.rep("-", width))
            end
        end
    end
    
    -- Draw data points
    output.setTextColor(color)
    output.setBackgroundColor(bgColor)
    
    local graphHeight = height - 3  -- Reserve space for title and labels
    local graphWidth = width - 1
    
    for i = 1, #data do
        local point = data[i]
        
        -- Calculate position
        local px = x + math.floor((i - 1) / (#data - 1) * graphWidth)
        local normalized = (point.count - minVal) / range
        local py = y + 2 + graphHeight - math.floor(normalized * graphHeight)
        
        -- Clamp to graph area
        if py < y + 2 then py = y + 2 end
        if py >= y + height then py = y + height - 1 end
        
        -- Draw point
        output.setCursorPos(px, py)
        output.write("*")
    end
    
    -- Draw min/max labels
    output.setTextColor(colors.white)
    output.setBackgroundColor(bgColor)
    
    -- Max value (top)
    local maxLabel = string.format("%.0f", maxVal)
    output.setCursorPos(x + width - #maxLabel, y + 2)
    output.write(maxLabel)
    
    -- Min value (bottom)
    local minLabel = string.format("%.0f", minVal)
    output.setCursorPos(x + width - #minLabel, y + height - 1)
    output.write(minLabel)
end

-- Draw a simple bar
function Graph.drawBar(output, x, y, width, value, maxValue, color, label)
    output.setBackgroundColor(colors.black)
    output.setTextColor(colors.white)
    
    -- Draw label
    if label then
        output.setCursorPos(x, y)
        output.write(label:sub(1, width))
    end
    
    -- Draw bar background
    output.setCursorPos(x, y + 1)
    output.setBackgroundColor(colors.gray)
    output.write(string.rep(" ", width))
    
    -- Draw filled portion
    local fillWidth = math.floor((value / maxValue) * width)
    if fillWidth > 0 then
        output.setCursorPos(x, y + 1)
        output.setBackgroundColor(color)
        output.write(string.rep(" ", math.min(fillWidth, width)))
    end
    
    -- Draw value text
    output.setBackgroundColor(colors.black)
    output.setTextColor(colors.white)
    output.setCursorPos(x, y + 2)
    output.write(string.format("%.1f / %.1f", value, maxValue))
end

return Graph
