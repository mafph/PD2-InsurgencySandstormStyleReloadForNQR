-- Spieler-Hooks: R tippen = Nachladen, R halten = HUD, Ticker pro Frame.

local cfg = rawget(_G, "NQR_MAGS")
local rcfg = rawget(_G, "NQR_MAGFILL")
local api = cfg.api

local function reload_held(state)
	local controller = state and state._controller

	if not controller or not controller.get_input_bool then return false end
	if controller.get_any_input and not controller:get_any_input() then return false end

	return controller:get_input_bool("reload") and true or false
end

local function tap_hold_time()
	local nqr = rawget(_G, "NQR")
	local retention = nqr and nqr.settings and nqr.settings.nqr_retention_time

	if type(retention) == "number" and retention > 0 then
		return retention
	end

	return 0.2
end

local function make_reload_hook(orig)
	local function hook(self, t, input)
		if not cfg.enabled then
			if cfg.tap_pending or cfg.panel_visible then
				cfg.tap_t = nil
				cfg.tap_pending = false
				cfg.tap_confirmed = false
				api.set_panel(false)
			end

			return orig(self, t, input)
		end

		local held = reload_held(self)

		if held then
			if input and input.btn_reload_press and self._magdrop_t and (t <= self._magdrop_t) and not self._magdrop_first_press then
				cfg.tap_t = nil
				cfg.tap_pending = false
				cfg.tap_confirmed = false
				api.set_panel(false)

				return orig(self, t, input)
			end

			if not cfg.tap_t then
				cfg.tap_t = t
				cfg.tap_confirmed = false
				cfg.tap_pending = true
			end

			if not cfg.tap_confirmed and (t - cfg.tap_t) >= tap_hold_time() then
				cfg.tap_confirmed = true
			end

			if cfg.tap_confirmed then
				api.set_panel(true)
				self._magdrop_t = nil
				self._magdrop_first_press = nil

				local wep = api.equipped_base()

				if wep and api.loose_of(wep) > 0 then
					api.add_to_job(wep)
				end
			end

			return false
		end

		if cfg.tap_pending then
			local tap_age = cfg.tap_t and (t - cfg.tap_t) or 999
			local short_press = not cfg.tap_confirmed and tap_age <= 1

			cfg.tap_t = nil
			cfg.tap_pending = false
			cfg.tap_confirmed = false

			if short_press then
				api.set_panel(false)

				return orig(self, t, { btn_reload_press = true })
			end
		end

		api.set_panel(false)

		return orig(self, t, input)
	end

	return hook
end

local function ensure_reload_hook()
	local PS = rawget(_G, "PlayerStandard")

	if not PS or not PS._check_action_reload then return end
	if PS._check_action_reload == cfg.reload_hook then return end

	cfg.reload_hook = make_reload_hook(PS._check_action_reload)
	PS._check_action_reload = cfg.reload_hook
end

local PICKUP_RANGE = 250
local PICKUP_HOLD = 1
local AIM_RADIUS = 50
local mvec_from = Vector3()
local mvec_to = Vector3()
local mvec_dir = Vector3()
local mvec_v = Vector3()
local mvec_closest = Vector3()

local function clear_pickup()
	if cfg.pickup_shown then
		cfg.pickup_shown = nil

		pcall(function()
			managers.hud:hide_interaction_bar(false)
			managers.hud:remove_interact()
		end)
	end

	cfg.pickup_tag = nil
	cfg.pickup_t = nil
end

local function prune_dropped()
	local dropped = api.dropped

	for k, tag in pairs(dropped) do
		if not alive(tag.col) then
			dropped[k] = nil
		end
	end
end

