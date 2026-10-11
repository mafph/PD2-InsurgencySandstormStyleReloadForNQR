local cfg = rawget(_G, "NQR_MAGS") or {}
_G.NQR_MAGS = cfg

local rcfg = rawget(_G, "NQR_MAGFILL") or {}
_G.NQR_MAGFILL = rcfg

local MAGS_SCHEMA = {
	{ key = "enabled", id = "nqr_mags_enabled", type = "toggle", default = true },
	{ key = "max_extra_mags", id = "nqr_mags_max_extra", type = "slider", default = 0, min = 0, max = 2, step = 1, precision = 0 },
	{ key = "ammo_max", id = "nqr_mags_ammo_max", type = "slider", default = 125, min = 100, max = 200, step = 5, precision = 0, percent = true },
	{ key = "overlay_always", id = "nqr_mags_overlay_always", type = "toggle", default = false },
	{ key = "show_mags", id = "nqr_mags_counts", type = "toggle", default = false },
	{ key = "show_loose", id = "nqr_mags_loose", type = "toggle", default = true },
	{ key = "show_ammo_type", id = "nqr_mags_ammo_type", type = "toggle", default = false },
	{ key = "max_boxes", id = "nqr_mags_max_boxes", type = "slider", default = 4, min = 2, max = 24, step = 1, precision = 0 },
	{ key = "show_more", id = "nqr_mags_more", type = "toggle", default = true },
	{ key = "font_size", id = "nqr_mags_font", type = "slider", default = 20, min = 10, max = 28, step = 1, precision = 0 },
	{ key = "pad_right", id = "nqr_mags_pad_right", type = "slider", default = 220, min = -100, max = 300, step = 2, precision = 0 },
	{ key = "pad_bottom", id = "nqr_mags_pad_bottom", type = "slider", default = 100, min = -50, max = 400, step = 2, precision = 0 }
}

local FILL_SCHEMA = {
	{ key = "enabled", id = "nqr_magfill_enabled", type = "toggle", default = true },
	{ key = "round_interval", id = "nqr_magfill_interval", type = "slider", default = 0.25, min = 0.02, max = 1, step = 0.01, precision = 2 },
	{ key = "sound", id = "nqr_magfill_sound", type = "toggle", default = true },
	{ key = "unblock_bag", id = "nqr_magfill_unblock", type = "toggle", default = true }
}

local function schema_keys(schema)
	local keys = {}

	for i = 1, #schema do
		keys[schema[i].key] = true
	end

	return keys
end

local function schema_defaults(schema)
	local defaults = {}

	for i = 1, #schema do
		defaults[schema[i].key] = schema[i].default
	end

	return defaults
end

local MAGS_SETTINGS_KEYS = schema_keys(MAGS_SCHEMA)
local FILL_SETTINGS_KEYS = schema_keys(FILL_SCHEMA)
local MAGS_DEFAULTS = schema_defaults(MAGS_SCHEMA)
local FILL_DEFAULTS = schema_defaults(FILL_SCHEMA)

local function load_settings(target, name, keys)
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
		return
	end

	for key, value in pairs(data) do
		if keys[key] then
			target[key] = value
		end
	end
end

local function save_settings(target, name, keys)
	if not rawget(_G, "json") then return end

	local data = {}

	for key in pairs(keys) do
		data[key] = target[key]
	end

	local ok, encoded = pcall(json.encode, data)

	if not ok then
		return
	end

	local file = io.open((SavePath or "") .. name, "w")

	if file then
		file:write(encoded)
		file:close()
	end
end

load_settings(cfg, "nqr_mags_settings.txt", MAGS_SETTINGS_KEYS)
load_settings(rcfg, "nqr_magfill_settings.txt", FILL_SETTINGS_KEYS)

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

cfg.mags = cfg.mags or {}
cfg.dropped = cfg.dropped or {}

apply_defaults(rcfg, FILL_DEFAULTS)

cfg.hooks = cfg.hooks or {}

