dynamic_forceload = {} -- container for globals

-- internationalization boilerplate
local MP = minetest.get_modpath(minetest.get_current_modname())
local S, NS = dofile(MP.."/intllib.lua")

local worldpath = minetest.get_worldpath()
local forceload_filename = worldpath.."/dynamic_forceload.json"

-- in-memory copy of data stored in dynamic_forceload.json
local forceload_data = {}

local hard_limit = tonumber(minetest.settings:get("max_forceloaded_blocks")) or 16
local rotation_time = tonumber(minetest.setting_get("dynamic_forceload_rotation_time")) or 60
local active_limit = math.min(tonumber(minetest.setting_get("dynamic_forceload_active_limit")) or 8, hard_limit)

local player_current_index = {}
local latest_player
local active_positions = {}

minetest.register_privilege("forceload", { description = "Allows players to use forceload block anchors", give_to_singleplayer = false})

-- Chat command

local get_forceloads_for = function(name)
	local positions = forceload_data[name]
	local output
	if positions then
		output = name .. "'s forceload anchors are at:"
		for _, pos in ipairs(positions) do
			output = output .. " " .. minetest.pos_to_string(pos)
		end
	else
		output = name .. " has no active forceload anchors registered."
	end
	return output
end

minetest.register_chatcommand("forceloads", {
    params = "[<name>|all]", -- Short parameter description
    description = "Show your forceload anchor positions, or another player's if you have server privilege.",
    func = function(name, param)
		if param == nil or param == "" then
			return true, get_forceloads_for(name)
		elseif minetest.check_player_privs(name, {server = true}) then
			if param ~= "all" then
				return true, get_forceloads_for(param)
			else
				local output = ""
				for player, _ in pairs(forceload_data) do
					output = output .. "\n" .. get_forceloads_for(player)
				end
				return true, output
			end
		else
			return false, "You need the server privilege to view other players' forceload anchor positions."
		end
		-- Returns boolean success and text output.
	end,                                      
})

-- Json storage

local save_data = function()
	local file = io.open(forceload_filename, "w")
	if file then
		file:write(minetest.serialize(forceload_data))
		file:close()
	end
end

local read_data = function()
	local file = io.open(forceload_filename, "r")
	if file then
		forceload_data = minetest.deserialize(file:read("*all"))
		file:close()
	else
		forceload_data = nil
	end
	if forceload_data == nil then
		forceload_data = {}
		save_data()
	end
end

-- Adds the anchor pos to the forceload_data.
-- If usurp_active is true and the player already has a forceloaded
-- position active, then pos will replace that position immediately.
-- Otherwise it gets added to the active list via an eventual rotate_active call.

-- If the node at pos has on_forceload_block defined it will be called
-- with the parameters (pos, player_name) when it is eventually forceloaded.
-- If it has on_forceload_free_block defined it will be called with the parameter
-- (pos) when the block's forceload ends.

dynamic_forceload.add_anchor = function(pos, player_name, usurp_active)
	if forceload_data[player_name] == nil then
		forceload_data[player_name] = {}
	end
	local player_data = forceload_data[player_name]
	table.insert(player_data, pos)
	save_data()
	
	if usurp_active then
		--reverse iterate through active positions and replace the first
		--one that belongs to the player
		for i = #active_positions, 1, -1 do
			local active_pos = active_positions[i]
			for _, player_pos in ipairs(player_data) do
				if vector.equals(active_pos, player_pos) then
					active_positions[i] = pos
					return
				end
			end
		end
	end	
end

local rotate_active

dynamic_forceload.remove_anchor = function(pos)
	minetest.forceload_free_block(pos, true) -- always do this just to be on the safe side
	
	-- remove from forceload_data
	for player, pos_list in pairs(forceload_data) do
		for i, anchor_pos in ipairs(pos_list) do
			if vector.equals(pos, anchor_pos) then
				table.remove(pos_list, i)
				if table.getn(pos_list) == 0 then
					forceload_data[player] = nil
				end
				save_data()
				
				-- If the position is currently forceloaded, remove it and trigger an update
				for i, active_pos in ipairs(active_positions) do
					if vector.equals(pos, active_pos) then
						table.remove(active_pos, i)
						rotate_active()						
						break
					end
				end
	
				return
			end
		end
	end
end

local call_on_forceload_block
call_on_forceload_block = function(pos, player_name)
	local nodename = minetest.get_node(pos).name
	--minetest.debug("activating node " .. nodename)
	if nodename == "ignore" then
		--block hasn't loaded yet, try again in a second.
		minetest.after(1, call_on_forceload_block, pos, player_name)	
	else
		local activating_def = minetest.registered_nodes[nodename]
		if activating_def.on_forceload_block then
			activating_def.on_forceload_block(pos, player_name)
		end
	end
end

minetest.register_node("dynamic_forceload:anchor_inert",{
	description = S("Inert Time Anchor"),
	_doc_items_longdesc = S("A magical block that can bend time itself, causing the world to continue running in its vicinity even when the player who placed it is not nearby or online. This one seems to be inactive, however."),
    _doc_items_usagehelp = S("Place the block to cause the local surroundings to continue running. Remove the block to restore the flow of time to normal."),
	walkable = false,
	drop = "dynamic_forceload:anchor",
	tiles = {"dynamic_forceload_anchor_top.png", "dynamic_forceload_anchor_top.png", "dynamic_forceload_anchor.png"},
	groups = {cracky = 3, oddly_breakable_by_hand = 2, not_in_creative_inventory = 1},
})

