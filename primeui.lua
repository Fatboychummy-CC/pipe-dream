-- PrimeUI by JackMacWindows
-- Public domain/CC0

local expect = require "cc.expect".expect

-- Initialization code
local PrimeUI = {}
do
    local coros = {}
    local restoreCursor

    --- Adds a task to run in the main loop.
    ---@param func function The function to run, usually an `os.pullEvent` loop
    function PrimeUI.addTask(func)
        expect(1, func, "function")
        local t = {coro = coroutine.create(func)}
        coros[#coros+1] = t
        _, t.filter = coroutine.resume(t.coro)
    end

    --- Sends the provided arguments to the run loop, where they will be returned.
    ---@param ... any The parameters to send
    function PrimeUI.resolve(...)
        coroutine.yield(coros, ...)
    end

    --- Clears the screen and resets all components. Do not use any previously
    --- created components after calling this function.
    function PrimeUI.clear()
        -- Reset the screen.
        term.setCursorPos(1, 1)
        term.setCursorBlink(false)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.clear()
        -- Reset the task list and cursor restore function.
        coros = {}
        restoreCursor = nil
    end

    --- Sets or clears the window that holds where the cursor should be.
    ---@param win Window|nil The window to set as the active window
    function PrimeUI.setCursorWindow(win)
        expect(1, win, "table", "nil")
        restoreCursor = win and win.restoreCursor
    end

    --- Gets the absolute position of a coordinate relative to a window.
    ---@param win Window The window to check
    ---@param x number The relative X position of the point
    ---@param y number The relative Y position of the point
    ---@return number x The absolute X position of the window
    ---@return number y The absolute Y position of the window
    function PrimeUI.getWindowPos(win, x, y)
        if win == term then return x, y end
        while win ~= term.native() and win ~= term.current() do
            if not win.getPosition then return x, y end
            local wx, wy = win.getPosition()
            x, y = x + wx - 1, y + wy - 1
            _, win = debug.getupvalue(select(2, debug.getupvalue(win.isColor, 1)), 1) -- gets the parent window through an upvalue
        end
        return x, y
    end

    --- Runs the main loop, returning information on an action.
    ---@return any ... The result of the coroutine that exited
    function PrimeUI.run()
        while true do
            -- Restore the cursor and wait for the next event.
            if restoreCursor then restoreCursor() end
            local ev = table.pack(os.pullEvent())
            -- Run all coroutines.
            for _, v in ipairs(coros) do
                if v.filter == nil or v.filter == ev[1] then
                    -- Resume the coroutine, passing the current event.
                    local res = table.pack(coroutine.resume(v.coro, table.unpack(ev, 1, ev.n)))
                    -- If the call failed, bail out. Coroutines should never exit.
                    if not res[1] then error(res[2], 2) end
                    -- If the coroutine resolved, return its values.
                    if res[2] == coros then return table.unpack(res, 3, res.n) end
                    -- Set the next event filter.
                    v.filter = res[2]
                end
            end
        end
    end
end

--- Creates a list of entries that can each be selected.
---@param win Window The window to draw on
---@param x number The X coordinate of the inside of the box
---@param y number The Y coordinate of the inside of the box
---@param width number The width of the inner box
---@param height number The height of the inner box
---@param entries string[] A list of entries to show, where the value is whether the item is pre-selected (or `"R"` for required/forced selected)
---@param action function|string A function or `run` event that's called when a selection is made
---@param selectChangeAction function|string|nil A function or `run` event that's called when the current selection is changed
---@param fgColor color|nil The color of the text (defaults to white)
---@param bgColor color|nil The color of the background (defaults to black)
function PrimeUI.selectionBox(win, x, y, width, height, entries, action, selectChangeAction, fgColor, bgColor)
    expect(1, win, "table")
    expect(2, x, "number")
    expect(3, y, "number")
    expect(4, width, "number")
    expect(5, height, "number")
    expect(6, entries, "table")
    expect(7, action, "function", "string")
    expect(8, selectChangeAction, "function", "string", "nil")
    fgColor = expect(9, fgColor, "number", "nil") or colors.white
    bgColor = expect(10, bgColor, "number", "nil") or colors.black
    -- Check that all entries are strings.
    if #entries == 0 then error("bad argument #6 (table must not be empty)", 2) end
    for i, v in ipairs(entries) do
        if type(v) ~= "string" then error("bad item " .. i .. " in entries table (expected string, got " .. type(v), 2) end
    end
    -- Create container window.
    local entrywin = window.create(win, x, y, width - 1, height)
    local selection, scroll = 1, 1
    -- Create a function to redraw the entries on screen.
    local function drawEntries()
        -- Clear and set invisible for performance.
        entrywin.setVisible(false)
        entrywin.setBackgroundColor(bgColor)
        entrywin.clear()
        -- Draw each entry in the scrolled region.
        for i = scroll, scroll + height - 1 do
            -- Get the entry; stop if there's no more.
            local e = entries[i]
            if not e then break end
            -- Set the colors: invert if selected.
            entrywin.setCursorPos(2, i - scroll + 1)
            if i == selection then
                entrywin.setBackgroundColor(fgColor)
                entrywin.setTextColor(bgColor)
            else
                entrywin.setBackgroundColor(bgColor)
                entrywin.setTextColor(fgColor)
            end
            -- Draw the selection.
            entrywin.clearLine()
            entrywin.write(#e > width - 1 and e:sub(1, width - 4) .. "..." or e)
        end
        -- Draw scroll arrows.
        entrywin.setCursorPos(width, 1)
        entrywin.write(scroll > 1 and "\30" or " ")
        entrywin.setCursorPos(width, height)
        entrywin.write(scroll < #entries - height + 1 and "\31" or " ")
        -- Send updates to the screen.
        entrywin.setVisible(true)
    end
    -- Draw first screen.
    drawEntries()
    -- Add a task for selection keys.
    PrimeUI.addTask(function()
        while true do
            local _, key = os.pullEvent("key")
            if key == keys.down and selection < #entries then
                -- Move selection down.
                selection = selection + 1
                if selection > scroll + height - 1 then scroll = scroll + 1 end
                -- Send action if necessary.
                if type(selectChangeAction) == "string" then PrimeUI.resolve("selectionBox", selectChangeAction, selection)
                elseif selectChangeAction then selectChangeAction(selection) end
                -- Redraw screen.
                drawEntries()
            elseif key == keys.up and selection > 1 then
                -- Move selection up.
                selection = selection - 1
                if selection < scroll then scroll = scroll - 1 end
                -- Send action if necessary.
                if type(selectChangeAction) == "string" then PrimeUI.resolve("selectionBox", selectChangeAction, selection)
                elseif selectChangeAction then selectChangeAction(selection) end
                -- Redraw screen.
                drawEntries()
            elseif key == keys.enter then
                -- Select the entry: send the action.
                if type(action) == "string" then PrimeUI.resolve("selectionBox", action, entries[selection])
                else action(entries[selection]) end
            end
        end
    end)
end

--- Draws a thin border around a screen region.
---@param win Window The window to draw on
---@param x number The X coordinate of the inside of the box
---@param y number The Y coordinate of the inside of the box
---@param width number The width of the inner box
---@param height number The height of the inner box
---@param fgColor color|nil The color of the border (defaults to white)
---@param bgColor color|nil The color of the background (defaults to black)
function PrimeUI.borderBox(win, x, y, width, height, fgColor, bgColor)
  expect(1, win, "table")
  expect(2, x, "number")
  expect(3, y, "number")
  expect(4, width, "number")
  expect(5, height, "number")
  fgColor = expect(6, fgColor, "number", "nil") or colors.white
  bgColor = expect(7, bgColor, "number", "nil") or colors.black
  -- Draw the top-left corner & top border.
  win.setBackgroundColor(bgColor)
  win.setTextColor(fgColor)
  win.setCursorPos(x - 1, y - 1)
  win.write("\x9C" .. ("\x8C"):rep(width))
  -- Draw the top-right corner.
  win.setBackgroundColor(fgColor)
  win.setTextColor(bgColor)
  win.write("\x93")
  -- Draw the right border.
  for i = 1, height do
      win.setCursorPos(win.getCursorPos() - 1, y + i - 1)
      win.write("\x95")
  end
  -- Draw the left border.
  win.setBackgroundColor(bgColor)
  win.setTextColor(fgColor)
  for i = 1, height do
      win.setCursorPos(x - 1, y + i - 1)
      win.write("\x95")
  end
  -- Draw the bottom border and corners.
  win.setCursorPos(x - 1, y + height)
  win.write("\x8D" .. ("\x8C"):rep(width) .. "\x8E")
end

return PrimeUI