local function wrap(class_name, fn_name, make)
	local cls = rawget(_G, class_name)
	local current = cls and cls[fn_name]

	if not current then return false end

	local key = class_name .. "." .. fn_name
	local entry = cfg.hooks[key]

	if entry and current == entry.hook then return true end

	entry = entry or {}
	cfg.hooks[key] = entry

	local inner = make(current)

	local function finish(ok, ...)
		entry.busy = false

		if not ok then
			error((...), 0)
		end

		return ...
	end

	entry.hook = function(self, ...)
		if entry.busy then
			return current(self, ...)
		end

		entry.busy = true

		return finish(pcall(inner, self, ...))
	end

	cls[fn_name] = entry.hook

	return true
end

local function player_unit()
	return managers.player and managers.player:player_unit()
end

local function L(id, fallback)
	local loc = managers.localization

	if loc and loc.exists and loc:exists(id) then
		return loc:text(id)
	end

	return fallback
end

local function extra_mags()
	return math.max(0, math.floor(cfg.max_extra_mags or 0))
end

local function equipped_unit()
	local unit = player_unit()

	return unit and unit:inventory() and unit:inventory():equipped_unit()
end

local function equipped_base()
	local unit = equipped_unit()

	return unit and unit:base()
end

local function is_ours(wep)
	local unit = player_unit()
	local setup = wep and wep._setup

	if not alive(unit) or not setup or not alive(setup.user_unit) then return false end

	return setup.user_unit:key() == unit:key()
end

local function find_mag_part(blueprint)
	local magazine = nil
	local clip = nil

	for i = 1, #blueprint do
		local part = tweak_data.weapon.factory.parts[blueprint[i]]

		if part then
			local has_clip = part.stats and part.stats.CLIP_AMMO_MAX

			if has_clip then
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

