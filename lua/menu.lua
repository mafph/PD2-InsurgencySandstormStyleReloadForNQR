-- Menues: Einstellungen fuer Magazine und Nachfuellung.

local cfg = rawget(_G, "NQR_MAGS")
local rcfg = rawget(_G, "NQR_MAGFILL")
local dbg = cfg.api.log

local MAGS_MENU_ID = "nqr_mags_menu"
local MAGS_MENU_TITLE = "NQR Magazines"
local MAGS_MENU_DESC = "Magazin- und Nachlade-Einstellungen"

local FILL_MENU_ID = "nqr_magfill_menu"
local FILL_MENU_TITLE = "NQR Magazine Refill"
local FILL_MENU_DESC = "Magazin-Nachfuellung"

local MAGS_ITEMS = {
	{
		type = "toggle",
		id = "nqr_mags_enabled",
		title = "NQR Magazines: aktiviert",
		desc = "Magazine als eigene Objekte mit Sandstorm-HUD.",
		callback = "nqr_mags_enabled_callback",
		data_key = "enabled"
	},
	{
		type = "slider",
		id = "nqr_mags_max_extra",
		title = "NQR Magazines: zusaetzliche Magazine",
		desc = "Wie viele Magazine ueber die NQR-Magazinanzahl hinaus gefuellt werden (0-2).",
		callback = "nqr_mags_max_extra_callback",
		data_key = "max_extra_mags",
		min = 0,
		max = 2,
		step = 1,
		precision = 0
	},
	{
		type = "toggle",
		id = "nqr_mags_counts",
		title = "NQR Magazines: Anzahl und lose Munition",
		desc = "Zeigt Magazinanzahl, lose Munition und das als naechstes geladene Magazin.",
		callback = "nqr_mags_counts_callback",
		data_key = "show_counts"
	},
	{
		type = "toggle",
		id = "nqr_mags_ammo_type",
		title = "NQR Magazines: Munitionstyp anzeigen",
		desc = "Zeigt neben der Munition den Kaliber an.",
		callback = "nqr_mags_ammo_type_callback",
		data_key = "show_ammo_type"
	},
	{
		type = "slider",
		id = "nqr_mags_max_boxes",
		title = "NQR Magazines: max. Kaesten",
		desc = "Wie viele Magazine im HUD gezeigt werden.",
		callback = "nqr_mags_max_boxes_callback",
		data_key = "max_boxes",
		min = 2,
		max = 24,
		step = 1,
		precision = 0
	},
	{
		type = "slider",
		id = "nqr_mags_font",
		title = "NQR Magazines: Schriftgroesse",
		desc = "Groesse der HUD-Schrift.",
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
		title = "NQR Magazines: Abstand rechts",
		desc = "Abstand des HUDs zum rechten Bildschirmrand.",
		callback = "nqr_mags_pad_right_callback",
		data_key = "pad_right",
		min = 0,
		max = 300,
		step = 2,
		precision = 0
	},
	{
		type = "slider",
		id = "nqr_mags_pad_bottom",
		title = "NQR Magazines: Abstand unten",
		desc = "Abstand des HUDs zum unteren Bildschirmrand.",
		callback = "nqr_mags_pad_bottom_callback",
		data_key = "pad_bottom",
		min = 0,
		max = 400,
		step = 2,
		precision = 0
	},
	{
		type = "toggle",
		id = "nqr_mags_debug",
		title = "NQR Magazines: Debug",
		desc = "Schreibt Details ins Log.",
		callback = "nqr_mags_debug_callback",
		data_key = "debug"
	}
}

local FILL_ITEMS = {
	{
		type = "toggle",
		id = "nqr_magfill_enabled",
		title = "NQR Refill: aktiviert",
		desc = "Ammo-Bag fuellt lose Munition, die Magazine werden nacheinander befuellt.",
		callback = "nqr_magfill_enabled_callback",
		data_key = "enabled"
	},
	{
		type = "slider",
		id = "nqr_magfill_interval",
		title = "NQR Refill: Sekunden pro Magazin",
		desc = "Pause zwischen zwei Magazinen waehrend der Nachfuell-Animation.",
		callback = "nqr_magfill_interval_callback",
		data_key = "mag_interval",
		min = 0.1,
		max = 3,
		step = 0.05,
		precision = 2
	},
	{
		type = "toggle",
		id = "nqr_magfill_sound",
		title = "NQR Refill: Sound",
		desc = "Spielt beim Fuellen eines Magazins einen Sound ab.",
		callback = "nqr_magfill_sound_callback",
		data_key = "sound"
	},
	{
		type = "toggle",
		id = "nqr_magfill_unblock",
		title = "NQR Refill: Bag auch bei vollem Clip nutzbar",
		desc = "Ammo-Bag bleibt benutzbar, wenn nur noch Magazine gefuellt werden muessen.",
		callback = "nqr_magfill_unblock_callback",
		data_key = "unblock_bag"
	},
	{
		type = "toggle",
		id = "nqr_magfill_debug",
		title = "NQR Refill: Debug",
		desc = "Schreibt Details ins Log.",
		callback = "nqr_magfill_debug_callback",
		data_key = "debug"
	}
}