local function update_pickup(state, t)
	prune_dropped()

	if not cfg.enabled then
		clear_pickup()
		return
	end

	local pl = managers.player and managers.player:player_unit()
	local cam = pl and pl:camera()
	local pos = cam and cam:position()
	local rot = cam and cam:rotation()

	if not pos or not rot then
		clear_pickup()
		return
	end

	mvector3.set(mvec_from, pos)
	mvector3.set(mvec_to, rot:y())
	mvector3.multiply(mvec_to, PICKUP_RANGE)
	mvector3.add(mvec_to, mvec_from)

	local ray = World:raycast(mvec_from, mvec_to)
	local hit_dist = ray and mvector3.distance(mvec_from, ray.position) or PICKUP_RANGE
	local tag = ray and ray.unit and alive(ray.unit) and api.dropped[ray.unit:key()] or nil

	if not tag then
		mvector3.set(mvec_dir, mvec_to)
		mvector3.subtract(mvec_dir, mvec_from)
		mvector3.normalize(mvec_dir)

		local best, best_along = nil, nil

		for _, cand in pairs(api.dropped) do
			if alive(cand.col) and api.can_pickup_dropped(cand) then
				mvector3.set(mvec_v, cand.col:position())
				mvector3.subtract(mvec_v, mvec_from)

				local along = mvector3.dot(mvec_v, mvec_dir)

				if along > 0 and along <= hit_dist then
					mvector3.set(mvec_closest, mvec_dir)
					mvector3.multiply(mvec_closest, along)
					mvector3.subtract(mvec_v, mvec_closest)

					local perp = mvector3.length(mvec_v)

					if perp <= AIM_RADIUS and (not best_along or along < best_along) then
						best = cand
						best_along = along
					end
				end
			end
		end

		tag = best
	end

	if not tag or not api.can_pickup_dropped(tag) then
		clear_pickup()
		return
	end

	if state._interacting and state:_interacting() then
		clear_pickup()
		return
	end

	if cfg.pickup_tag ~= tag then
		cfg.pickup_tag = tag
		cfg.pickup_t = t
		cfg.pickup_shown = true

		pcall(function()
			managers.hud:show_interact({
				text = managers.localization:btn_macro("interact", false) .. " Magazin aufheben"
			})
		end)

		return
	end

	local controller = state._controller

	if not controller or not controller.get_input_bool or not controller:get_input_bool("interact") then
		clear_pickup()
		return
	end

	local progress = math.min(1, (t - cfg.pickup_t) / PICKUP_HOLD)

	pcall(function()
		managers.hud:show_interaction_bar(progress, 1)
	end)

	if progress < 1 then return end

	local ok = api.pickup_dropped(tag)

	pcall(function()
		managers.hud:hide_interaction_bar(ok and true or false)
		managers.hud:remove_interact()
	end)

	if ok then
		if alive(tag.col) then tag.col:set_slot(0) end
		if alive(tag.mag) then tag.mag:set_slot(0) end

		api.dropped[tag.key] = nil

		pcall(function() pl:sound():play("pickup_ammo") end)

		api.log("picked up dropped mag")
	end

	cfg.pickup_tag = nil
	cfg.pickup_t = nil
	cfg.pickup_shown = nil
end

local function ensure_hud_hook()
	local TM = rawget(_G, "HUDTeammate")

	if not TM or not TM.set_ammo_amount_by_type or TM.set_ammo_amount_by_type == cfg.hud_hook then return end

	local orig = TM.set_ammo_amount_by_type

	cfg.hud_hook = function(self, wtype, max_clip, current_clip, current_left, max, weapon_panel)
		orig(self, wtype, max_clip, current_clip, current_left, max, weapon_panel)

		local ok, err = pcall(function()
			if self._id ~= HUDManager.PLAYER_PANEL then return end

			local pl = managers.player and managers.player:player_unit()
			local inv = pl and pl:inventory()
			local unit = inv and inv:unit_by_selection(wtype == "primary" and 2 or 1)
			local base = alive(unit) and unit:base() or nil

			if not base then return end

			local count = api.mag_count(base)

			if not count then return end

			local panel = weapon_panel

			if not panel and self._player_panel then
				local weapons = self._player_panel:child("weapons_panel")
				panel = weapons and weapons:child(wtype .. "_weapon_panel")
			end

			local amt = panel and panel:child("ammo_total")

			if not amt then return end

			local zero = count < 10 and "00" or count < 100 and "0" or ""

			amt:set_text(zero .. tostring(count))
			amt:set_font_size(string.len(count) < 4 and 24 or 20)

			pcall(function()
				amt:set_range_color(0, string.len(zero), amt:color():with_alpha(0.5))
			end)
		end)

		if not ok then
			api.log("hud mag count failed: " .. tostring(err))
		end
	end

	TM.set_ammo_amount_by_type = cfg.hud_hook
end

local function install_gameplay_hooks()
	local PS = rawget(_G, "PlayerStandard")

	if not PS or not PS._get_input or cfg.gameplay_installed then return end

	cfg.gameplay_installed = true

	ensure_reload_hook()
	api.ensure_on_reload_hook()
	api.ensure_add_ammo_hook()

	local orig_get_input = PS._get_input

	PS._get_input = function(self, t, dt, paused)
		ensure_reload_hook()
		api.ensure_on_reload_hook()
		api.ensure_add_ammo_hook()
		api.ensure_drop_hook()
		ensure_hud_hook()
		api.install_save_hooks()
		api.ensure_bag_hooks()
		api.ensure_interaction_hooks()

		local base = api.equipped_base()

		if base and not api.skip_weapon(base) and base._nqr_mag_loose == nil then
			api.loose_of(base)
			api.refresh_hud()
		end

		if paused then
			clear_pickup()
		else
			update_pickup(self, t)
		end

		if not paused and cfg.panel_visible and (not rcfg.last_tick_t or rcfg.last_tick_t ~= t) then
			rcfg.last_tick_t = t
			api.tick(dt)

			if cfg.panel_dirty then
				cfg.panel_dirty = false
				api.refresh_panel()
			end
		end

		return orig_get_input(self, t, dt, paused)
	end
end

install_gameplay_hooks()
