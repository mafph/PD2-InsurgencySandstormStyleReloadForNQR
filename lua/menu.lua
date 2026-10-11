local cfg = rawget(_G, "NQR_MAGS")
local rcfg = rawget(_G, "NQR_MAGFILL")
local dbg = cfg.api.log

local MAGS_MENU_ID = "nqr_mags_menu"

local LOC_PATH = ModPath .. "loc/"

Hooks:Add("LocalizationManagerPostInit", "nqr_mags_loc_init", function(loc)
	local lang = BLT.Localization and BLT.Localization:get_language()
	local code = (lang and lang.language) or (BLT.save_data and BLT.save_data.language) or "en"

	loc:load_localization_file(LOC_PATH .. code .. ".txt")
	if code ~= "en" then
		loc:load_localization_file(LOC_PATH .. "en.txt", false)
	end
end)

local MAGS_ITEMS = {
	{
		type = "toggle",
		id = "nqr_mags_enabled",
		title = "nqr_mags_enabled_title",
		desc = "nqr_mags_enabled_desc",
		callback = "nqr_mags_enabled_callback",
		data_key = "enabled"
	},
	{
		type = "slider",
		id = "nqr_mags_max_extra",
		title = "nqr_mags_max_extra_title",
		desc = "nqr_mags_max_extra_desc",
		callback = "nqr_mags_max_extra_callback",
		data_key = "max_extra_mags",
		min = 0,
		max = 2,
		step = 1,
		precision = 0
	},
	{
		type = "slider",
		id = "nqr_mags_ammo_max",
		title = "nqr_mags_ammo_max_title",
		desc = "nqr_mags_ammo_max_desc",
		callback = "nqr_mags_ammo_max_callback",
		data_key = "ammo_max",
		min = 100,
		max = 200,
		step = 5,
		precision = 0,
		is_percentage = true
	},
	{
		type = "toggle",
		id = "nqr_mags_counts",
		title = "nqr_mags_counts_title",
		desc = "nqr_mags_counts_desc",
		callback = "nqr_mags_counts_callback",
		data_key = "show_mags"
	},
	{
		type = "toggle",
		id = "nqr_mags_loose",
		title = "nqr_mags_loose_title",
		desc = "nqr_mags_loose_desc",
		callback = "nqr_mags_loose_callback",
		data_key = "show_loose"
	},
	{
		type = "toggle",
		id = "nqr_mags_ammo_type",
		title = "nqr_mags_ammo_type_title",
		desc = "nqr_mags_ammo_type_desc",
		callback = "nqr_mags_ammo_type_callback",
		data_key = "show_ammo_type"
	},
	{
		type = "slider",
		id = "nqr_mags_max_boxes",
		title = "nqr_mags_max_boxes_title",
		desc = "nqr_mags_max_boxes_desc",
		callback = "nqr_mags_max_boxes_callback",
		data_key = "max_boxes",
		min = 2,
		max = 24,
		step = 1,
		precision = 0
	},
	{
		type = "toggle",
		id = "nqr_mags_more",
		title = "nqr_mags_more_title",
		desc = "nqr_mags_more_desc",
		callback = "nqr_mags_more_callback",
		data_key = "show_more"
	},
	{
		type = "slider",
		id = "nqr_mags_font",
		title = "nqr_mags_font_title",
		desc = "nqr_mags_font_desc",
		callback = "nqr_mags_font_callback",
		data_key = "font_size",
		min = 10,
		max = 28,
		step = 1,
		precision = 0
	},
	{
		type = "slider",
		id = "nqr_mags_pad_right",
		title = "nqr_mags_pad_right_title",
		desc = "nqr_mags_pad_right_desc",
		callback = "nqr_mags_pad_right_callback",
		data_key = "pad_right",
		min = -100,
		max = 300,
		step = 2,
		precision = 0
	},
	{
		type = "slider",
		id = "nqr_mags_pad_bottom",
		title = "nqr_mags_pad_bottom_title",
		desc = "nqr_mags_pad_bottom_desc",
		callback = "nqr_mags_pad_bottom_callback",
		data_key = "pad_bottom",
		min = -50,
		max = 400,
		step = 2,
		precision = 0
	},
	{
		type = "toggle",
		id = "nqr_mags_debug",
		title = "nqr_mags_debug_title",
		desc = "nqr_mags_debug_desc",
		callback = "nqr_mags_debug_callback",
		data_key = "debug"
	}
}

