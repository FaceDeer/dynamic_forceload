dynamic_forceload = {} -- container for globals

local modpath = minetest.get_modpath(minetest.get_current_modname())
dofile(modpath.."/nodes.lua")

local worldpath = minetest.get_worldpath()
local forceload_filename = worldpath.."/dynamic_forceload.json"

-- in-memory copy of data stored in dynamic_forceload.json
local forceload_data = {}
forceload_data.players = {}

local BLOCKSIZE = core.MAP_BLOCKSIZE
local function get_blockpos(pos)
	return {
		x = math.floor(pos.x/BLOCKSIZE),
		y = math.floor(pos.y/BLOCKSIZE),
		z = math.floor(pos.z/BLOCKSIZE)}
end
local active_block_range = tonumber(minetest.settings:get("active_block_range")) or 3
--local function overlapping_activation(pos1, pos2)
--	local blockpos1 = get_blockpos(pos1)
--	local blockpos2 = get_blockpos(pos2)
--	return vector.distance(blockpos1, blockpos2) < BLOCKSIZE * 2 * active_block_range
--end

local hard_limit = tonumber(minetest.settings:get("max_forceloaded_blocks")) or 16
local rotation_time = tonumber(minetest.setting_get("dynamic_forceload_rotation_time")) or 60
local active_limit = math.min(tonumber(minetest.setting_get("dynamic_forceload_active_limit")) or 8, hard_limit)

local player_current_index = {}
local latest_player
local active_positions = {}

-- predeclare some local functions
local call_on_forceload_block
local rotate_active

minetest.register_privilege("forceload", { description = "Allows players to use forceload block anchors", give_to_singleplayer = false})

-- Chat command

local get_forceloads_for = function(name)
	local positions = forceload_data.players[name]
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
				for player, _ in pairs(forceload_data.players) do
					output = output .. "\n" .. get_forceloads_for(player)
				end
				output = output .. "\n\nCurrently active:\n"
				for _, active in ipairs(active_positions) do
					output = output .. " " .. minetest.pos_to_string(active)
				end
				return true, output
			end
		else
			return false, "You need the server privilege to view other players' forceload anchor positions."
		end
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
		forceload_data.version = 1 -- Only update this when making compatibility-breaking changes to the forceload data.
		forceload_data.players = {}
		save_data()
	end
end

-- use these methods to ensure callbacks are triggered
local forceload_free_block = function(deactivating_pos)
	local deactivating_def = minetest.registered_nodes[minetest.get_node(deactivating_pos).name]
	if deactivating_def.on_forceload_free_block then
		deactivating_def.on_forceload_free_block(deactivating_pos)
	end
	minetest.debug("forcload_free_block at " .. minetest.pos_to_string(deactivating_pos))
	minetest.forceload_free_block(deactivating_pos, true)
end

call_on_forceload_block = function(pos, player_name, count)
	local nodename = minetest.get_node(pos).name
	if nodename == "ignore" then
		--block hasn't loaded yet, try again in a second.
		if count < 60 then
			minetest.after(1, call_on_forceload_block, pos, player_name, count+1)
		else
			minetest.log("error", "[dynamic_forceload] call_on_forceload_block "..
				"made 60 attempts to trigger on_forceload_block callback on node " ..
				" at " .. minetest.pos_to_string(pos) .. " on behalf of " ..
				player_name .. " without success, giving up.")
		end
	else
		local activating_def = minetest.registered_nodes[nodename]
		if activating_def.on_forceload_block then
			activating_def.on_forceload_block(pos, player_name)
		end
	end
end

local forceload_block = function(new_pos, next_player)
	if not minetest.forceload_block(new_pos, true) then
		minetest.log("error", "[dynamic_forceload] Unable to forceload block at position " ..
			minetest.pos_to_string(new_pos) .. " on behalf of player " .. next_player ..
			" - possibly exceeded hard forceload limit?")
	else
		minetest.debug("forceload_block at " .. minetest.pos_to_string(new_pos))
		call_on_forceload_block(new_pos, next_player, 0)
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
	if forceload_data.players[player_name] == nil then
		forceload_data.players[player_name] = {}
	end
	local player_data = forceload_data.players[player_name]
	local already_added = false
	for _, already_pos in ipairs(player_data) do
		if vector.equals(pos, already_pos) then
			already_added = true
			break
		end
	end
	if not already_added then
		table.insert(player_data, pos)
		save_data()
	end
	
	if usurp_active then
		--reverse iterate through active positions and replace the first
		--one that belongs to the player.
		for i = #active_positions, 1, -1 do
			local active_pos = active_positions[i]
			for pi, player_pos in ipairs(player_data) do
				if vector.equals(active_pos, player_pos) then
					local old_pos = active_positions[i]
					minetest.debug("usurping " .. minetest.pos_to_string(old_pos) .. " with " .. minetest.pos_to_string(pos))
					active_positions[i] = pos
					-- update the forceload if the usurped position is in a new map block
					if not vector.equals(get_blockpos(old_pos), get_blockpos(pos)) then
						forceload_free_block(old_pos)
						forceload_block(pos, player_name)
					end
					return
				end
			end
		end
	end	
