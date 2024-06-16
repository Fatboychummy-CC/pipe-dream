local PrimeUI = require("primeui")

local thready = require "thready"
local file_helper = require "file_helper"
local data_dir = file_helper:instanced("data")
local logging = require "logging"

local log = logging.create_context("pipe_dream")
local logging_win
do
  local width, height = term.getSize()
  logging_win = window.create(term.current(), 3, 8, width - 4, height - 8)
  logging_win.setVisible(false)
  logging.set_window(logging_win)
end

local NICKNAMES_FILE = "nicknames.txt"
local ITEMS_MOVED_FILE = "items_moved.txt"
local CONNECTIONS_FILE = "connections.txt"
local MOVING_ITEMS_FILE = "moving_items.txt"
local UPDATE_TICKRATE_FILE = "update_tickrate.txt"

local nicknames = data_dir:unserialize(NICKNAMES_FILE, {})
local items_moved = data_dir:unserialize(ITEMS_MOVED_FILE, 0)
local connections = data_dir:unserialize(CONNECTIONS_FILE, {})
local moving_items = data_dir:unserialize(MOVING_ITEMS_FILE, true)
local update_tickrate = data_dir:unserialize(UPDATE_TICKRATE_FILE, 10)
log.info("Loaded data (or created defaults).")

local function save()
  data_dir:serialize(NICKNAMES_FILE, nicknames)
  data_dir:serialize(ITEMS_MOVED_FILE, items_moved)
  data_dir:serialize(CONNECTIONS_FILE, connections)
  data_dir:serialize(MOVING_ITEMS_FILE, moving_items)
  data_dir:serialize(UPDATE_TICKRATE_FILE, update_tickrate)
  log.info("Saved data.")
end

-- We are fine if this value fails to load, as it will not break the program.
if type(items_moved) ~= "number" then
  items_moved = 0
  log.warn("Items moved file is corrupted, resetting to 0.")
end
---@cast items_moved number

-- We are also fine if this value fails to load, as it will not break the program.
if type(update_tickrate) ~= "number" then
  update_tickrate = 10
  log.warn("Update tickrate file is corrupted, resetting to 10.")
end
---@cast update_tickrate number

-- We are also also fine if this value fails to load, as it will not break the program.
if type(nicknames) ~= "table" then
  nicknames = {}
  log.warn("Nicknames file is corrupted, resetting to empty table.")
end

-- We are not fine if this value fails to load, as it will break the program.
if type(connections) ~= "table" then
  error("Connections file might be corrupted, please check it for errors. Cannot read it currently.", 0)
end
---@cast connections Connection[]

---@class Connection
---@field name string The name of the connection.
---@field from string The peripheral the connection is from.
---@field to string[] The peripherals the connection is to.
---@field filter_list string[] The blacklist or whitelist of items.
---@field filter_mode "whitelist"|"blacklist" The item filter mode of the connection.
---@field mode "1234"|"split" The mode of the connection. 1234 means "push and fill 1, then 2, then 3, then 4". Split means "split input evenly between all outputs".
---@field moving boolean Whether the connection is active (moving items).
---@field id integer The unique ID of the connection.

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
local function outlined_input_box(win, x, y, width, action, fg_color, bg_color, replacement, history, completion_func,
                                  default, disabled)
  -- Input box with border
  PrimeUI.borderBox(win, x, y, width, 1, fg_color, bg_color)

  return PrimeUI.inputBox(win, x, y, width, action, fg_color, bg_color, replacement, history, completion_func, default,
    disabled)
end

--- Get all peripherals by their name
---@return string[] peripherals The list of peripheral names.
local function get_peripherals()
  local peripherals = peripheral.getNames()

  -- Replace names with nicknames
  for i, v in ipairs(peripherals) do
    peripherals[i] = v
  end

  --[[@fixme this code needs to be re-added
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
  ]]

  return peripherals
end

--- Display the unacceptable input screen.
---@param _type "error"|"input"|string The type of error.
---@param reason string The reason for the error.
local function unacceptable(_type, reason)
  local win = window.create(term.current(), 1, 1, term.getSize())

  log.warn("Unacceptable :", _type, ":", reason)

  PrimeUI.clear()

  -- Draw info box.
  if _type == "error" then
    info_box(win, "Error", ("An error occurred.\n%s\n\nPress enter to continue."):format(reason), 15, colors.red)
  elseif _type == "input" then
    info_box(win, "Input Error", ("The last user input was unacceptable.\n%s\n\nPress enter to continue."):format(reason),
      15, colors.red)
  else
    info_box(win, "Unknown Error", ("An unknown error occurred.\n%s\n\nPress enter to continue."):format(reason), 15,
      colors.red)
  end

  PrimeUI.keyAction(keys.enter, "exit")

  PrimeUI.run()
end

local keys_held = {}
local function key_listener()
  keys_held = {} -- Reset the keys held when this method is called.
  while true do
    local event, key = os.pullEvent()
    if event == "key" then
      keys_held[key] = true
    elseif event == "key_up" then
      keys_held[key] = nil
    end
  end
end

--- Verify a connection.
---@param connection_data Connection The connection data to verify.
---@return boolean valid Whether the connection is valid.
---@return string? error_message The error message if the connection is invalid.
local function verify_connection(connection_data)
  if not connection_data then
    return false, "Connection data is nil. This should not happen, and is a bug."
  end

  if not connection_data.name or connection_data.name == "" then
    return false, "Connection has no name."
  end

  if not connection_data.from or connection_data.from == "" then
    return false, "Origin not set."
  end

  if not connection_data.to or #connection_data.to == 0 then
    return false, "No destinations selected."
  end

  if not connection_data.filter_mode or (connection_data.filter_mode ~= "whitelist" and connection_data.filter_mode ~= "blacklist") then
    return false, "Filter mode is not set or is invalid."
  end

  if not connection_data.filter_list then
    return false, "Filter list is not set."
  end

  if not connection_data.mode or (connection_data.mode ~= "1234" and connection_data.mode ~= "split") then
    return false, "Mode is not set or is invalid."
  end

  return true, "Connection is valid, so you should not see this message. This is a bug if you do."