local FILL_ITEMS = {
	{
		type = "toggle",
		id = "nqr_magfill_enabled",
		title = "nqr_magfill_enabled_title",
		desc = "nqr_magfill_enabled_desc",
		callback = "nqr_magfill_enabled_callback",
		data_key = "enabled"
	},
	{
		type = "slider",
		id = "nqr_magfill_interval",
		title = "nqr_magfill_interval_title",
		desc = "nqr_magfill_interval_desc",
		callback = "nqr_magfill_interval_callback",
		data_key = "round_interval",
		min = 0.02,
		max = 1,
		step = 0.01,
		precision = 2
	},
	{
		type = "toggle",
		id = "nqr_magfill_sound",
		title = "nqr_magfill_sound_title",
		desc = "nqr_magfill_sound_desc",
		callback = "nqr_magfill_sound_callback",
		data_key = "sound"
	},
	{
		type = "toggle",
		id = "nqr_magfill_unblock",
		title = "nqr_magfill_unblock_title",
		desc = "nqr_magfill_unblock_desc",
		callback = "nqr_magfill_unblock_callback",
		data_key = "unblock_bag"
	},
	{
		type = "toggle",
		id = "nqr_magfill_debug",
		title = "nqr_magfill_debug_title",
		desc = "nqr_magfill_debug_desc",
		callback = "nqr_magfill_debug_callback",
		data_key = "debug"
	}
}

local LAYOUT = {}

local function layout_add(items, target)
	for i = 1, #items do
		LAYOUT[#LAYOUT + 1] = { def = items[i], target = target }
	end
end

layout_add(MAGS_ITEMS, cfg)
LAYOUT[#LAYOUT + 1] = { divider = { id = "nqr_mags_divider_1" } }
layout_add(FILL_ITEMS, rcfg)
LAYOUT[#LAYOUT + 1] = { divider = { id = "nqr_mags_divider_2" } }
LAYOUT[#LAYOUT + 1] = {
	button = {
		id = "nqr_mags_reset",
		title = "nqr_mags_reset_title",
		desc = "nqr_mags_reset_desc",
		callback = "nqr_mags_reset_callback"
	}
}

local function add_layout_item(entry, priority)
	if entry.divider then
		MenuHelper:AddDivider({
			menu_id = MAGS_MENU_ID,
			id = entry.divider.id,
			priority = priority
		})
		return
	end

	if entry.button then
		MenuHelper:AddButton({
			menu_id = MAGS_MENU_ID,
			id = entry.button.id,
			title = entry.button.title,
			desc = entry.button.desc,
			callback = entry.button.callback,
			priority = priority,
			localized = true
		})
		return
	end

	local def = entry.def
	local data = {
		id = def.id,
		title = def.title,
		desc = def.desc,
		callback = def.callback,
		value = entry.target[def.data_key],
		menu_id = MAGS_MENU_ID,
		priority = priority,
		localized = true
	}

	if def.type == "toggle" then
		MenuHelper:AddToggle(data)
	elseif def.type == "slider" then
		data.min = def.min
		data.max = def.max
		data.step = def.step
		data.show_value = true
		data.display_precision = def.precision or 2
		data.is_percentage = def.is_percentage or false
		MenuHelper:AddSlider(data)
	end
end

local function register_callback(item_def, target, save)
	local is_slider = item_def.type == "slider"
	local precision = item_def.precision or 2

	MenuCallbackHandler[item_def.callback] = function(_, item)
		local value = item:value()

		if is_slider then
			if precision == 0 then
				value = math.floor(value + 0.5)
			end
		else
			value = value == true or value == "on"
		end

		target[item_def.data_key] = value

		save()
	end
end

local function reset_all(item)
	local groups = {
		{ items = MAGS_ITEMS, target = cfg },
		{ items = FILL_ITEMS, target = rcfg }
	}

	for g = 1, #groups do
		local items = groups[g].items
		local target = groups[g].target

		for i = 1, #items do
			MenuHelper:ResetItemsToDefaultValue(item, { [items[i].id] = true }, target.defaults[items[i].data_key])
		end
	end
end

Hooks:Add("MenuManagerInitialize", "nqr_mags_menu_initialize", function()
	for i = 1, #MAGS_ITEMS do
		register_callback(MAGS_ITEMS[i], cfg, cfg.api.save)
	end

	for i = 1, #FILL_ITEMS do
		register_callback(FILL_ITEMS[i], rcfg, rcfg.api.save)
	end

	MenuCallbackHandler.nqr_mags_reset_callback = function(_, item)
		reset_all(item)
	end
end)

Hooks:Add("MenuManagerSetupCustomMenus", "nqr_mags_menu_setup", function()
	MenuHelper:NewMenu(MAGS_MENU_ID)
end)

Hooks:Add("MenuManagerPopulateCustomMenus", "nqr_mags_menu_populate", function()
	for i = 1, #LAYOUT do
		add_layout_item(LAYOUT[i], #LAYOUT - i + 1)
	end
end)

Hooks:Add("MenuManagerBuildCustomMenus", "nqr_mags_menu_build", function(_, nodes)
	local parent = nodes and (nodes.lua_mod_options_menu or nodes.blt_options or nodes.options)

	if not parent then
		dbg("no parent menu node found")
		return
	end

	nodes[MAGS_MENU_ID] = MenuHelper:BuildMenu(MAGS_MENU_ID, { area_bg = "half" })
	MenuHelper:AddMenuItem(parent, MAGS_MENU_ID, "nqr_mags_menu_title", "nqr_mags_menu_desc")
end)