minetest.register_node("dynamic_forceload:anchor",{
	description = S("Time Anchor"),
	_doc_items_longdesc = S("A magical block that can bend time itself, causing the world to continue running in its vicinity even when the player who placed it is not nearby or online."),
    _doc_items_usagehelp = S("Place the block to cause the local surroundings to continue running. Remove the block to restore the flow of time to normal."),
	walkable = false,
	tiles = {"dynamic_forceload_anchor_top.png", "dynamic_forceload_anchor_top.png", {name="dynamic_forceload_anchor_anim.png", animation={
        type = "vertical_frames",
        aspect_w = 16,
        aspect_h = 16,
        length = 2.0,
    }}},
	groups = {cracky = 3, oddly_breakable_by_hand = 2},
	after_destruct = function(pos)
		dynamic_forceload.remove_anchor(pos)
		save_data()
	end,
	after_place_node = function(pos, placer)
		if not minetest.check_player_privs(placer:get_player_name(),
				{forceload = true}) then
			minetest.chat_send_player(placer:get_player_name(), S("The forceload privilege is required to register this location for continued timeflow."))
			minetest.swap_node(pos, {name="dynamic_forceload:anchor_inert"})
		else
			dynamic_forceload.add_anchor(pos, placer:get_player_name())
		end
--		minetest.get_node_timer(pos):start(1)
	end,
	
--	on_forceload_block = function(pos, name)
--		minetest.debug("On forceload block called at " .. minetest.pos_to_string(pos) .. " on behalf of player " .. name)
--		minetest.get_node_timer(pos):start(1)
--	end,
--	on_forceload_free_block = function(pos)
--		minetest.debug("On forceload free block called at " .. minetest.pos_to_string(pos))
--		minetest.get_node_timer(pos):stop()
--	end,
--	on_timer = function(pos, elapsed)
--		minetest.chat_send_all("dynamic_forceload at " .. minetest.pos_to_string(pos) .. " ticked.")
--		minetest.get_node_timer(pos):start(1)
--	end,
})

read_data()

rotate_active = function()
	--minetest.debug("rotate_active called")
	--minetest.debug(dump(forceload_data))

	-- if there are no positions to load, do nothing.
	if next(forceload_data) == nil then return end
	
	-- if the latest player's had his last position removed, we've lost our bearings in the player queue. Reset.
	if latest_player and forceload_data[latest_player] == nil then latest_player = nil end
	
	local next_player = next(forceload_data, latest_player)
	if next_player == nil then
		next_player = next(forceload_data) -- we've run off the end of the players, go back to the beginning
	end
	latest_player = next_player
	
	local next_player_positions = forceload_data[next_player]
	if player_current_index[next_player] == nil or player_current_index[next_player] > table.getn(next_player_positions) - 1 then
		-- if we've gone off the end of the list of positions, or this player has never gone before, reset to beginning
		player_current_index[next_player] = 0
	end
	player_current_index[next_player] = player_current_index[next_player] + 1
	
	local new_pos = next_player_positions[player_current_index[next_player]]
	
	for _, active_pos in ipairs(active_positions) do
		if vector.equals(new_pos, active_pos) then
			--minetest.debug("position already active: " .. minetest.pos_to_string(new_pos))
			return -- the position is already active, do nothing
		end	
	end
	
	-- insert the new pos at the end and forceload it
	minetest.log("info", "[dynamic_forceload] " .. next_player .. " gets to run the block at " .. minetest.pos_to_string(new_pos))
	table.insert(active_positions, new_pos)
	--minetest.debug(dump(active_positions))
	
	-- if we're over the limit, remove the oldest active position
	if table.getn(active_positions) > active_limit then
		local deactivating_pos = active_positions[1]
		local deactivating_def = minetest.registered_nodes[minetest.get_node(deactivating_pos).name]
		if deactivating_def.on_forceload_free_block then
			deactivating_def.on_forceload_free_block(deactivating_pos)
		end
		
		minetest.forceload_free_block(deactivating_pos, true)
		--minetest.debug("Over active limit, removing " .. minetest.pos_to_string(active_positions[1]))
		table.remove(active_positions, 1)
	end	
	
	-- forceload *after* free_block is called in case these nodes are in the same block or in case we're at the hard limit
	if not minetest.forceload_block(new_pos, true) then
		dynamic_forceload.remove_anchor(new_pos)
		minetest.log("error", "[dynamic_forceload] Unable to forceload block at position " .. minetest.pos_to_string(new_pos) .. ", anchor removed from anchor list.")
	else
		minetest.after(1, call_on_forceload_block, new_pos, next_player)
	end
end

local timer = rotation_time -- start at rotation time so that rotate_active() is called immediately to get things started.
minetest.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer > rotation_time then
		timer = timer - rotation_time
		rotate_active()
	end
end)

if minetest.get_modpath("default") then
	minetest.register_craft({
		output = "dynamic_forceload:anchor",
		recipe = {
			{"default:mese_crystal_fragment", "default:mese_crystal_fragment", "default:mese_crystal_fragment"},
			{"default:glass", "default:mese_crystal", "default:glass"},
			{"default:glass", "default:glass", "default:glass"}
		}
	})
end
