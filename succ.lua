local PrimeUI = require("primeui")

local file_helper = require "file_helper"
local data_dir = file_helper:instanced("data")

local LISTS_FILE = "lists.txt"
local NICKNAMES_FILE = "nicknames.txt"
local ITEMS_MOVED_FILE = "items_moved.txt"
local CONNECTIONS_FILE = "connections.txt"
local UPDATE_TICKRATE_FILE = "update_tickrate.txt"
local MOVING_ITEMS_FILE = "moving_items.txt"

local lists = data_dir:unserialize(LISTS_FILE, {})
local nicknames = data_dir:unserialize(NICKNAMES_FILE, {})
local items_moved = data_dir:unserialize(ITEMS_MOVED_FILE, 0)
local connections = data_dir:unserialize(CONNECTIONS_FILE, {})
local moving_items = data_dir:unserialize(MOVING_ITEMS_FILE, true)
local update_tickrate = data_dir:unserialize(UPDATE_TICKRATE_FILE, 10)

local function save()
  data_dir:serialize(LISTS_FILE, lists)
  data_dir:serialize(NICKNAMES_FILE, nicknames)
  data_dir:serialize(ITEMS_MOVED_FILE, items_moved)
  data_dir:serialize(CONNECTIONS_FILE, connections)
  data_dir:serialize(MOVING_ITEMS_FILE, moving_items)
  data_dir:serialize(UPDATE_TICKRATE_FILE, update_tickrate)
end

-- We are fine if this value fails to load, as it will not break the program.
if type(items_moved) ~= "number" then
  items_moved = 0
end
---@cast items_moved number

-- We are also fine if this value fails to load, as it will not break the program.
if type(update_tickrate) ~= "number" then
  update_tickrate = 10
end
---@cast update_tickrate number

-- We are also also fine if this value fails to load, as it will not break the program.
if type(nicknames) ~= "table" then
  nicknames = {}
end

-- We are not fine if this value fails to load, as it will break the program.
if type(connections) ~= "table" then
  error("Connections file might be corrupted, please check it for errors. Cannot read it currently.", 0)
end
---@cast connections table<string, string[]> -- connections[peripheral_name] = { "split"/"1234", peripheral_1, peripheral_2, ... }

-- We are also not fine if this value fails to load, as it will break the program.
if type(lists) ~= "table" then
  error("Lists file might be corrupted, please check it for errors. Cannot read it currently.", 0)
end
---@cast lists table<string, string[]> -- lists[peripheral_name] = { "whitelist"/"blacklist", item_1, item_2, ... }
-- Default for all connections is blacklist with no items.

local function count_table(tbl)
  local count = 0
  for _ in pairs(tbl) do
    count = count + 1
  end
  return count
end

