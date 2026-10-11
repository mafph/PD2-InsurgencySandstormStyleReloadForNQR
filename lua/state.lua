local cfg = rawget(_G, "NQR_MAGS") or {}
_G.NQR_MAGS = cfg

local rcfg = rawget(_G, "NQR_MAGFILL") or {}
_G.NQR_MAGFILL = rcfg

local function print_log(prefix, ...)
	local parts = {}

	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring(select(i, ...))
	end

	local out = prefix .. " " .. table.concat(parts, " ")

	if _G.log then
		_G.log(out)
	else
		print(out)
	end
end

local function dbg(...)
	if not cfg.debug then return end

	print_log("[nqr_mags]", ...)
end

local function rdbg(...)
	if not rcfg.debug then return end

	print_log("[nqr_magfill]", ...)
end

local MAGS_SETTINGS_KEYS = {
	enabled = true,
	max_extra_mags = true,
	ammo_max = true,
	max_boxes = true,
	show_mags = true,
	show_loose = true,
	show_more = true,
	show_ammo_type = true,
	font_size = true,
	pad_right = true,
	pad_bottom = true,
	debug = true
}

local FILL_SETTINGS_KEYS = {
	enabled = true,
	round_interval = true,
	sound = true,
	unblock_bag = true,
	debug = true
}

local MAGS_DEFAULTS = {
	enabled = true,
	max_extra_mags = 0,
	ammo_max = 125,
	max_boxes = 4,
	show_mags = false,
	show_loose = true,
	show_more = true,
	show_ammo_type = false,
	font_size = 20,
	pad_right = 220,
	pad_bottom = 100,
	debug = false
}

local FILL_DEFAULTS = {
	enabled = true,
	round_interval = 0.25,
	sound = true,
	unblock_bag = true,
	debug = false
}

local function load_settings(target, name, keys, log)
	if target.settings_loaded then return end

	target.settings_loaded = true

	if not rawget(_G, "json") then return end

	local file = io.open((SavePath or "") .. name, "r")

	if not file then return end

	local raw = file:read("*all")

	file:close()

	if not raw or raw == "" then return end

	local ok, data = pcall(json.decode, raw)

	if not ok or type(data) ~= "table" then
		log("settings file unreadable")
		return
	end

	for key, value in pairs(data) do
		if keys[key] then
			target[key] = value
		end
	end

	log("settings loaded")
end

local function save_settings(target, name, keys, log)
	if not rawget(_G, "json") then return end

	local data = {}

	for key in pairs(keys) do
		data[key] = target[key]
	end

	local ok, encoded = pcall(json.encode, data)

	if not ok then
		log("settings encode failed")
		return
	end

	local file = io.open((SavePath or "") .. name, "w")

	if file then
		file:write(encoded)
		file:close()
	else
		log("settings file not writable")
	end
end

load_settings(cfg, "nqr_mags_settings.txt", MAGS_SETTINGS_KEYS, dbg)
load_settings(rcfg, "nqr_magfill_settings.txt", FILL_SETTINGS_KEYS, rdbg)

local function apply_defaults(target, defaults)
	for key, value in pairs(defaults) do
		if target[key] == nil then
			target[key] = value
		elseif type(value) == "boolean" then
			target[key] = target[key] == true or target[key] == "on"
		end
	end
end

apply_defaults(cfg, MAGS_DEFAULTS)

cfg.box_w = cfg.box_w or 20
cfg.box_h = cfg.box_h or 28
cfg.box_gap = cfg.box_gap or 4
cfg.mags = cfg.mags or {}
cfg.dropped = cfg.dropped or {}

apply_defaults(rcfg, FILL_DEFAULTS)

local function equipped_unit()
	local unit = managers.player and managers.player:player_unit()

	return unit and unit:inventory() and unit:inventory():equipped_unit()
end

local function equipped_base()
	local unit = equipped_unit()

	return unit and unit:base()
end

