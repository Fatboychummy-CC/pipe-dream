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
---@cast connections table<string, Connection[]>

---@class Connection
---@field name string The name of the connection.
---@field from string The peripheral the connection is from.
---@field to string[] The peripherals the connection is to.
---@field whitelist string[] The whitelist of items.
---@field blacklist string[] The blacklist of items.
---@field list_mode "whitelist"|"blacklist" The mode of the connection.
---@field mode "1234"|"split" The mode of the connection. 1234 means "push and fill 1, then 2, then 3, then 4". Split means "split input evenly between all outputs".
---@field moving boolean Whether the connection is active (moving items).

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
---@param override_title_color integer? The color of the title text.
local function info_box(win, title, desc, height, override_title_color)
  local width = win.getSize()
  width = width - 4

  -- Info box with border
  PrimeUI.borderBox(win, 3, 3, width, height)
  PrimeUI.textBox(win, 3, 2, #title + 2, 1, ' ' .. title .. ' ', override_title_color or colors.purple)
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

  local periph_lookup = {}
  for i, v in ipairs(peripherals) do
    periph_lookup[v] = true
  end

  -- Iterate through connections and add any peripherals from that list that
  -- have been disconnected.
  for name in pairs(connections) do
    if not periph_lookup[name] then
      table.insert(peripherals, "dc:" .. (nicknames[name] or name))
    end
  end

  return peripherals
end

--- Display the unacceptable input screen.
---@param _type "error"|"input"|string The type of error.
---@param reason string The reason for the error.
local function unacceptable(_type, reason)
  local win = window.create(term.current(), 1, 1, term.getSize())

  PrimeUI.clear()

  -- Draw info box.
  if _type == "error" then
    info_box(win, "Error", ("An error occurred.\n%s\n\nPress enter to continue."):format(reason), 10, colors.red)
  elseif _type == "input" then
    info_box(win, "Input Error", ("The last user input was unacceptable.\n%s\n\nPress enter to continue."):format(reason), 4, colors.red)
  else
    info_box(win, "Unknown Error", ("An unknown error occurred.\n%s\n\nPress enter to continue."):format(reason), 10, colors.red)
  end

  PrimeUI.keyAction(keys.enter, "exit")

  PrimeUI.run()
end

local function connections_add_menu()

end

local function connections_edit_menu()

end

local function connections_remove_menu()

end

--- Connections menu
local function connections_main_menu()
  --[[
    ######################################################
    # Connections                                        #
    #                                                    #
    # Total Connections: x                               #
    ######################################################
    ######################################################
    # > Add Connection                                   #
    #   Edit Connection                                  #
    #   Remove Connection                                #
    #   Go Back                                          # -- backspace will also work
    ######################################################
  ]]

  local win = window.create(term.current(), 1, 1, term.getSize())
  local width, height = win.getSize()

  while true do
    PrimeUI.clear()

    -- Draw info box.
    info_box(win, "Connections", ("Total Connections: %d"):format(count_table(connections)), 1)

    local add_connection = "Add Connection"
    local edit_connection = "Edit Connection"
    local remove_connection = "Remove Connection"
    local go_back = "Go Back"

    -- Draw the selection box.
    outlined_selection_box(win, 3, 6, width - 4, 4, {
      add_connection,
      edit_connection,
      remove_connection,
      go_back
    }, "selection", nil, colors.white, colors.black, 1, 1)

    PrimeUI.keyAction(keys.backspace, "exit")

    local object, event, selected = PrimeUI.run()

    if object == "selectionBox" then
      if selected == add_connection then
        unacceptable("error", "This feature is not yet implemented.")
      elseif selected == edit_connection then
        unacceptable("error", "This feature is not yet implemented.")
      elseif selected == remove_connection then
        unacceptable("error", "This feature is not yet implemented.")
      elseif selected == go_back then
        return
      end
    elseif object == "keyAction" and event == "exit" then
      return
    end
  end
end

local function list_menu()
  unacceptable("error", "This feature is not yet implemented.")
end

local function tickrate_menu()
  --[[
    ######################################################
    # Update Rate                                        #
    # Press enter to accept the update rate and exit.    #
    ######################################################
    ######################################################
    # Updates every [  10] ticks                         #
    ######################################################
  ]]

  local win = window.create(term.current(), 1, 1, term.getSize())
  local width, height = win.getSize()

  PrimeUI.clear()

  -- Draw info box.
  info_box(win, "Update Rate", "Press enter to accept the new update rate and exit.", 2)

  -- Draw the input box.
  -- First the text around the input box.
  PrimeUI.textBox(win, 3, 8, width - 4, 1, "Updates every [        ] ticks.", colors.white)

  -- And the outline
  PrimeUI.borderBox(win, 3, 8, width - 4, 1, colors.white, colors.black)

  -- Then the input box itself.
  local tickrate = tostring(update_tickrate)
  PrimeUI.inputBox(win, 18, 8, 8, "tickrate", colors.white, colors.black, nil, nil, nil, tickrate)

  local object, event, output = PrimeUI.run()

  if object == "inputBox" then
    if event == "tickrate" then
      local value = tonumber(output)
      if not value then
        unacceptable("input", "The input must be a number.")
      elseif value < 1 then
        unacceptable("input", "The input must be 1 or greater.")
      else
        update_tickrate = math.ceil(value) -- disallow decimals
      end
    end
  end
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
        if selected == cached_peripheral_list[index] or selected == "" then
          -- Remove the nickname
          nicknames[cached_peripheral_list[index]] = nil
        else
          -- Set the nickname
          nicknames[cached_peripheral_list[index]] = selected
        end
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
    connections_main_menu()
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
    ---@diagnostic disable-next-line ITS A HEKKIN STRING
    unacceptable("error", result)

    print() -- put the cursor back on the screen
    error(result, 0)
    break
  elseif result then
    print() -- put the cursor back on the screen
    break
  end
end