end

local move_anchor_in_pos_list = function(old_pos, new_pos, pos_list, player)
	for i, anchor_pos in ipairs(pos_list) do
		if vector.equals(anchor_pos, old_pos) then
			pos_list[i] = new_pos
			for j, active_pos in ipairs(active_positions) do
				if active_pos == anchor_pos then
					active_positions[j] = new_pos
					-- update the forceload if the new position is in a new map block
					if not vector.equals(get_blockpos(old_pos), get_blockpos(new_pos)) then
						forceload_free_block(old_pos)
						forceload_block(new_pos, player)
					end
				end
			end
			return true
		end
	end
end

-- If player_name_check is not nil, will check to ensure that the player owns the
-- forceload anchor before moving it.
dynamic_forceload.move_anchor = function(old_pos, new_pos, player_name_check)
	if player_name_check == nil then
		for player, pos_list in pairs(forceload_data.players) do
			if move_anchor_in_pos_list(old_pos, new_pos, pos_list, player) then
				return true
			end
		end
	else
		local pos_list = forceload_data.players[player_name_check]
		if pos_list ~= nil then
			if move_anchor_in_pos_list(old_pos, new_pos, pos_list, player_name_check) then
				return true
			end
		end
	end
	minetest.log("action", "[dynamic_forceload] unable to move forceload " ..
		minetest.pos_to_string(old_pos) .. " to " .. minetest.pos_to_string(new_pos))
	return false
end

dynamic_forceload.remove_anchor = function(pos)

	local active_index = nil
	for i, active_pos in ipairs(active_positions) do
		if vector.equals(pos, active_pos) then
			active_index = i
		end
	end
	
	-- remove from forceload_data
	for player, pos_list in pairs(forceload_data.players) do
		for i, anchor_pos in ipairs(pos_list) do
			if vector.equals(pos, anchor_pos) then
				table.remove(pos_list, i)
				if table.getn(pos_list) == 0 then
					forceload_data.players[player] = nil
				end
				save_data()
				
				-- If the position is currently forceloaded, remove it and trigger an update
				if active_index ~= nil then
					forceload_free_block(pos)
					table.remove(active_positions, active_index)					
					rotate_active()
					break
				end
	
				return
			end
		end
	end
end

rotate_active = function()
	--minetest.debug("rotate_active called")

	-- if there are no positions to load, do nothing.
	if next(forceload_data.players) == nil then return end
	
	-- if the latest player's had his last position removed, we've lost our bearings in the player queue. Reset.
	if latest_player and forceload_data.players[latest_player] == nil then latest_player = nil end
	
	local next_player = next(forceload_data.players, latest_player)
	if next_player == nil then
		next_player = next(forceload_data.players) -- we've run off the end of the players, go back to the beginning
	end
	latest_player = next_player
	
	local next_player_positions = forceload_data.players[next_player]
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
		forceload_free_block(deactivating_pos)
		--minetest.debug("Over active limit, removing " .. minetest.pos_to_string(active_positions[1]))
		table.remove(active_positions, 1)
	end	
	save_data()
	
	-- forceload *after* free_block is called in case these nodes are in the same block or in case we're at the hard limit
	forceload_block(new_pos, next_player)
end

read_data()

-- After initializing immediately fill the queue with an initial set of forceloads
minetest.after(1, function()
	local count = 0
	for _, position_list in pairs(forceload_data.players) do
		count = count + table.getn(position_list)
		if count > active_limit then
			count = active_limit
			break
		end
	end
	while count > 0 do
		rotate_active()
		count = count - 1
	end
end)

local timer = 0
minetest.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer > rotation_time then
		timer = timer - rotation_time
		rotate_active()
	end
end)