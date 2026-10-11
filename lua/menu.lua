-- Einstieg (menumanager-Hook): laedt zuerst den gemeinsamen Zustand.
dofile(ModPath .. "lua/state.lua")

local cfg = rawget(_G, "NQR_MAGS")
local rcfg = rawget(_G, "NQR_MAGFILL")
local dbg = cfg.api.log

local MAGS_MENU_ID = "nqr_mags_menu"
local LOC_PATH = ModPath .. "loc/"

local function file_exists(path)
	local file = io.open(path, "r")

	if file then
		file:close()
		return true
	end

	return false
end

Hooks:Add("LocalizationManagerPostInit", "nqr_mags_loc_init", function(loc)
	local lang = BLT.Localization and BLT.Localization:get_language()
	local code = (lang and lang.language) or (BLT.save_data and BLT.save_data.language) or "en"
	local own = file_exists(LOC_PATH .. code .. ".txt")

	if own then
		loc:load_localization_file(LOC_PATH .. code .. ".txt")
	end

	-- Englisch als Fallback; ueberschreibt vorhandene Texte nicht.
	if code ~= "en" or not own then
		loc:load_localization_file(LOC_PATH .. "en.txt", not own)
	end
end)

-- Die Menue-Eintraege kommen aus den Schemata in state.lua. Texte und Callback
-- heissen immer <id>_title, <id>_desc und <id>_callback.
local GROUPS = {
	{ schema = cfg.api.schema, target = cfg, api = cfg.api },
	{ schema = rcfg.api.schema, target = rcfg, api = rcfg.api }
}

local LAYOUT = {}

for g = 1, #GROUPS do
	if g > 1 then
		LAYOUT[#LAYOUT + 1] = { divider = "nqr_mags_divider_" .. (g - 1) }
	end

	for i = 1, #GROUPS[g].schema do
		LAYOUT[#LAYOUT + 1] = { def = GROUPS[g].schema[i], target = GROUPS[g].target }
	end
end

LAYOUT[#LAYOUT + 1] = { divider = "nqr_mags_divider_" .. #GROUPS }
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
			id = entry.divider,
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
		title = def.id .. "_title",
		desc = def.id .. "_desc",
		callback = def.id .. "_callback",
		value = entry.target[def.key],
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
		data.is_percentage = def.percent or false
		MenuHelper:AddSlider(data)
	end
end

local function register_callback(def, target, save)
	local is_slider = def.type == "slider"
	local round = is_slider and (def.precision or 2) == 0

	MenuCallbackHandler[def.id .. "_callback"] = function(_, item)
		local value = item:value()

		if is_slider then
			if round then
				value = math.floor(value + 0.5)
			end
		else
			value = value == true or value == "on"
		end

		target[def.key] = value

		save()
	end
end

-- Setzt Menue-Anzeige, gespeicherte Werte und Datei zurueck.
-- (ResetItemsToDefaultValue aendert nur das Menue, nicht die Werte.)
local function reset_all(item)
	for g = 1, #GROUPS do
		local group = GROUPS[g]

		for i = 1, #group.schema do
			local def = group.schema[i]
			local default = group.api.defaults[def.key]

			group.target[def.key] = default
			MenuHelper:ResetItemsToDefaultValue(item, { [def.id] = true }, default)
		end

		group.api.save()
	end
end

Hooks:Add("MenuManagerInitialize", "nqr_mags_menu_initialize", function()
	for g = 1, #GROUPS do
		local group = GROUPS[g]

		for i = 1, #group.schema do
			register_callback(group.schema[i], group.target, group.api.save)
		end
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