--- Create an information box.
---@param win Window The window to draw the box on.
---@param title string The title of the box.
---@param desc string The description of the box.
---@param height integer The height of the box.
local function info_box(win, title, desc, height)
  local width = win.getSize()
  width = width - 4

  -- Info box with border
  PrimeUI.borderBox(win, 3, 3, width, height)
  PrimeUI.textBox(win, 3, 2, #title + 2, 1, ' ' .. title .. ' ', colors.purple)
  PrimeUI.textBox(win, 3, 3, width, height, desc, colors.lightGray)
end

--- Create a selection box, with a list of items.
---@param win Window The window to draw the box on.
---@param x integer The x position of the box.
---@param y integer The y position of the box.
---@param width integer The width of the box.
---@param height integer The height of the box.
---@param items string[] The items to display in the box.
---@param action string|fun(index: integer, scroll_index: integer) The action to perform when an item is selected.
---@param select_change_action nil|string|fun(index: integer, scroll_index: integer) The action to perform when the selection changes.
---@param fg_color integer The color of the text.
---@param bg_color integer The color of the background.
---@param initial_index integer The index of the item to select initially.
---@param initial_scroll integer The index of the item to scroll to initially.
---@param disabled boolean? Whether the box is disabled (displayed, but not interactable).
local function outlined_selection_box(win, x, y, width, height, items, action, select_change_action, fg_color, bg_color,
                                      initial_index, initial_scroll, disabled)
  -- Selection box with border
  PrimeUI.borderBox(win, x, y, width, height, fg_color, bg_color)

  -- Draw the items
  return PrimeUI.selectionBox(win, x, y, width + 1, height, items, action, select_change_action, fg_color, bg_color,
    initial_index, initial_scroll, disabled)
end

--- Create an outlined input box.
---@param win Window The window to draw the box on.
---@param x integer The x position of the box.
---@param y integer The y position of the box.
---@param width integer The width of the box.
---@param action string|fun(text: string) The action to perform when the input is submitted.
---@param fg_color integer The color of the text.
---@param bg_color integer The color of the background.
---@param replacement string? The replacement character for the input.
---@param history string[]? The history of inputs.
---@param completion_func nil|fun(text: string): string[] The function to call for completion.
---@param default string? The default text to display in the input box.
---@param disabled boolean? Whether the box is disabled (displayed, but not interactable).
local function outlined_input_box(win, x, y, width, action, fg_color, bg_color, replacement, history, completion_func, default, disabled)
  -- Input box with border
  PrimeUI.borderBox(win, x, y, width, 1, fg_color, bg_color)

  return PrimeUI.inputBox(win, x, y, width, action, fg_color, bg_color, replacement, history, completion_func, default, disabled)
end

--- Get all peripherals by their name
---@return string[] peripherals The list of peripheral names.
local function get_peripherals()
  local peripherals = peripheral.getNames()

  -- Replace names with nicknames
  for i, v in ipairs(peripherals) do
    peripherals[i] = v
  end

  -- Iterate through connections and add any peripherals from that list that
  -- have been disconnected.
  for name in pairs(connections) do
    for i, v in ipairs(peripherals) do
      local found = false
      if v == name then
        found = true
        break
      end
      if not found then
        table.insert(peripherals, "dc:" .. (nicknames[name] or name))
      end
    end
  end

  return peripherals
end

--- Connections menu
local function connections_menu()
  --[[
    ######################################################
    # Connections                                        #
    # Press tab to alternate between inputs and outputs. #
    # Press enter to toggle on a connection.             #
    # Press space to toggle connection mode.             #
    # Press backspace to exit.                           #
    # Connection mode: Fill 1 then fill 2 then fill 3... # -- Other modes: 'split evenly' (self-explanatory), 'none' (no connections currently), or
    #                                                    # -- 'output node' (this node is already set to be the output of something else, and cannot be an input)
    # Note: Connections are not saved until this menu is #
    #       closed.                                      #
    ######################################################
    ########## INPUT ######### ######### OUTPUT ##########
    # > peripheral_1         # # > peripheral_2          # -- Currently selected node will not appear in output list
    #   peripheral_2         # #   1. peripheral_3       # -- Selected nodes will be prefixed by their index in output list.
    #                        # #                         # -- output nodes will not show in input list
    ########################## ###########################
  ]]

  -- Outline the information box.
  local win = window.create(term.current(), 1, 1, term.getSize())
  local width, height = win.getSize()

  local selector_toggle = false
  local run = true

  local left_index = 1
  local right_index = 1
  local left_scroll = 1
  local right_scroll = 1
  local cached_peripheral_list = get_peripherals()

  --- Calculate possible outputs for a given input.
  --- This does NOT show disconnected peripherals.
  ---@param input string The input peripheral.
  ---@return string[] outputs The list of possible output peripherals.
  local function get_outputs(input)
    local outputs = {}

    -- Iterate through all peripherals, and if they are not the input, add them to the list.
    local peripherals = cached_peripheral_list

    for i, v in ipairs(peripherals) do
      if v ~= input then
        table.insert(outputs, v)
      end
    end

    return outputs
  end

  while run do
    PrimeUI.clear()

    -- Draw info box.
    local info =
    "Press tab to alternate between inputs and outputs.\nPress enter to toggle on a connection.\nPress space to toggle connection mode.\nPress backspace to exit.\nNote: Applies and saves on exit.\n\nConnection mode: %s"
    local connection_mode = connections[1] and connections[1][1] or "None"
    info_box(win, "Connections", info:format(connection_mode), 8)

    -- Draw the two bottom selection boxes.
    local width_half = math.floor(width / 2) - 3
    local height_selections = 6

    cached_peripheral_list = selector_toggle and cached_peripheral_list or get_peripherals()
    if #cached_peripheral_list == 0 then
      cached_peripheral_list = { "No peripherals" }
    end

    local peripherals_with_nicks = {}
    for i, v in ipairs(cached_peripheral_list) do
      table.insert(peripherals_with_nicks, nicknames[v] or v)
    end

    local outputs = get_outputs(cached_peripheral_list[left_index])
    local outputs_with_nicks = {}
    for i, v in ipairs(outputs) do
      table.insert(outputs_with_nicks, nicknames[v] or v)
    end

    outlined_selection_box(
      win,
      3, 13,
      width_half, height_selections,
      peripherals_with_nicks,
      "left", "change_left",
      selector_toggle and colors.gray or colors.white, colors.black,
      left_index, left_scroll,
      selector_toggle
    )
    PrimeUI.textBox(win, 3, 12, 8, 1, " Inputs ", selector_toggle and colors.gray or colors.purple)

    outlined_selection_box(
      win,
      width_half + 6, 13,
      width_half, height_selections,
      cached_peripheral_list[1] == "No peripherals" and { "No peripherals" } or outputs_with_nicks,
      "right", "change_right",
      selector_toggle and colors.white or colors.gray, colors.black,
      right_index, right_scroll,
      not selector_toggle
    )
    PrimeUI.textBox(win, width_half + 6, 12, 9, 1, " Outputs ", selector_toggle and colors.purple or colors.gray)

    -- Tab key: swaps which selection box is selected.
    PrimeUI.keyAction(keys.tab, "toggle_selector")

    -- Space key: toggles the connection mode
    PrimeUI.keyAction(keys.space, "toggle_mode")

    -- Backspace key: exits the menu
    PrimeUI.keyAction(keys.backspace, "exit")

    local object, event, selected, scroll = PrimeUI.run()

    if object == "keyAction" then
      if event == "toggle_selector" then
        selector_toggle = not selector_toggle
      elseif event == "toggle_mode" then
        if connections[left_index] then
          if connections[left_index][1] == "split" then
            connections[left_index][1] = "1234"
          elseif connections[left_index][1] == "1234" then
            connections[left_index][1] = "split"
          end
        end
      elseif event == "exit" then
        run = false
      end
    elseif object == "selectionBox" then
      if event == "left" then
        -- activate right box
        selector_toggle = not selector_toggle
      elseif event == "right" then
        -- Toggle connection from left node to this node.
      elseif event == "change_left" then
        left_index = selected
        left_scroll = scroll
        -- If the left changes, the right needs to be reset
        right_index = 1
        right_scroll = 1
        -- The items on the right also need to be recalculated.
      elseif event == "change_right" then
        right_index = selected
        right_scroll = scroll
      end
    end
  end
end

local function list_menu()

end

local function tickrate_menu()

end

local function nickname_menu()
  --[[
    ######################################################
    # Nicknames                                          #
    # Press enter to edit a nickname.                    #
    # Press backspace to exit.                           #
    ######################################################
    ######################################################
    # > peripheral_1                                     #
    #   peripheral_2                                     #
    #   peripheral_3                                     #
    #   ...                                              #
    #   ...                                              #
    ######################################################
    # nickname nickname nickname nickname nickname       #
    ######################################################
  ]]

  local run = true
  local index = 1
  local scroll = 1
  local win = window.create(term.current(), 1, 1, term.getSize())
  local width, height = win.getSize()
  local editing = false

  local cached_peripheral_list = get_peripherals()

  while run do
    PrimeUI.clear()

    -- Draw info box.
    local info = "Press enter to edit a nickname.\nPress backspace to exit (while not editing)."
    info_box(win, "Nicknames", info, 2)

    cached_peripheral_list = editing and cached_peripheral_list or get_peripherals()
    if #cached_peripheral_list == 0 then
      cached_peripheral_list = { "No peripherals" }
    end

    outlined_selection_box(
      win,
      3, 7,
      width - 4, 9,
      cached_peripheral_list,
      "edit", "change",
      editing and colors.gray or colors.white, colors.black,
      index, scroll,
      editing
    )
    PrimeUI.textBox(win, 3, 6, 13, 1, " Peripherals ", editing and colors.gray or colors.purple)

    outlined_input_box(
      win,
      3, height - 1,
      width - 4,
      "text_box",
      editing and colors.white or colors.gray, colors.black,
      nil, nil, nil,
      nicknames[cached_peripheral_list[index]] or cached_peripheral_list[index],
      not editing
    )
    local x, y = term.getCursorPos()
    PrimeUI.textBox(win, 3, height - 2, 10, 1, " Nickname ", editing and colors.purple or colors.gray)

    if not editing then
      -- Backspace key: exits the menu
      PrimeUI.keyAction(keys.backspace, "exit")
    end

    -- Reset the cursor position to be in the input box, and ensure it is visible if it needs to be.
    term.setCursorPos(x, y)
    term.setTextColor(colors.white)
    term.setCursorBlink(editing)

    -- Run the UI
    local object, event, selected, _scroll = PrimeUI.run()

    if object == "keyAction" then
      if event == "exit" then
        run = false
      end
    elseif object == "selectionBox" then
      if event == "edit" then
        -- Edit the nickname of the selected peripheral.
        editing = true
      elseif event == "change" then
        index = selected
        scroll = _scroll
      end
    elseif object == "inputBox" then
      if event == "text_box" then
        nicknames[cached_peripheral_list[index]] = selected
        editing = false
      end
    end
  end
end


--- Main menu
local function main_menu()
  local update_connections = "Update Connections"
  local whitelist_blacklist = "Change Connection Whitelists/Blacklists"
  local update_rate = "Change Update Rate"
  local nickname = "Change Peripheral Nicknames"
  local toggle = "Toggle Running"
  local exit = "Exit"

  local description = ("Select an option from the list below.\n\nTotal items moved: %d\nTotal connections: %d\n\nUpdate rate: Every %d tick%s\nRunning: %s")
      :format(
        items_moved,
        count_table(connections),
        update_tickrate,
        update_tickrate == 1 and "" or "s",
        moving_items and "Yes" or "No"
      )

  local win = window.create(term.current(), 1, 1, term.getSize())
  local width, height = win.getSize()

  PrimeUI.clear()

  -- Create the information box.
  info_box(win, "Main Menu", description, 7)

  -- Create the selection box.
  outlined_selection_box(win, 4, 13, width - 6, height - 13, {
    update_connections,
    whitelist_blacklist,
    update_rate,
    nickname,
    toggle,
    exit
  }, "selection", nil, colors.white, colors.black, 1, 1)

  local object, event, selected = PrimeUI.run()

  if selected == update_connections then
    connections_menu()
  elseif selected == whitelist_blacklist then
    list_menu()
  elseif selected == update_rate then
    tickrate_menu()
  elseif selected == nickname then
    nickname_menu()
  elseif selected == toggle then
    moving_items = not moving_items
  elseif selected == exit then
    print("Exiting...")
    return true
  end

  save()
end

while true do
  local ok, result = pcall(main_menu)
  if not ok then
    print() -- put the cursor back on the screen
    error(result, 0)
    break
  elseif result then
    print() -- put the cursor back on the screen
    break
  end
end