local function mag_part_id(wep)
	local blueprint = wep._blueprint

	if not blueprint then return nil end

	if wep._nqr_pid_bp ~= blueprint or wep._nqr_pid_n ~= #blueprint then
		wep._nqr_pid = find_mag_part(blueprint) or false
		wep._nqr_pid_bp = blueprint
		wep._nqr_pid_n = #blueprint
	end

	return wep._nqr_pid or nil
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

	local ok, value = pcall(wep.get_chamber, wep)

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

		for _ = 1, extra_mags() do
			queue[#queue + 1] = new_mag(0)
		end

		cfg.mags[key] = queue
	end

	return queue, key, pid, caliber, mag_capacity(pid, caliber)
end

local function sort_queue(queue)
	table.sort(queue, function(a, b)
		return (a.rounds or 0) > (b.rounds or 0)
	end)
end

local function mag_left(wep)
	local queue = queue_of(wep)

	if not queue then return end

	local rounds = math.max(0, wep:get_ammo_remaining_in_clip() - chamber_of(wep))

	wep._nqr_mag_left_rounds = rounds
	wep._nqr_mag_installed = new_mag(0)
	wep._nqr_drop_count = 0
	wep._nqr_no_mag = true

	cfg.panel_dirty = true
end

local function mag_entered(wep)
	wep._nqr_no_mag = nil
	cfg.panel_dirty = true
end

local function reload_interrupted(wep)
	if not wep._nqr_mag_left_rounds and (wep._nqr_drop_count or 0) < 1 then return end

	local queue = queue_of(wep)
	local drops = wep._nqr_drop_count or 0

	wep._nqr_drop_count = 0
	wep._nqr_mag_left_rounds = nil

	cfg.panel_dirty = true

	if not queue then return end

	if drops >= 1 then
		wep._nqr_no_mag = true
		wep._nqr_mag_gone = true
		wep._nqr_mag_installed = new_mag(0)
	else
		wep._nqr_mag_installed = new_mag(math.max(0, wep:get_ammo_remaining_in_clip() - chamber_of(wep)))
		wep._nqr_no_mag = nil
		wep._nqr_mag_gone = nil
	end
end

local sync_total

local function loose_of(wep)
	if wep._nqr_mag_loose == nil then
		wep._nqr_mag_loose = 0
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

local function max_total(wep)
	local pid = mag_part_id(wep)
	local caliber = wep._caliber

	if not pid or not caliber then return nil end

	local capacity = mag_capacity(pid, caliber)
	local base = capacity + chamber_of(wep) + nqr_mag_amount(wep) * capacity

	return math.floor(base * math.max(1, cfg.ammo_max / 100))
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
	return mag_amount_for(tag.pid, tag.caliber, tag.name_id) + extra_mags()
end

local function can_pickup_dropped(tag)
	local queue = tag and cfg.mags[tag.queue_key]

	if not queue then return false end

	local cap = dropped_cap(tag)
	local wep = equipped_base()

	if wep and wep._nqr_mag_gone and queue_of(wep) == queue then
		cap = cap + 1
	end

	return #queue < cap
end

local function pickup_dropped(tag)
	if not can_pickup_dropped(tag) then return false end

	local queue = cfg.mags[tag.queue_key]

	queue[#queue + 1] = new_mag(tag.rounds or 0)

	local wep = equipped_base()

	if wep and queue_of(wep) == queue then
		sync_total(wep)
	end

	cfg.panel_dirty = true
	refresh_hud()

	return true
end

local function job_done(job)
	if job.index <= #job.list then return false end

	rcfg.job = nil

	return true
end

local function add_to_job(wep)
	if rcfg.job then
		job_done(rcfg.job)
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
end

local function installed_room(wep, capacity)
	if wep._nqr_no_mag or wep._nqr_mag_gone then return 0 end

	local rounds = math.max(0, wep:get_ammo_remaining_in_clip() - chamber_of(wep))

	return math.max(0, capacity - rounds)
end

local function fill_mags(wep, amount)
	local queue, _, pid, caliber, capacity = queue_of(wep)

	if not queue or not capacity or amount <= 0 then return amount end

	for i = 1, #queue do
		local take = math.min(amount, math.max(0, capacity - (queue[i].rounds or 0)))

		queue[i].rounds = (queue[i].rounds or 0) + take
		amount = amount - take
	end

	local max_mags = mag_amount_for(pid, caliber, wep._name_id) + extra_mags()

	if wep._nqr_mag_gone then max_mags = max_mags + 1 end

	while amount > 0 and #queue < max_mags do
		local take = math.min(amount, capacity)

		queue[#queue + 1] = new_mag(take)
		amount = amount - take
	end

	local take = math.min(amount, installed_room(wep, capacity))

	if take > 0 then
		local installed = wep._nqr_mag_installed or new_mag(0)

		wep:set_ammo_remaining_in_clip(wep:get_ammo_remaining_in_clip() + take)
		installed.rounds = math.max(0, wep:get_ammo_remaining_in_clip() - chamber_of(wep))
		wep._nqr_mag_installed = installed
		amount = amount - take
	end

	sort_queue(queue)

	return amount
end

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

	if job_done(job) then return end

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

	local into_gun = false

	if not target and installed_room(wep, capacity) > 0 then
		into_gun = true
		target = wep._nqr_mag_installed or new_mag(0)
		wep._nqr_mag_installed = target
	end

	if not target then
		job.index = job.index + 1
		return
	end

	if into_gun then
		wep:set_ammo_remaining_in_clip(wep:get_ammo_remaining_in_clip() + 1)
		target.rounds = math.max(0, wep:get_ammo_remaining_in_clip() - chamber_of(wep))
	else
		target.rounds = (target.rounds or 0) + 1
	end

	set_loose(wep, loose_of(wep) - 1)
	sync_total(wep)
	sort_queue(queue)

	job.filled = job.filled + 1

	refresh_hud()
	cfg.panel_dirty = true

	if target.rounds >= capacity then
		if rcfg.sound then
			local unit = player_unit()

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

	if job_done(job) then return end

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

	return installed_room(wep, capacity) > 0
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
cfg.api.mag_left = mag_left
cfg.api.mag_entered = mag_entered
cfg.api.reload_interrupted = reload_interrupted
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
cfg.api.fill_mags = fill_mags
cfg.api.tick = tick
cfg.api.magazines_need_fill = magazines_need_fill
cfg.api.needs_fill = needs_fill
cfg.api.save = function() save_settings(cfg, "nqr_mags_settings.txt", MAGS_SETTINGS_KEYS) end
cfg.api.defaults = MAGS_DEFAULTS
cfg.api.schema = MAGS_SCHEMA
cfg.api.wrap = wrap
cfg.api.player_unit = player_unit
cfg.api.L = L

rcfg.api = rcfg.api or {}

rcfg.api.save = function() save_settings(rcfg, "nqr_magfill_settings.txt", FILL_SETTINGS_KEYS) end
rcfg.api.defaults = FILL_DEFAULTS
rcfg.api.schema = FILL_SCHEMA
