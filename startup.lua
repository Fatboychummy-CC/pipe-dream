local PrimeUI = require("primeui")

local file_helper = require "file_helper"
local data_dir = file_helper:instanced("data")

local LISTS_FILE = "lists.txt"
local ITEMS_MOVED_FILE = "items_moved.txt"
local CONNECTIONS_FILE = "connections.txt"
local UPDATE_TICKRATE_FILE = "update_tickrate.txt"

local lists = data_dir:unserialize(LISTS_FILE, {})
local items_moved = data_dir:unserialize(ITEMS_MOVED_FILE, 0)
local connections = data_dir:unserialize(CONNECTIONS_FILE, {})
local update_tickrate = data_dir:unserialize(UPDATE_TICKRATE_FILE, 10)

local function save()
  data_dir:serialize(LISTS_FILE, lists)
  data_dir:serialize(ITEMS_MOVED_FILE, items_moved)
  data_dir:serialize(CONNECTIONS_FILE, connections)
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

local function info_box(win, title, desc)
  local width, height = term.getSize()
  local max_width, max_height = width - 4, height - 4 - 10
  local info_height = height - max_height - 6

  -- Info box with border
  PrimeUI.borderBox(win, 3, 3, max_width, info_height)
  PrimeUI.textBox(win, 3, 3, max_width, 1, title, colors.purple)
  PrimeUI.textBox(win, 3, 4, max_width, info_height - 1, desc, colors.lightGray)
end

--- Create a menu given a list of options.
---@param title string The title of the menu
---@param desc string The description of the menu
---@param ... string The list of options to display
local function quick_menu(title, desc, ...)
  local options = { ... }

  local win = window.create(term.current(), 1, 1, term.getSize())

  PrimeUI.clear()

  local width, height = term.getSize()
  local max_width, max_height = width - 4, height - 4 - 10
  local info_height = height - max_height - 6

  -- Selection box with border
  PrimeUI.borderBox(win, 3, 3 + 10, max_width, max_height)
  local sel_name = "selection"
  PrimeUI.selectionBox(
    win,
    3, 3 + 10,
    max_width + 1, max_height,
    options,
    sel_name
  )

  -- Info box with border
  info_box(win, title, desc)

  local event, action, selected = PrimeUI.run()

  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColor(colors.white)
  term.setBackgroundColor(colors.black)

  print(event, action, selected)

  if action == sel_name then
    return selected
  end
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
    # > peripheral_1         # # > 1. peripheral_2       # -- Currently selected node will not appear in output list
    #   peripheral_2         # #   2. peripheral_3       #
    ########################## ###########################
  ]]

  -- Outline the information box.
  local win = window.create(term.current(), 1, 1, term.getSize())

  PrimeUI.clear()

  local width, height = term.getSize()
  local max_width, max_height = width - 4, height - 4 - 10
  local info_height = height - max_height - 6

  -- Info box
  info_box(win, "Connections",
    "Press tab to alternate between ins and outs.\nPress enter to toggle a connection.\nPress space to toggle connection mode.\nPress backspace to exit.\nNote: Applies changes and saves upon exit.\n\nConnection mode: Fill 1 then fill 2 ...")

  PrimeUI.run()
end

local function list_menu()

end

local function tickrate_menu()

end


--- Main menu
local function main_menu()
  local update_connections = "Update Connections"
  local whitelist_blacklist = "Change Connection Whitelists/Blacklists"
  local update_rate = "Change Update Rate"
  local exit = "Exit"

  local description = ("Select an option from the list below.\n\nTotal items moved: %d\nTotal connections: %d\n\nUpdate rate: Every %d tick%s")
      :format(
        items_moved,
        count_table(connections),
        update_tickrate,
        update_tickrate == 1 and "" or "s"
      )

  local selected = quick_menu(
    "Main Menu",
    description,
    update_connections,
    whitelist_blacklist,
    update_rate,
    exit
  )

  if selected == update_connections then
    print("Update connections uwu")
    connections_menu()
  elseif selected == whitelist_blacklist then
    print("Change whitelist/blacklist uwu")
    list_menu()
  elseif selected == update_rate then
    print("Change update rate uwu")
    tickrate_menu()
  elseif selected == exit then
    print("Exiting...")
    return true
  end

  save()
end

while true do
  if main_menu() then
    break
  end
end