local function is_ours(wep)
	local unit = managers.player and managers.player:player_unit()
	local setup = wep and wep._setup

	if not alive(unit) or not setup or not alive(setup.user_unit) then return false end

	return setup.user_unit:key() == unit:key()
end

local function mag_part_id(wep)
	local blueprint = wep._blueprint
	local magazine = nil
	local clip = nil

	if not blueprint then return nil end

	for i = 1, #blueprint do
		local part = tweak_data.weapon.factory.parts[blueprint[i]]

		if part then
			local has_clip = part.stats and part.stats.CLIP_AMMO_MAX

			if has_clip then
				-- Teil mit CLIP_AMMO_MAX bevorzugen: bei Revolvern (z.B. model3)
				-- traegt das Magazin-Slot-Teil (m_bullets/m_body) keine Kapazitaet,
				-- die echte Kapazitaet steht auf dem Zylinder.
				if part.type == "magazine" then
					return blueprint[i]
				end

				clip = clip or blueprint[i]
			elseif part.type == "magazine" and not magazine then
				magazine = blueprint[i]
			end
		end
	end

	return clip or magazine
end

local function mag_capacity(pid, caliber)
	local part = tweak_data.weapon.factory.parts[pid]
	local value = part and part.stats and part.stats.CLIP_AMMO_MAX

	if type(value) == "number" then
		return value
	end

	if type(value) == "table" then
		local by_caliber = value[caliber]

		if type(by_caliber) == "number" then
			return by_caliber
		end

		for _, v in pairs(value) do
			if type(v) == "number" then
				return v
			end
		end
	end

	return 30
end

local function chamber_of(wep)
	if not wep or not wep.get_chamber then return 0 end

	local ok, value = pcall(function() return wep:get_chamber() end)

	if ok and type(value) == "number" then
		return value
	end

	return 0
end

local function full_capacity(wep)
	local pid = mag_part_id(wep)

	if not pid or not wep._caliber then return nil end

	return mag_capacity(pid, wep._caliber) + chamber_of(wep)
end

local function new_mag(rounds)
	return { rounds = rounds }
end

local function mag_amount_for(pid, caliber, name_id)
	local part = pid and tweak_data.weapon.factory.parts[pid]
	local value = part and part.stats and part.stats.mag_amount
	local amount = nil

	if type(value) == "table" then
		amount = value[2]
	elseif type(value) == "number" then
		amount = value
	end

	if type(amount) == "number" and amount >= 1 then
		return math.floor(amount)
	end

	-- NQR-Fallback wie deren replenish: AMMO_MAX der Waffe als ganze Magazine
	local capacity = pid and caliber and mag_capacity(pid, caliber) or 0
	local tweak = name_id and tweak_data.weapon[name_id]

	if capacity > 0 and tweak and type(tweak.AMMO_MAX) == "number" then
		return math.max(1, math.floor(tweak.AMMO_MAX / capacity))
	end

	return 3
end

local function nqr_mag_amount(wep)
	return mag_amount_for(mag_part_id(wep), wep._caliber, wep._name_id)
end