local function add_dynamic_menu_item(menu_id, item_def, priority, target)
	local data = {
		id = item_def.id,
		title = item_def.title,
		desc = item_def.desc,
		callback = item_def.callback,
		value = target[item_def.data_key],
		menu_id = menu_id,
		priority = priority,
		localized = false
	}

	if item_def.type == "toggle" then
		MenuHelper:AddToggle(data)
	elseif item_def.type == "slider" then
		data.min = item_def.min
		data.max = item_def.max
		data.step = item_def.step
		data.show_value = true
		data.display_precision = item_def.precision or 2
		MenuHelper:AddSlider(data)
	end
end

local function register_callback(item_def, target, save)
	local is_slider = item_def.type == "slider"
	local precision = item_def.precision or 2

	MenuCallbackHandler[item_def.callback] = function(_, item)
		local value = item:value()

		if is_slider and precision == 0 then
			value = math.floor(value + 0.5)
		end

		target[item_def.data_key] = value

		save()
	end
end

Hooks:Add("MenuManagerInitialize", "nqr_mags_menu_initialize", function()
	for i = 1, #MAGS_ITEMS do
		register_callback(MAGS_ITEMS[i], cfg, cfg.api.save)
	end

	for i = 1, #FILL_ITEMS do
		register_callback(FILL_ITEMS[i], rcfg, rcfg.api.save)
	end
end)

local function register_menu_loc()
	local loc = managers and managers.localization

	if loc and loc.add_localized_strings then
		loc:add_localized_strings({
			[MAGS_MENU_ID .. "_title"] = MAGS_MENU_TITLE,
			[MAGS_MENU_ID .. "_desc"] = MAGS_MENU_DESC,
			[FILL_MENU_ID .. "_title"] = FILL_MENU_TITLE,
			[FILL_MENU_ID .. "_desc"] = FILL_MENU_DESC
		})
	end
end

register_menu_loc()

Hooks:Add("MenuManagerInitialize", "nqr_mags_menu_loc", register_menu_loc)
Hooks:Add("LocalizationManagerPostInit", "nqr_mags_menu_loc_post", register_menu_loc)

Hooks:Add("MenuManagerSetupCustomMenus", "nqr_mags_menu_setup", function()
	MenuHelper:NewMenu(MAGS_MENU_ID)
	MenuHelper:NewMenu(FILL_MENU_ID)
end)

Hooks:Add("MenuManagerPopulateCustomMenus", "nqr_mags_menu_populate", function()
	for i = 1, #MAGS_ITEMS do
		add_dynamic_menu_item(MAGS_MENU_ID, MAGS_ITEMS[i], #MAGS_ITEMS - i + 1, cfg)
	end

	for i = 1, #FILL_ITEMS do
		add_dynamic_menu_item(FILL_MENU_ID, FILL_ITEMS[i], #FILL_ITEMS - i + 1, rcfg)
	end
end)

Hooks:Add("MenuManagerBuildCustomMenus", "nqr_mags_menu_build", function(_, nodes)
	local parent = nodes and (nodes.lua_mod_options_menu or nodes.blt_options or nodes.options)

	if not parent then
		dbg("no parent menu node found")
		return
	end

	nodes[MAGS_MENU_ID] = MenuHelper:BuildMenu(MAGS_MENU_ID, { area_bg = "half" })
	MenuHelper:AddMenuItem(parent, MAGS_MENU_ID, MAGS_MENU_ID .. "_title", MAGS_MENU_ID .. "_desc")

	nodes[FILL_MENU_ID] = MenuHelper:BuildMenu(FILL_MENU_ID, { area_bg = "half" })
	MenuHelper:AddMenuItem(parent, FILL_MENU_ID, FILL_MENU_ID .. "_title", FILL_MENU_ID .. "_desc")
end)
