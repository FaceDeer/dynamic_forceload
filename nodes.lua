-- internationalization boilerplate
local MP = minetest.get_modpath(minetest.get_current_modname())
local S, NS = dofile(MP.."/intllib.lua")

local BLOCKSIZE = core.MAP_BLOCKSIZE
local active_block_range = tonumber(minetest.settings:get("active_block_range")) or 3

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
	_doc_items_longdesc = S("A magical block that can bend time itself, causing the world to continue running in its vicinity even when the player who placed it is not nearby or online. The effect has a range of approximately @1 meters.", BLOCKSIZE*active_block_range),
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