local function queue_of(wep)
	local pid = mag_part_id(wep)
	local caliber = wep._caliber

	if not pid or not caliber then return nil end

	local key = tostring(caliber) .. "|" .. tostring(pid)
	local queue = cfg.mags[key]

	if not queue then
		local capacity = mag_capacity(pid, caliber)

		queue = {}
		for _ = 1, nqr_mag_amount(wep) do
			queue[#queue + 1] = new_mag(capacity)
		end

		for _ = 1, math.max(0, math.floor(cfg.max_extra_mags or 0)) do
			queue[#queue + 1] = new_mag(0)
		end

		cfg.mags[key] = queue
		dbg("seeded " .. key .. " x" .. tostring(#queue) .. " cap=" .. tostring(capacity))
	end

	return queue, key, pid, caliber, mag_capacity(pid, caliber)
end

local function sort_queue(queue)
	table.sort(queue, function(a, b)
		return (a.rounds or 0) > (b.rounds or 0)
	end)
end

local sync_total

local function loose_of(wep)
	if wep._nqr_mag_loose == nil then
		wep._nqr_mag_loose = 0
		dbg("initial loose 0 on " .. tostring(wep._name_id))
		sync_total(wep)
	end

	return wep._nqr_mag_loose
end

local function set_loose(wep, value)
	wep._nqr_mag_loose = math.max(0, math.floor(value or 0))
end

local function queue_rounds(wep)
	local queue = queue_of(wep)
	local rounds = 0

	if queue then
		for i = 1, #queue do
			rounds = rounds + (queue[i].rounds or 0)
		end
	end

	return rounds
end

sync_total = function(wep)
	wep:set_ammo_total(wep:get_ammo_remaining_in_clip() + loose_of(wep) + queue_rounds(wep))
end

-- Wert fuer ammo_max der Waffe: ammo_max-Prozent mal Startmenge (volles Magazin + Rebalance-Magazinanzahl * Magazingroesse).
local function max_total(wep)
	local pid = mag_part_id(wep)
	local caliber = wep._caliber

	if not pid or not caliber then return nil end

	local capacity = mag_capacity(pid, caliber)
	local base = capacity + chamber_of(wep) + nqr_mag_amount(wep) * capacity

	return math.floor(base * math.max(1, (cfg.ammo_max or 125) / 100))
end

local function skip_weapon(wep)
	if not cfg.enabled then return true end
	if not is_ours(wep) then return true end
	if not wep._blueprint then return true end
	if wep._second_gun then return true end
	if wep.use_shotgun_reload and wep:use_shotgun_reload() then return true end
	if wep.is_special and wep:is_special() then return true end

	return mag_part_id(wep) == nil
end

local function mag_count(wep)
	if not wep or skip_weapon(wep) then return nil end

	local queue = queue_of(wep)

	if not queue then return nil end

	return #queue
end

local function refresh_hud()
	pcall(function()
		local base = equipped_base()

		if not base or not base.selection_index or not base.ammo_info then return end

		managers.hud:set_ammo_amount(base:selection_index(), base:ammo_info())
	end)
end

local function dropped_cap(tag)
	return mag_amount_for(tag.pid, tag.caliber, tag.name_id) + math.max(0, math.floor(cfg.max_extra_mags or 0))
end

local function can_pickup_dropped(tag)
	local queue = tag and cfg.mags[tag.queue_key]

	if not queue then return false end

	return #queue < dropped_cap(tag)
end

local function pickup_dropped(tag)
	if not can_pickup_dropped(tag) then return false end

	local queue = cfg.mags[tag.queue_key]

	queue[#queue + 1] = new_mag(tag.rounds or 0)

	dbg("picked up mag rounds=" .. tostring(tag.rounds or 0) .. " key=" .. tostring(tag.queue_key)
		.. " queue=" .. tostring(#queue))

	cfg.panel_dirty = true
	refresh_hud()

	return true
end

local function add_to_job(wep)
	if rcfg.job and rcfg.job.index > #rcfg.job.list then
		rcfg.job = nil
	end

	if not rcfg.job then
		rcfg.job = {
			list = {},
			index = 1,
			t = 0,
			filled = 0
		}
	end

	for i = 1, #rcfg.job.list do
		if rcfg.job.list[i] == wep then return end
	end

	rcfg.job.list[#rcfg.job.list + 1] = wep

	rdbg("queued " .. tostring(wep._name_id) .. " for refill")
end

-- Fuellt pro Aufruf genau eine Patrone aus den losen Patronen ins naechste nicht volle Magazin.
local function fill_one_round()
	local job = rcfg.job

	if not job then return end

	while job.index <= #job.list do
		local wep = job.list[job.index]

		if not wep or skip_weapon(wep) then
			job.index = job.index + 1
		else
			break
		end
	end

	if job.index > #job.list then
		rdbg("refill done, rounds filled=" .. tostring(job.filled))
		rcfg.job = nil
		return
	end

	local wep = job.list[job.index]
	local queue, _, _, _, capacity = queue_of(wep)

	if not queue or not capacity or loose_of(wep) <= 0 then
		job.index = job.index + 1
		return
	end

	local target = nil

	for i = 1, #queue do
		if capacity - (queue[i].rounds or 0) > 0 then
			target = queue[i]
			break
		end
	end

	if not target then
		job.index = job.index + 1
		return
	end

	target.rounds = (target.rounds or 0) + 1

	set_loose(wep, loose_of(wep) - 1)
	sync_total(wep)
	sort_queue(queue)

	job.filled = job.filled + 1

	refresh_hud()
	cfg.panel_dirty = true

	if target.rounds >= capacity then
		rdbg("mag full " .. tostring(capacity) .. " loose=" .. tostring(loose_of(wep)) .. " rounds=" .. tostring(job.filled))

		if rcfg.sound then
			local unit = managers.player and managers.player:player_unit()

			if unit and unit.sound then
				pcall(function() unit:sound():play("pickup_ammo") end)
			end
		end
	end
end

local function tick(dt)
	if not rcfg.enabled then return end

	local job = rcfg.job

	if not job then return end

	if job.index > #job.list then
		rdbg("refill done, rounds filled=" .. tostring(job.filled))
		rcfg.job = nil
		return
	end

	job.t = job.t + (dt or 0)

	if job.t < rcfg.round_interval then return end

	job.t = 0
	fill_one_round()
end

local function needs_fill(wep)
	if not wep or skip_weapon(wep) then return false end

	local queue, _, _, _, capacity = queue_of(wep)

	if not queue or not capacity then return false end

	for i = 1, #queue do
		if capacity - (queue[i].rounds or 0) > 0 then return true end
	end

	return false
end

local function magazines_need_fill(player)
	local inventory = player and player:inventory()
	local selections = inventory and inventory:available_selections()

	if not selections then return false end

	for _, sel in pairs(selections) do
		local wep = sel.unit and sel.unit:base()

		if wep and not skip_weapon(wep) then
			local queue, _, _, _, capacity = queue_of(wep)

			if queue and capacity then
				if wep._nqr_mag_installed and (wep._nqr_mag_installed.rounds or 0) < capacity then
					return true
				end

				for i = 1, #queue do
					if capacity - (queue[i].rounds or 0) > 0 then
						return true
					end
				end
			end
		end
	end

	return false
end

cfg.api = cfg.api or {}

cfg.api.loose_of = loose_of
cfg.api.max_total = max_total
cfg.api.set_loose = set_loose
cfg.api.sync_total = sync_total
cfg.api.queue_of = queue_of
cfg.api.sort_queue = sort_queue
cfg.api.skip_weapon = skip_weapon
cfg.api.new_mag = new_mag
cfg.api.chamber_of = chamber_of
cfg.api.equipped_base = equipped_base
cfg.api.mag_count = mag_count
cfg.api.refresh_hud = refresh_hud
cfg.api.dropped = cfg.dropped
cfg.api.can_pickup_dropped = can_pickup_dropped
cfg.api.pickup_dropped = pickup_dropped
cfg.api.add_to_job = add_to_job
cfg.api.tick = tick
cfg.api.magazines_need_fill = magazines_need_fill
cfg.api.needs_fill = needs_fill
cfg.api.save = function() save_settings(cfg, "nqr_mags_settings.txt", MAGS_SETTINGS_KEYS, dbg) end
cfg.api.log = dbg
cfg.api.defaults = MAGS_DEFAULTS

rcfg.api = rcfg.api or {}

rcfg.api.save = function() save_settings(rcfg, "nqr_magfill_settings.txt", FILL_SETTINGS_KEYS, rdbg) end
rcfg.api.log = rdbg
rcfg.api.defaults = FILL_DEFAULTS