end

--- Confirmation menu with custom title and body.
---@param title string The title of the menu.
---@param body string The body of the menu.
---@param select_yes_default boolean? Whether the default selection is "Yes".
---@return boolean sure Whether the user is sure they want to exit without saving.
local function confirmation_menu(title, body, select_yes_default)
  local win = window.create(term.current(), 1, 1, term.getSize())
  local width, height = win.getSize()

  while true do
    PrimeUI.clear()

    -- Draw info box.
    info_box(win, title, body, 2)

    outlined_selection_box(win, 3, 7, width - 4, 2, {
      "Yes",
      "No"
    }, "selection", nil, colors.white, colors.black, select_yes_default and 1 or 2, 1)

    PrimeUI.keyAction(keys.backspace, "exit")

    local object, event, result = PrimeUI.run()

    if object == "selectionBox" then
      if event == "selection" then
        return result == "Yes"
      end
    elseif object == "keyAction" and event == "exit" then
      return false
    end
  end
end

--- Ask the user if they're sure they want to exit without saving.
---@return boolean sure Whether the user is sure they want to exit without saving.
local function confirm_exit_no_save()
  return confirmation_menu("Exit Without Saving", "Are you sure you want to exit without saving?", false)
end

--- Implement the connection filter editing menu.
---@param connection_data Connection The connection data to edit.
local function _connections_filter_edit_impl(connection_data)
  --[[
    # Filter connectionname ##############################
    # > Add item                                         # -- this box will turn into an info box if add/view/remove is selected
    #   View items                                       #
    #   Remove item                                      #
    #   Toggle blacklist/whitelist                       #
    ######################################################
    # Filter blacklist ################################### -- or whitelist...
    # minecraft:item_1                                   # -- If possible, the filter preview should scroll up and down if overfull
    # minecraft:item_2                                   # -- I believe we can use PrimeUI.addTask to do this, just have something
    # ...                                                # -- resolve PrimeUI after half a second or so?
    ######################################################
  ]]

  log.debug("Editing filter for connection", connection_data.name)

  local win = window.create(term.current(), 1, 1, term.getSize())
  local width, height = win.getSize()

  local items = connection_data.filter_list
  local item_count = #items

  ---@type "add"|"view"|"remove"|nil The selected action.
  local selected

  ---@type integer, integer The selected item in the preview box. Will be set to -1 unless it is active.
  local item_selected, item_scroll = -1, 1

  local items_y, items_height = 9, 10

  ---@type integer, integer For the main selection box.
  local main_selected, main_scroll = 1, 1

  ---@type integer When at either "edge" of the list, pause for this many iterations before reversing direction.
  local scroll_edge_pause = 5

  ---@type 1|0|-1 The direction to scroll in.
  local scroll_direction = 0
  ---@type 1|-1 The direction to swap to scrolling after the edge pause.
  local next_scroll_direction = 1

  local add_item, view_items, remove_item, toggle_mode, go_back = "Add item", "View items", "Remove item", "Toggle blacklist/whitelist", "Save and exit"

  local timer = os.startTimer(0.5)

  local no_items_toggle = true

  while true do
    PrimeUI.clear()

    -- If we've selected something, we can draw the info box for it.
    if selected == "add" then
      info_box(win, "Add item", "Enter the name of the item to add to the filter list, then press enter to confirm.", 2)
      outlined_input_box(win, 3, 7, width - 4, "add-item", colors.white, colors.black)
      PrimeUI.textBox(win, 3, 6, 11, 1, " Item Name ", colors.purple)

      items_y = 10
      items_height = 9
    elseif selected == "view" then
      info_box(win, "View items", "Press backspace to go back.", 1)
      items_y = 6
      items_height = 13
    elseif selected == "remove" then
      info_box(win, "Remove item", "Select the item to remove from the filter list.", 1)
      items_y = 6
      items_height = 13
    else
      items_y = 10
      items_height = 9

      -- No info box, just put the selection box in.
      outlined_selection_box(win, 3, 3, width - 4, 5, {
        add_item,
        view_items,
        remove_item,
        toggle_mode,
        go_back
      }, "select", "select-change", colors.white, colors.black, main_selected, main_scroll)
      PrimeUI.textBox(win, 3, 2, 11 + #connection_data.name, 1, " Filter - " .. connection_data.name, colors.purple)
    end

    local enable_selector = selected == "view" or selected == "remove"
    -- Draw the preview selection box
    outlined_selection_box(
      win,
      3, items_y,
      width - 4, items_height,
      #items == 0 and { no_items_toggle and "No items" or "" } or items,
      "select-item", "select-item-change",
      enable_selector and colors.white or colors.gray, colors.black,
      item_selected, item_scroll,
      not enable_selector
    )
    PrimeUI.textBox(
      win,
      3, items_y - 1,
      2 + #connection_data.filter_mode, 1,
      ' ' .. connection_data.filter_mode .. ' ',
      enable_selector and colors.purple or colors.gray
    )

    if selected ~= "add" then -- Add stops working due to read implementation
      PrimeUI.addTask(function()
        repeat
          local _, timer_id = os.pullEvent("timer")
        until timer_id == timer

        no_items_toggle = not no_items_toggle
        PrimeUI.resolve("scroller")
      end)

      -- Read needs backspace, so we only activate it if not in add mode.
      PrimeUI.keyAction(keys.backspace, "exit")
    end


    local object, event, result, selection, scroll_result = PrimeUI.run()

    local function reset_scroller()
      scroll_direction = 0
      next_scroll_direction = 1
      scroll_edge_pause = 5
      item_scroll = 1
      item_selected = -1
    end

    if object == "selectionBox" then
      if event == "select-change" then
        main_selected = selection
        main_scroll = scroll_result
      elseif event == "select-item-change" then
        item_selected = selection
        item_scroll = scroll_result
      elseif event == "select" then
        if result == add_item then
          selected = "add"
          log.debug("Selected add item")
        elseif result == view_items then
          selected = "view"
          item_selected = 1
          item_scroll = 1
          log.debug("Selected view items")
        elseif result == remove_item then
          selected = "remove"
          item_selected = 1
          item_scroll = 1
          log.debug("Selected remove item")
        elseif result == toggle_mode then
          connection_data.filter_mode = connection_data.filter_mode == "whitelist" and "blacklist" or "whitelist"
          log.debug("Toggled filter mode to", connection_data.filter_mode)
        elseif result == go_back then
          save()

          log.debug("Exiting filter edit for connection", connection_data.name)
          return
        end
      elseif event == "select-item" then
        if selected == "remove" then
          if items[selection] and confirmation_menu("Remove item", "Are you sure you want to remove item " .. tostring(items[selection]) .. "?") then
            log.debug("Remove item", items[selection], "from filter list for connection", connection_data.name)

            table.remove(items, selection)
            item_count = item_count - 1

            -- Offset the selected item, since we just removed one.
            item_selected = item_selected - 1
            if item_selected < 1 then
              item_selected = 1
            end
            if item_selected < item_scroll then
              item_scroll = item_selected
            end
          end
          -- Exit the selection mode
          selected = nil
          reset_scroller()

          -- Restart the timer, since we did something that may take longer than 0.5 secs
          timer = os.startTimer(0.5)
        end
      end
    elseif object == "scroller" then
      -- scroll the preview box
      timer = os.startTimer(0.5)

      if not enable_selector and item_count > items_height then

        item_scroll = item_scroll + scroll_direction

        if item_scroll < 1 then
          item_scroll = 1
          scroll_direction = 0
          next_scroll_direction = 1
          scroll_edge_pause = 5
        elseif item_scroll > item_count - items_height + 1 then
          item_scroll = item_count - items_height + 1
          scroll_direction = 0
          next_scroll_direction = -1
          scroll_edge_pause = 5
        end

        if scroll_edge_pause > 0 then
          scroll_edge_pause = scroll_edge_pause - 1
        else
          scroll_direction = next_scroll_direction
        end
      end
    elseif object == "keyAction" and event == "exit" then
      if selected then
        -- <something> was selected, so go back to the "main" section, reverting
        -- data to defaults.
        selected = nil
        reset_scroller()
      else
        save()
        return
      end
    elseif object == "inputBox" then
      if event == "add-item" then
        if result and result ~= "" then
          table.insert(connection_data.filter_list, result)
          item_count = item_count + 1
          log.debug("Added item", result, "to filter list for connection", connection_data.name)
        elseif result == "" then
          log.debug("Add empty item, ignored.")
        end

        selected = nil
        reset_scroller()

        -- Restart the timer, since we did something that may take longer than 0.5 secs
        timer = os.startTimer(0.5)
      end
    end
  end
end

--- Implement the connection editing menu.
---@param connection_data Connection? The connection data to edit.
local function _connections_edit_impl(connection_data)
  --[[
    # Add Connection ##################################### -- Sections will expand/contract as needed.
    # Enter the name of this connection                  # -- Info box will change depending on expanded section.
    # Press enter when done.                             #
    ######################################################
    # Name ###############################################
    # blablabla                                          #
    ######################################################
    # Origin #############################################
    # peripheral_1                                       #
    ######################################################
    # Destinations #######################################
    # peripheral_2                                       #
    # peripheral_3                                       #
    # ...                                                #
    ######################################################
    # Filter Mode ########################################
    # Whitelist                                          #
    # Blacklist                                          #
    ######################################################
    # Filters ############################################
    # item_1                                             #
    # item_2                                             #
    # ...                                                #
    ######################################################
    # Mode ###############################################
    # Fill 1, then 2, then 3, then 4                     #
    # Split evenly                                       #
    ######################################################
  ]]
  local _connection_data = {
    name = "",
    from = "",
    to = {},
    filter_list = {},
    filter_mode = "blacklist",
    mode = "1234",
    moving = false, -- New connections will be disabled by default
    id = os.epoch("utc")
  }
  if connection_data then
    _connection_data.name = connection_data.name or _connection_data.name
    _connection_data.from = connection_data.from or _connection_data.from
    _connection_data.to = connection_data.to or _connection_data.to
    _connection_data.filter_list = connection_data.filter_list or _connection_data.filter_list
    _connection_data.filter_mode = connection_data.filter_mode or _connection_data.filter_mode
    _connection_data.mode = connection_data.mode or _connection_data.mode
    _connection_data.moving = connection_data.moving or _connection_data.moving
    _connection_data.id = connection_data.id or _connection_data.id

    log.debug("Editing connection", _connection_data.name)
  else
    log.debug("Creating new connection")
  end

  --- If the connection is from a non-inventory type peripheral, it is
  --- connection limited, and can only move items to one destination. This means
  --- the filter and mode options should be disabled.
  local connection_limited = false

  local cached_peripheral_list = get_peripherals()
  local expanded_section = 1

  local win = window.create(term.current(), 1, 1, term.getSize())
  local width, height = win.getSize()

  local periphs_with_nicknames = {}             -- predeclare so section_info can access it.
  local destination_periphs_with_nicknames = {} -- predeclare so section_info can access it.


  local section_infos = {
    {
      name = (
        (_connection_data.name == "") and "Name" or
        "Name - " .. _connection_data.name
      ),
      info =
      "Enter the name of this connection\nPress enter to save section data, tab to go to the next step, and shift+tab to go back.",
      size = 1,
      object = "input_box",
      args = {
        default = _connection_data.name,
        action = "set-name",
      },
      increment_on_enter = true,
      disable_when_limited = false,
    },
    {
      name = (
        (_connection_data.from == "") and "Origin" or
        "Origin - " .. (nicknames[_connection_data.from] or _connection_data.from)
      ),
      info = "Select the peripheral this connection is from.",
      size = 7,
      object = "selection_box",
      args = {
        action = "select-origin",
        items = periphs_with_nicknames,
      },
      increment_on_enter = true,
      disable_when_limited = false,
    },
    {
      name = (
        (#_connection_data.to == 0) and "Destinations" or
        "Destinations - " .. (#_connection_data.to) .. " selected"
      ),
      info = "Select the peripherals this connection is to.",
      connection_limited_info = "This connection is limited, and can only set a single destination.",
      size = 7,
      object = "selection_box",
      args = {
        action = "select-destination",
        items = destination_periphs_with_nicknames,
      },
      increment_on_enter = false,
      disable_when_limited = false,
    },
    {
      name = (
        (_connection_data.filter_mode == "") and "Filter Mode" or
        "Filter Mode - " .. _connection_data.filter_mode
      ),
      info = "Select the filter mode of the connection. The list starts empty, and you can edit it in another menu.",
      connection_limited_info = "This connection is limited, filters cannot apply to it.",
      size = 2,
      object = "selection_box",
      args = {
        action = "select-filter_mode",
        items = { "Blacklist", "Whitelist" },
      },
      increment_on_enter = true,
      disable_when_limited = true,
    },
    {
      name = (
        (_connection_data.mode == "") and "Mode" or
        "Mode - " .. _connection_data.mode
      ),
      info = "Select the mode of the connection.",
      connection_limited_info = "This connection is limited, and can only be to one destination.",
      size = 2,
      object = "selection_box",
      args = {
        action = "select-mode",
        items = { "Fill 1, then 2, then 3, then 4", "Split evenly" },
      },
      increment_on_enter = true,
      disable_when_limited = true,
    }
  }

  local function save_connection()
    local ok, err = verify_connection(_connection_data)
    if ok then
      -- Search the connections list for a connection with this ID.
      for i, v in ipairs(connections) do
        if v.id == _connection_data.id then
          connections[i] = _connection_data
          save()
          return true
        end
      end

      -- If we made it here, we didn't find the connection in the list.
      -- Thus, this must be a new connection.
      -- We can just insert it into the list.
      table.insert(connections, _connection_data)

      return true
    else
      unacceptable("input", "Connection data is malformed or incorrect: " .. tostring(err))
      return false
    end
  end

  while true do
    if expanded_section > #section_infos then
      if save_connection() then
        return
      end
      expanded_section = #section_infos
    end

    local section_info = section_infos[expanded_section]

    -- Update peripheral list
    -- Clear the list
    while periphs_with_nicknames[1] do
      table.remove(periphs_with_nicknames)
    end
    while destination_periphs_with_nicknames[1] do
      table.remove(destination_periphs_with_nicknames)
    end

    -- Add the peripherals to the list
    -- Step 1: Add the peripherals to the list
    for i, v in ipairs(cached_peripheral_list) do
      periphs_with_nicknames[i] = nicknames[v] or v -- we can just outright add the nicknames here for this table.
      local found = false

      for j = 1, #_connection_data.to do
        if _connection_data.to[j] == v then
          destination_periphs_with_nicknames[i] = j .. ". " .. periphs_with_nicknames[i]
          found = true
          break
        end
      end

      if not found then
        destination_periphs_with_nicknames[i] = periphs_with_nicknames[i]
      end
    end

    -- Begin drawing
    PrimeUI.clear()

    -- Draw info box.
    info_box(win, "Add Connection", connection_limited and section_info.connection_limited_info or section_info.info, 3)

    local y = 8

    -- Draw the sections
    for i = 1, #section_infos do
      local section = section_infos[i]
      local expanded = i == expanded_section
      local color = expanded and colors.purple or colors.gray

      local text = ' ' .. section.name .. ' '
      if section.disable_when_limited and connection_limited then
        text = ' ' .. section.name:gsub(" ?%-.+", "") .. ' ' .. "- Connection Limited "
      end

      if expanded then
        -- Draw the stuffs
        local object = section.object
        local args = section.args

        if object == "input_box" then
          -- Input box
          outlined_input_box(win, 3, y, width - 4, args.action, colors.white, colors.black, nil, nil, nil, args.default)
        elseif object == "selection_box" then
          -- Selection box

          if #args.items == 0 then
            args.items = { "No peripherals" }
          end

          outlined_selection_box(win, 3, y, width - 4, section.size, args.items, args.action, nil, section.disable_when_limited and connection_limited and colors.red or colors.white,
            colors.black, args.selection or 1, args.scroll or 1, section.disable_when_limited and connection_limited)
        else
          error("Invalid object type '" .. tostring(object) .. "' at index " .. i)
        end

        -- Draw the text box
        PrimeUI.textBox(win, 3, y - 1, #text, 1, text, section.disable_when_limited and connection_limited and colors.orange or color, colors.black)
      else
        -- Draw the border box and text box
        PrimeUI.borderBox(win, 3, y, width - 4, -1, color, colors.black)
        PrimeUI.textBox(win, 3, y - 1, #text, 1, text, color, colors.black)
      end

      y = y + (expanded and section.size + 2 or 1)
    end

    -- Tab: advance the expanded section, saving any relevant data.
    -- shift+tab: go back a section, saving any relevant data.
    PrimeUI.keyAction(keys.tab, "section_switch")

    local object, event, result, selection, scroll_result = PrimeUI.run()

    if object == "keyAction" then
      if event == "section_switch" then
        if keys_held[keys.leftShift] then
          log.debug("Go back a section.")
          expanded_section = expanded_section - 1
          if expanded_section < 1 then
            if confirm_exit_no_save() then
              log.debug("User confirmed exit without save.")
              return
            end
            expanded_section = 1
          end
        else
          log.info("Advance a section.")
          expanded_section = expanded_section + 1
          if expanded_section > #section_infos then
            if save_connection() then
              log.debug("Connection updated and saved, exiting this menu.")
              return
            end

            expanded_section = #section_infos
          end
        end
      end
    elseif object == "selectionBox" then
      if event == "select-origin" then
        local becomes_limited = not peripheral.hasType(cached_peripheral_list[selection], "inventory")

        if becomes_limited and #_connection_data.to > 1 then
          unacceptable("input", "The last request would make this connection limited, and would only be able to have one destination.\nRemove all but one destination and try again.")
        else
          connection_limited = becomes_limited
          _connection_data.from = cached_peripheral_list[selection]
          section_info.name = "Origin - " .. result
          log.debug("Selected origin", _connection_data.from)
        end
      elseif event == "select-destination" then
        -- Insert the peripheral into the list of destinations.
        -- Unless it is already in the list, in which case remove it.
        local found = false

        for i = 1, #_connection_data.to do
          if _connection_data.to[i] == cached_peripheral_list[selection] then
            table.remove(_connection_data.to, i)
            found = true
            log.debug("Removed destination", cached_peripheral_list[selection])
            break
          end
        end

        section_info.args.selection = selection
        section_info.args.scroll = scroll_result

        if connection_limited and #_connection_data.to > 1 then
          unacceptable("input", "This connection is connection limited, and can only have one destination.\nIf you need more destinations, create a buffer chest connection.")
        else
          if not found then
            table.insert(_connection_data.to, cached_peripheral_list[selection])
            log.debug("Added destination", cached_peripheral_list[selection])
          end

          if #_connection_data.to == 0 then
            section_info.name = "Destinations"
          else
            section_info.name = "Destinations - " .. (#_connection_data.to) .. " selected"
          end
        end
      elseif event == "select-filter_mode" then
        _connection_data.filter_mode = selection == 1 and "blacklist" or "whitelist"

        section_info.name = "Filter Mode - " .. _connection_data.filter_mode

        log.debug("Selected filter mode", _connection_data.filter_mode)
      elseif event == "select-mode" then
        _connection_data.mode = selection == 1 and "1234" or "split"

        section_info.name = "Mode - " .. _connection_data.mode

        log.debug("Selected mode", _connection_data.mode)
      end

      if section_info.increment_on_enter then
        expanded_section = expanded_section + 1
      end
    elseif object == "inputBox" then
      if event == "set-name" then
        _connection_data.name = result
        section_info.args.default = result
        section_info.name = "Name - " .. result

        log.debug("Set name to", result)
      end

      if section_info.increment_on_enter then
        expanded_section = expanded_section + 1
      end
    end
  end
end

--- Menu to add a new connection.
local function connections_add_menu()
  log.debug("Add connection")
  parallel.waitForAny(key_listener, _connections_edit_impl)
end

--- A quick menu to select a connection, with a custom header.
---@param title string The title of the menu.
---@param body string The body of the menu.
---@return Connection? connection The connection selected, or nil if none was selected.
local function select_connection(title, body)
  local win = window.create(term.current(), 1, 1, term.getSize())
  local width, height = win.getSize()

  log.debug("Select a connection")

  while true do
    PrimeUI.clear()

    -- Draw info box.
    info_box(win, title, body, 2)

    local connection_list = {}
    for i, v in ipairs(connections) do
      connection_list[i] = v.name
    end

    if #connection_list == 0 then
      connection_list = { "No connections" }
    end

    outlined_selection_box(win, 3, 7, width - 4, 12, connection_list, "edit", nil, colors.white, colors.black, 1, 1)
    PrimeUI.textBox(win, 3, 6, 13, 1, " Connections ", colors.purple)

    PrimeUI.keyAction(keys.backspace, "exit")

    local object, event, selected, selection = PrimeUI.run()

    if object == "selectionBox" then
      if event == "edit" then
        log.debug("Selected connection", selection, "(", selected, ")")
        return connections[selection]
      end
    elseif object == "keyAction" and event == "exit" then
      log.debug("Exit connection selection.")
      return
    end
  end
end

--- Edit a connection
local function connections_edit_menu()
  log.debug("Edit connection")
  local connection = select_connection("Edit Connection", "Press enter to edit a connection.\nPress backspace to exit.")

  if connection then
    parallel.waitForAny(key_listener, function()
      _connections_edit_impl(connection)
    end)
  end
end

--- Edit whitelist/blacklist of a connection
local function connections_filter_menu()
  log.debug("Edit connection filter")
  local connection = select_connection("Edit Connection Filter", "Press enter to edit a connection's filter.\nPress backspace to exit.")

  if connection then
    parallel.waitForAny(key_listener, function()
      _connections_filter_edit_impl(connection)
    end)
  end
end

local function connections_remove_menu()
  log.debug("Remove connection")
  local connection = select_connection("Remove Connection", "Press enter to remove a connection.\nPress backspace to exit.")

  if connection and confirmation_menu("Remove Connection", "Are you sure you want to remove connection " .. tostring(connection.name) .. "?") then
    for i, v in ipairs(connections) do
      if v == connection then
        table.remove(connections, i)
        return
      end
    end
  end
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
  log.debug("Connections menu")

  local win = window.create(term.current(), 1, 1, term.getSize())
  local width, height = win.getSize()

  while true do
    PrimeUI.clear()

    -- Draw info box.
    info_box(win, "Connections", ("Total Connections: %d"):format(#connections), 1)

    local add_connection = "Add Connection"
    local edit_connection = "Edit Connection"
    local filter_connection = "Edit Connection Filter"
    local remove_connection = "Remove Connection"
    local go_back = "Go Back"

    -- Draw the selection box.
    outlined_selection_box(win, 3, 6, width - 4, 5, {
      add_connection,
      edit_connection,
      filter_connection,
      remove_connection,
      go_back
    }, "selection", nil, colors.white, colors.black, 1, 1)

    PrimeUI.keyAction(keys.backspace, "exit")

    local object, event, selected = PrimeUI.run()

    if object == "selectionBox" then
      if selected == add_connection then
        connections_add_menu()
      elseif selected == edit_connection then
        connections_edit_menu()
      elseif selected == filter_connection then
        connections_filter_menu()
      elseif selected == remove_connection then
        connections_remove_menu()
      elseif selected == go_back then
        save()
        log.debug("Exiting connections menu.")
        return
      end

      save()
    elseif object == "keyAction" and event == "exit" then
      save()
      log.debug("Exiting connections menu.")
      return
    end
  end
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
  log.debug("Update tickrate menu")

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
        log.debug("Set update tickrate to", update_tickrate)
      end
    end
  end
end

--- The nickname menu
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
  log.debug("Nickname menu")

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
    local object, event, selected, _selection, _scroll = PrimeUI.run()

    if object == "keyAction" then
      if event == "exit" then
        run = false
        log.debug("Exiting nickname menu.")
      end
    elseif object == "selectionBox" then
      if event == "edit" then
        -- Edit the nickname of the selected peripheral.
        editing = true
        log.debug("Editing nickname for", selected)
      elseif event == "change" then
        index = _selection
        scroll = _scroll
      end
    elseif object == "inputBox" then
      if event == "text_box" then
        if selected == cached_peripheral_list[index] or selected == "" then
          -- Remove the nickname
          nicknames[cached_peripheral_list[index]] = nil

          log.debug("Removed nickname for", cached_peripheral_list[index])
        else
          -- Set the nickname
          nicknames[cached_peripheral_list[index]] = selected

          log.debug("Set nickname for", cached_peripheral_list[index], "to", selected)
        end
        editing = false
      end
    end
  end
end

--- Log menu
local function log_menu()
  log.info("Hello there!")

  PrimeUI.clear()

  local win = window.create(term.current(), 1, 1, term.getSize())
  local width, height = win.getSize()

  local function draw_main()
    -- Draw the info box.
    info_box(
      win,
      "Log",
      "Press enter to dump log to a file.\nPress c to clear warns/errors.\nPress backspace to exit.",
      3
    )

    -- Draw a box around where the log will be displayed.
    PrimeUI.borderBox(win, 3, 8, width - 4, height - 8, colors.white, colors.black)

    -- Draw the log window
    logging_win.setVisible(true)
  end

  draw_main()

  PrimeUI.keyAction(keys.backspace, "exit")
  PrimeUI.keyAction(keys.enter, "dump")

  local object, event = PrimeUI.run()

  if object == "keyAction" then
    if event == "exit" then
      log.info("Exiting log menu.")
    elseif event == "dump" then
      log.info("Getting output file...")

      PrimeUI.clear()

      draw_main()

      outlined_input_box(win, 4, 4, width - 6, "output", colors.white, colors.black, nil, nil, nil, "log.txt")
      PrimeUI.textBox(win, 4, 3, 10, 1, " Filename ", colors.purple)

      local object, event, output = PrimeUI.run()

      if object == "inputBox" and event == "output" then
        log.info("Dumping log to", output)

        logging.dump_log(output)
      end
    end
  end
end

--- Main menu
local function main_menu()
  local update_connections = "Update Connections"
  local update_rate = "Change Update Rate"
  local nickname = "Change Peripheral Nicknames"
  local toggle = "Toggle Running"
  local view_log = "View Log"
  local exit = "Exit"

  log.info("Start main menu")

  local menu_timer_timeout = 5
  local menu_timer = os.startTimer(menu_timer_timeout)

  local selection, scroll = 1, 1

  while true do
    local description = ("Select an option from the list below.\n\nTotal items moved: %d\nTotal connections: %d\n\nUpdate rate: Every %d tick%s\nRunning: %s")
        :format(
          items_moved,
          #connections,
          update_tickrate,
          update_tickrate == 1 and "" or "s",
          moving_items and "Yes" or "No"
        )

    local win = window.create(term.current(), 1, 1, term.getSize())
    local width, height = win.getSize()

    PrimeUI.clear()

    -- Create the information box.
    info_box(win, "Main Menu", description, 8)

    -- Create the selection box.
    outlined_selection_box(win, 4, 12, width - 6, height - 12, {
      update_connections,
      update_rate,
      nickname,
      toggle,
      view_log,
      exit
    }, "selection", "selection-change", colors.white, colors.black, selection, scroll)

    PrimeUI.addTask(function()
      repeat
        local _, timer_id = os.pullEvent("timer")
      until timer_id == menu_timer

      PrimeUI.resolve("timeout")
    end)

    local object, event, selected, _selection, _scroll = PrimeUI.run()
    log.debug("Selected", selected)

    if object == "selectionBox" then
      if event == "selection" then
        if selected == update_connections then
          connections_main_menu()
        elseif selected == update_rate then
          tickrate_menu()
        elseif selected == nickname then
          nickname_menu()
        elseif selected == toggle then
          moving_items = not moving_items
          log.debug("Toggled running to", moving_items)
        elseif selected == view_log then
          log_menu()
        elseif selected == exit then
          log.info("Exiting program")
          save()
          return true
        end
        save()
        menu_timer = os.startTimer(menu_timer_timeout)
      elseif event == "selection-change" then
        selection = _selection
        scroll = _scroll
      end
    elseif object == "timeout" then
      save()
      menu_timer = os.startTimer(menu_timer_timeout)
    end
  end
end

------------------------
-- Inventory Section
------------------------

---@class inventory_request
---@field funcs function[] The inventory requests to call, wrapped with arguments (i.e: {function() return inventory.getItemDetail(i) end, ...}). The returned value will be stored in the results field.
---@field id integer The ID of the request, used to identify it in the queue.
---@field results table[] The results of the inventory requests, in the same order as funcs.

local backend_log = logging.create_context("backend")

---@type integer The ID of the last inventory request.
local last_inventory_request_id = 0

---@type inventory_request[] A queue of inventory requests to process.
local inventory_request_queue = {}

---@type integer A soft maximum number of inventory requests to process at once.
local max_inventory_requests = 175

---@type integer If inserting the current job will overflow the max_inventory_requests, this is how much we are allowed to go over before the job is rejected. Thus, a hard limit of max_inventory_requests + max_inventory_requests_overflow is enforced.
local max_inventory_requests_overflow = 25

---@type boolean If we are actually processing something at this very moment. Used so that we can determine whether or not queueing a `inventory_request:new` event is necessary.
local processing_inventory_requests = false


--- Process inventory requests. We can run up to 256 of these at once (event queue length)
--- However, we will likely use a smaller value to allow for space for other events to not
--- overflow the queue.
local function process_inventory_requests()
  local current = {}
  local result_ts = {}
  local result_events = {}
  local current_n = 0

  --- Process the current request queue, or do nothing if there are no requests.
  local function process_queue()
    if current_n == 0 then return end

    backend_log.debug("Processing", current_n, "inventory requests.")

    local funcs = {}

    for i = 1, current_n do
      local func = current[i]
      local result = result_ts[i]

      funcs[i] = function()
        result.out[result.index] = func()
      end
    end

    parallel.waitForAll(table.unpack(funcs, 1, current_n))

    for _, event in ipairs(result_events) do
      os.queueEvent("inventory_request:" .. event)
    end

    current = {}
    result_ts = {}
    result_events = {}
    current_n = 0
  end

  while true do
    processing_inventory_requests = true

    while inventory_request_queue[1] do
      local request = inventory_request_queue[1]
      local count = #request.funcs

      if current_n + count > max_inventory_requests + max_inventory_requests_overflow then
        process_queue()
      end

      for i = 1, count do
        current[current_n + i] = request.funcs[i]
        result_ts[current_n + i] = {out = request.results, index = i}
      end
      result_events[#result_events + 1] = request.id

      current_n = current_n + count
    end

    process_queue()
    processing_inventory_requests = false

    os.pullEvent("inventory_request:new") -- Wait for new requests
  end
end

--- Make an inventory request, then wait until it completes.
---@param funcs function[] The inventory requests to call, wrapped with arguments (i.e: {function() return inventory.getItemDetail(i) end, ...}).
---@return table[] The results of the inventory requests, in the same order as funcs.
local function make_inventory_request(funcs)
  last_inventory_request_id = last_inventory_request_id + 1
  local id = last_inventory_request_id
  local results = {}

  backend_log.debug("New inventory request:", id)

  -- insert request data into the queue
  table.insert(inventory_request_queue, {funcs = funcs, id = id, results = results})

  -- If we are not currently processing inventory requests, queue a new event to start the process.
  if not processing_inventory_requests then
    os.queueEvent("inventory_request:new")
  end

  -- Wait for the results to be filled in.
  os.pullEvent("inventory_request:" .. id)

  backend_log.debug("Inventory request", id, "completed.")

  return results
end

--- Determines if the item can be moved from one inventory to another, given the filter mode and filter.
---@param item string The item to check.
---@param list string[] The list of items to check against.
---@param mode "whitelist"|"blacklist" The mode to use.
local function can_move(item, list, mode)
  if mode ~= "whitelist" and mode ~= "blacklist" then
    error("Invalid mode '" .. tostring(mode) .. "'")
  end

  -- Whitelist
  if mode == "whitelist" then
    for _, v in ipairs(list) do
      if v == item then
        return true
      end
    end

    return false
  end

  -- Blacklist
  for _, v in ipairs(list) do
    if v == item then
      return false
    end
  end

  return true
end

--- Run a connection from the "origin" node.
--- We do this without context of the endpoint nodes, as we can't guarantee that they are inventories.
---@param connection Connection The connection to run.
local function _run_connection_from_origin(connection)
  local filter = connection.filter_list
  local filter_mode = connection.filter_mode
  local mode = connection.mode
  local from = connection.from
  local to = connection.to

  local inv = peripheral.wrap(from) --[[@as Inventory?]]

  if not inv then
    backend_log.warn("Connection", connection.name, "failed to run: origin peripheral is missing.")
    return
  end

  local inv_contents = inv.list()

  -- If the inventory is empty, we can't do anything.
  if not next(inv_contents) then
    backend_log.debug("Connection", connection.name, "is empty, skipping.")
    return
  end

  local funcs = {}
  if mode == "1234" then
    -- Iterate through each inventory, and push whatever remains in the input inventory to the selected output.
    for _, output_inventory in ipairs(to) do
      -- Queue up the items to move.
      for slot, item in pairs(inv_contents) do
        -- if items are left in this slot, and the item matches the filter, queue the move.
        if item.count > 0 and can_move(item.name, filter, filter_mode) then
          funcs[#funcs + 1] = function()
            local moved = inv.pushItems(output_inventory, slot)

            items_moved = items_moved + moved  -- track the number of items moved.

            if moved then
              item.count = item.count - moved
            end
          end
        end
      end

      if #funcs == 0 then
        break -- we are done moving items.
      end

      -- Actually run the request.
      make_inventory_request(funcs)

      -- Clear the funcs table for the next iteration.
      funcs = {}
    end
  else -- mode == "split"
    -- First, we need to calculate how much of each item (that we can move) in the inventory
    -- we have, then split it evenly between the output inventories.
    local item_counts = {}

    for _, item in pairs(inv_contents) do
      if can_move(item.name, filter, filter_mode) then
        if not item_counts[item.name] then
          item_counts[item.name] = 0
        end

        item_counts[item.name] = item_counts[item.name] + item.count
      end
    end

    -- Next, we need to calculate how many items to move to each inventory.
    -- We can do this by simply dividing each item count by the number of inventories.
    local inv_count = #to

    for name, count in pairs(item_counts) do
      local split = math.floor(count / inv_count)

      item_counts[name] = split
    end

    -- Finally, we can start pushing items to the inventories.
    -- We will repeat the process until we have moved all of the (current) items in the inventory.
    -- In theory this shouldn't be an infinite loop?
    while true do
      for slot, item in pairs(inv_contents) do
        if item.count > 0 and item_counts[item.name] then
          funcs[#funcs + 1] = function()
            local moved = inv.pushItems(to[1], slot, item_counts[item.name])

            items_moved = items_moved + moved  -- track the number of items moved.

            if moved then
              item.count = item.count - moved
            end
          end
        end
      end

      if #funcs == 0 then
        break -- we are done moving items.
      end

      -- Actually run the request.
      make_inventory_request(funcs)

      -- Clear the funcs table for the next iteration.
      funcs = {}
    end
  end
end

--- Run a connection to a single 'to' node.
---@param connection Connection The connection to run.
local function _run_connection_to_inventory(connection)
  local from = connection.from
  local to = connection.to[1]

  -- We cannot see what is in the `from` node, since we cannot `.list()` or even
  -- `.size()` it.
  -- This means we cannot apply the filter or anything. Instead, the user should
  -- create another connection from the `to` node with the filters applied.
  --
  -- As well, since we don't know the items inside or even the size, we will
  -- call `pullItems` as many times as we have slots in `to`.

  local inv = peripheral.wrap(to) --[[@as Inventory?]]

  if not inv or not inv.list then
    backend_log.error("Connection", connection.name, "failed to run: destination peripheral is missing or is not an inventory.")
    return
  end

  local size = inv.size()

  local funcs = {}

  for i = 1, size do
    funcs[#funcs + 1] = function()
      local moved = inv.pullItems(from, i)

      items_moved = items_moved + moved  -- track the number of items moved.
    end
  end

  make_inventory_request(funcs)
end

--- Implementation of the connection runner.
---@param connection Connection The connection to run.
local function _run_connection_impl(connection)
  local from = connection.from
  local to = connection.to

  -- First, we need to check if our from node is an inventory.
  if peripheral.hasType(from, "inventory") then
    _run_connection_from_origin(connection)
  end

  -- Next check is if the first output node is any inventory.
  if peripheral.hasType(to[1], "inventory") then
    _run_connection_to_inventory(connection)
  end

  -- If we made it here, neither the origin or all destinations are inventories.
  -- Thus, fail.
  backend_log.error("Connection", connection.name, " could not be run: could not select a valid path. Consider using a buffer chest.")
end

--- Run the rules of a connection.
---@param connection Connection The connection to run the rules of.
local function run_connection(connection)
  if connection.moving then
    backend_log.debug("Running connection", connection.name)
    _run_connection_impl(connection)
    backend_log.debug("Connection", connection.name, "completed.")
  end
end

local function backend()
  local known_ids = {}
  while true do
    for _, connection in ipairs(connections) do
      local id = connection.id

      -- Only spawn a new thread if the connection has finished running.
      if known_ids[id] then
        if not thready.is_alive(known_ids[id]) then
          known_ids[id] = thready.spawn("connection_runners", function() run_connection(connection) end)
        else
          backend_log.warn("Connection", connection.name, "took too long, and was skipped on this cycle.")
        end
      else
        -- ... Or never ran yet.
        known_ids[id] = thready.spawn("connection_runners", function() run_connection(connection) end)
      end
    end

    sleep(0.05 * update_tickrate)
  end
end

local function frontend()
  while true do
    if main_menu() then
      return
    end
  end
end

local ok, err = pcall(thready.parallelAny, frontend, backend, process_inventory_requests)
print() -- put the cursor back on the screen

if not ok then
  log.fatal(err)
  ---@diagnostic disable-next-line ITS A HEKKIN STRING
  unacceptable("error", err)

  ---@fixme add test mode if error was "Terminated" and user terminates the unacceptable prompt again.
end
