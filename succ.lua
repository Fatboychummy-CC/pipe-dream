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
---@cast connections Connection[]

---@class Connection
---@field name string The name of the connection.
---@field from string The peripheral the connection is from.
---@field to string[] The peripherals the connection is to.
---@field filter_list string[] The blacklist or whitelist of items.
---@field filter_mode "whitelist"|"blacklist" The item filter mode of the connection.
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

  PrimeUI.clear()

  -- Draw info box.
  if _type == "error" then
    info_box(win, "Error", ("An error occurred.\n%s\n\nPress enter to continue."):format(reason), 10, colors.red)
  elseif _type == "input" then
    info_box(win, "Input Error", ("The last user input was unacceptable.\n%s\n\nPress enter to continue."):format(reason),
      4, colors.red)
  else
    info_box(win, "Unknown Error", ("An unknown error occurred.\n%s\n\nPress enter to continue."):format(reason), 10,
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
        elseif result == view_items then
          selected = "view"
          item_selected = 1
          item_scroll = 1
        elseif result == remove_item then
          selected = "remove"
          item_selected = 1
          item_scroll = 1
        elseif result == toggle_mode then
          connection_data.filter_mode = connection_data.filter_mode == "whitelist" and "blacklist" or "whitelist"
        elseif result == go_back then
          save()
          return
        end
      elseif event == "select-item" then
        if selected == "remove" then
          if items[selection] and confirmation_menu("Remove item", "Are you sure you want to remove item " .. tostring(items[selection]) .. "?") then
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
  connection_data = connection_data or {
    name = "",
    from = "",
    to = {},
    filter_list = {},
    filter_mode = "blacklist",
    mode = "1234",
    moving = false, -- New connections will be disabled by default
  }
  local cached_peripheral_list = get_peripherals()
  local expanded_section = 1

  local win = window.create(term.current(), 1, 1, term.getSize())
  local width, height = win.getSize()

  local periphs_with_nicknames = {}             -- predeclare so section_info can access it.
  local destination_periphs_with_nicknames = {} -- predeclare so section_info can access it.


  local section_infos = {
    {
      name = (
        (connection_data.name == "") and "Name" or
        "Name - " .. connection_data.name
      ),
      info =
      "Enter the name of this connection\nPress enter to save section data, tab to go to the next step, and shift+tab to go back.",
      size = 1,
      object = "input_box",
      args = {
        default = connection_data.name,
        action = "set-name",
      },
      increment_on_enter = true
    },
    {
      name = (
        (connection_data.from == "") and "Origin" or
        "Origin - " .. (nicknames[connection_data.from] or connection_data.from)
      ),
      info = "Select the peripheral this connection is from.",
      size = 7,
      object = "selection_box",
      args = {
        action = "select-origin",
        items = periphs_with_nicknames,
      },
      increment_on_enter = true
    },
    {
      name = (
        (#connection_data.to == 0) and "Destinations" or
        "Destinations - " .. (#connection_data.to) .. " selected"
      ),
      info = "Select the peripherals this connection is to.",
      size = 7,
      object = "selection_box",
      args = {
        action = "select-destination",
        items = destination_periphs_with_nicknames,
      },
      increment_on_enter = false
    },
    {
      name = (
        (connection_data.filter_mode == "") and "Filter Mode" or
        "Filter Mode - " .. connection_data.filter_mode
      ),
      info = "Select the filter mode of the connection. The list starts empty, and you can edit it in another menu.",
      size = 2,
      object = "selection_box",
      args = {
        action = "select-filter_mode",
        items = { "Blacklist", "Whitelist" },
      },
      increment_on_enter = true
    },
    {
      name = (
        (connection_data.mode == "") and "Mode" or
        "Mode - " .. connection_data.mode
      ),
      info = "Select the mode of the connection.",
      size = 2,
      object = "selection_box",
      args = {
        action = "select-mode",
        items = { "Fill 1, then 2, then 3, then 4", "Split evenly" },
      },
      increment_on_enter = true
    }
  }

  local function save_connection()
    local ok, err = verify_connection(connection_data)
    if ok then
      table.insert(connections, connection_data)
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

      for j = 1, #connection_data.to do
        if connection_data.to[j] == v then
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
    info_box(win, "Add Connection", section_info.info, 3)

    local y = 8

    -- Draw the sections
    for i = 1, #section_infos do
      local section = section_infos[i]
      local expanded = i == expanded_section
      local color = expanded and colors.purple or colors.gray

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

          outlined_selection_box(win, 3, y, width - 4, section.size, args.items, args.action, nil, colors.white,
            colors.black, args.selection or 1, args.scroll or 1)
        else
          error("Invalid object type '" .. tostring(object) .. "' at index " .. i)
        end

        -- Draw the text box
        PrimeUI.textBox(win, 3, y - 1, #section.name + 2, 1, ' ' .. section.name .. ' ', color, colors.black)
      else
        -- Draw the border box and text box
        PrimeUI.borderBox(win, 3, y, width - 4, -1, color, colors.black)
        PrimeUI.textBox(win, 3, y - 1, #section.name + 2, 1, ' ' .. section.name .. ' ', color, colors.black)
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
          expanded_section = expanded_section - 1
          if expanded_section < 1 then
            if confirm_exit_no_save() then
              return
            end
            expanded_section = 1
          end
        else
          expanded_section = expanded_section + 1
          if expanded_section > #section_infos then
            if save_connection() then
              return
            end

            expanded_section = #section_infos
          end
        end
      end
    elseif object == "selectionBox" then
      if event == "select-origin" then
        connection_data.from = cached_peripheral_list[selection]
        section_info.name = "Origin - " .. result
      elseif event == "select-destination" then
        -- Insert the peripheral into the list of destinations.
        -- Unless it is already in the list, in which case remove it.
        local found = false

        for i = 1, #connection_data.to do
          if connection_data.to[i] == cached_peripheral_list[selection] then
            table.remove(connection_data.to, i)
            found = true
            break
          end
        end

        section_info.args.selection = selection
        section_info.args.scroll = scroll_result

        if not found then
          table.insert(connection_data.to, cached_peripheral_list[selection])
        end

        if #connection_data.to == 0 then
          section_info.name = "Destinations"
        else
          section_info.name = "Destinations - " .. (#connection_data.to) .. " selected"
        end
      elseif event == "select-filter_mode" then
        connection_data.filter_mode = selection == 1 and "blacklist" or "whitelist"

        section_info.name = "Filter Mode - " .. connection_data.filter_mode
      elseif event == "select-mode" then
        connection_data.mode = selection == 1 and "1234" or "split"

        section_info.name = "Mode - " .. connection_data.mode
      end

      if section_info.increment_on_enter then
        expanded_section = expanded_section + 1
      end
    elseif object == "inputBox" then
      if event == "set-name" then
        connection_data.name = result
        section_info.args.default = result
        section_info.name = "Name - " .. result
      end

      if section_info.increment_on_enter then
        expanded_section = expanded_section + 1
      end
    end
  end
end

--- Menu to add a new connection.
local function connections_add_menu()
  parallel.waitForAny(key_listener, _connections_edit_impl)
end

--- A quick menu to select a connection, with a custom header.
---@param title string The title of the menu.
---@param body string The body of the menu.
---@return Connection? connection The connection selected, or nil if none was selected.
local function select_connection(title, body)
  local win = window.create(term.current(), 1, 1, term.getSize())
  local width, height = win.getSize()

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
        return connections[selection]
      end
    elseif object == "keyAction" and event == "exit" then
      return
    end
  end
end

--- Edit a connection
local function connections_edit_menu()
  local connection = select_connection("Edit Connection", "Press enter to edit a connection.\nPress backspace to exit.")

  if connection then
    parallel.waitForAny(key_listener, function()
      _connections_edit_impl(connection)
    end)
  end
end

--- Edit whitelist/blacklist of a connection
local function connections_filter_menu()
  local connection = select_connection("Edit Connection Filter", "Press enter to edit a connection's filter.\nPress backspace to exit.")

  if connection then
    parallel.waitForAny(key_listener, function()
      _connections_filter_edit_impl(connection)
    end)
  end
end

local function connections_remove_menu()
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
        return
      end

      save()
    elseif object == "keyAction" and event == "exit" then
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
    local object, event, selected, _selection, _scroll = PrimeUI.run()

    if object == "keyAction" then
      if event == "exit" then
        run = false
      end
    elseif object == "selectionBox" then
      if event == "edit" then
        -- Edit the nickname of the selected peripheral.
        editing = true
      elseif event == "change" then
        index = _selection
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
  local update_rate = "Change Update Rate"
  local nickname = "Change Peripheral Nicknames"
  local toggle = "Toggle Running"
  local exit = "Exit"

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
  info_box(win, "Main Menu", description, 7)

  -- Create the selection box.
  outlined_selection_box(win, 4, 14, width - 6, height - 14, {
    update_connections,
    update_rate,
    nickname,
    toggle,
    exit
  }, "selection", nil, colors.white, colors.black, 1, 1)

  local object, event, selected = PrimeUI.run()

  if selected == update_connections then
    connections_main_menu()
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
