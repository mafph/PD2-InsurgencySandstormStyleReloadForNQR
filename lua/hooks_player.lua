local cfg = rawget(_G, "ISSR")
local rcfg = rawget(_G, "ISSR_RELOAD")
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

local function holster_start(state, t, reason)
	if cfg.holster == reason then return true end
	if cfg.holster then return false end
	if state:_changing_weapon() then return false end

	local pl = api.player_unit()
	local inv = pl and pl:inventory()

	if not inv or not inv.equipped_selection then return false end

	cfg.holster = reason
	state:_start_action_unequip_weapon(t, { selection_wanted = inv:equipped_selection() })

	return true
end

local function holster_release(reason)
	if cfg.holster == reason then
		cfg.holster = nil
	end
end

local function holstered(state, t)
	local expire = state._unequip_weapon_expire_t

	return cfg.holster ~= nil and expire ~= nil and t >= expire
end

local function make_reload_hook(orig)
	return function(self, t, input)
		if not cfg.enabled then
			self._issr_hold_t = nil
			holster_release("refill")

			if cfg.panel_visible then
				api.set_panel(false)
			end

			return orig(self, t, input)
		end

		local held = reload_held(self)
		local wep = api.equipped_base()
		local applicable = wep and not api.skip_weapon(wep)

		if held and applicable then
			if not self._issr_hold_t then
				self._issr_hold_t = t + tap_hold_time()
			end

			if t >= self._issr_hold_t then
				self._issr_held_long = true

				api.set_panel(true)

				local reloading = self._state_data and self._state_data.reload_expire_t

				if not reloading and api.loose_of(wep) > 0 and api.needs_fill(wep) then
					if holster_start(self, t, "refill") and holstered(self, t) then
						api.add_to_job(wep)
					end
				else
					holster_release("refill")
				end
			end

			return false
		end

		holster_release("refill")

		local tap = self._issr_hold_t ~= nil and not self._issr_held_long

		self._issr_hold_t = nil
		self._issr_held_long = nil

		if cfg.panel_visible and not cfg.overlay_always then
			api.set_panel(false)
		end

		if tap then
			return orig(self, t, { btn_reload_press = true })
		end

		return orig(self, t, input)
	end
end

local function make_interupt_hook(orig)
	return function(self, t, ...)
		local wep = api.equipped_base()
		local ret = orig(self, t, ...)

		if cfg.enabled and wep and not api.skip_weapon(wep) then
			api.reload_interrupted(wep)
		end

		return ret
	end
end

local function make_holster_hook(orig)
	return function(self, t, input)
		if cfg.holster and self._unequip_weapon_expire_t then
			return
		end

		return orig(self, t, input)
	end
end

local function make_hud_hook(orig)
	return function(self, wtype, max_clip, current_clip, current_left, max, weapon_panel)
		orig(self, wtype, max_clip, current_clip, current_left, max, weapon_panel)

		pcall(function()
			if self._id ~= HUDManager.PLAYER_PANEL then return end

			local pl = api.player_unit()
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
	end
end

local function install_hooks()
	api.install_weapon_hooks()

	api.wrap("PlayerStandard", "_update_equip_weapon_timers", make_holster_hook)
	api.wrap("PlayerStandard", "_check_action_reload", make_reload_hook)
	api.wrap("PlayerStandard", "_interupt_action_reload", make_interupt_hook)
	api.wrap("HUDTeammate", "set_ammo_amount_by_type", make_hud_hook)
end

local PICKUP_RANGE = 250
local PICKUP_HOLD = 1
local AIM_RADIUS = 50
local mvec_from = Vector3()
local mvec_to = Vector3()
local mvec_dir = Vector3()
local mvec_v = Vector3()
local mvec_closest = Vector3()

local function bar_stop(complete)
	holster_release("pickup")

	if cfg.pickup_bar then
		cfg.pickup_bar = nil
		pcall(function() managers.hud:hide_interaction_bar(complete and true or false) end)
	end
end

local function clear_pickup()
	bar_stop(false)

	if cfg.pickup_shown then
		cfg.pickup_shown = nil
		pcall(function() managers.hud:remove_interact() end)
	end

	cfg.pickup_tag = nil
	cfg.pickup_t = nil
end

local function firearm_in_hand(state, pl)
	local base = api.equipped_base()

	if not base or base.get_ammo_remaining_in_clip == nil or base._blueprint == nil then return false end
	if state._is_meleeing and state:_is_meleeing() then return false end

	local inv = pl and pl:inventory()
	local sel = inv and inv.equipped_selection and inv:equipped_selection()

	return sel == nil or sel == 1 or sel == 2
end

local function find_aimed_tag(pos, rot)
	mvector3.set(mvec_from, pos)
	mvector3.set(mvec_to, rot:y())
	mvector3.multiply(mvec_to, PICKUP_RANGE)
	mvector3.add(mvec_to, mvec_from)

	local ray = World:raycast(mvec_from, mvec_to)
	local hit_dist = ray and mvector3.distance(mvec_from, ray.position) or PICKUP_RANGE
	local tag = ray and ray.unit and alive(ray.unit) and api.dropped[ray.unit:key()] or nil

	if tag then return tag end

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

	return best
end

local function update_pickup(state, t)
	for k, tag in pairs(api.dropped) do
		if not alive(tag.col) then
			api.dropped[k] = nil
		end
	end

	if not cfg.enabled or next(api.dropped) == nil then
		clear_pickup()
		return
	end

	local pl = api.player_unit()
	local cam = pl and pl:camera()
	local pos = cam and cam:position()
	local rot = cam and cam:rotation()

	if not pos or not rot then
		clear_pickup()
		return
	end

	local tag = find_aimed_tag(pos, rot)

	if not tag or not api.can_pickup_dropped(tag) then
		clear_pickup()
		return
	end

	if cfg.pickup_tag ~= tag then
		cfg.pickup_tag = tag
		cfg.pickup_shown = true

		pcall(function()
			managers.hud:show_interact({
				text = managers.localization:btn_macro("interact", false) .. " " .. api.L("issr_pickup", "Magazin aufheben")
			})
		end)
	end

	local ctrl = state._controller
	local held = ctrl and ctrl.get_input_bool and ctrl:get_input_bool("interact")

	if not held then
		if cfg.pickup_t or cfg.holster == "pickup" then
			bar_stop(false)
			cfg.pickup_t = nil
			cfg.pickup_tag = nil
		end

		return
	end

	if not cfg.pickup_t then
		local in_hand = firearm_in_hand(state, pl) and state._unequip_weapon_expire_t == nil
		local need_holster = cfg.holster == "pickup" or in_hand

		if need_holster and (not holster_start(state, t, "pickup") or not holstered(state, t)) then return end

		cfg.pickup_t = t
		cfg.pickup_bar = true
		managers.hud:show_interaction_bar(0, PICKUP_HOLD)
	end

	local progress = math.min(1, (t - cfg.pickup_t) / PICKUP_HOLD)

	managers.hud:set_interaction_bar_width(progress * PICKUP_HOLD, PICKUP_HOLD)

	if progress < 1 then return end

	local ok = api.pickup_dropped(tag)

	bar_stop(ok)
	pcall(function() managers.hud:remove_interact() end)

	if ok then
		if alive(tag.col) then tag.col:set_slot(0) end
		if alive(tag.mag) then tag.mag:set_slot(0) end

		api.dropped[tag.key] = nil

		pcall(function() pl:sound():play("pickup_ammo") end)
	end

	cfg.pickup_tag = nil
	cfg.pickup_t = nil
	cfg.pickup_shown = nil
end

local function prepare_weapon(base)
	if base._issr_mag_loose == nil then
		api.loose_of(base)
		api.refresh_hud()
	end

	if base.set_ammo_max then
		local want = api.max_total(base)

		if want and base:get_ammo_max() ~= want then
			base:set_ammo_max(want)
		end
	end
end

local function install_gameplay_hooks()
	local PS = rawget(_G, "PlayerStandard")

	if not PS or not PS._get_input or cfg.gameplay_installed then return end

	cfg.gameplay_installed = true

	install_hooks()

	local orig_get_input = PS._get_input

	PS._get_input = function(self, t, dt, paused)
		install_hooks()

		local before = api.equipped_base()

		if before and not api.skip_weapon(before) then
			prepare_weapon(before)
		end

		local input = orig_get_input(self, t, dt, paused)

		local base = api.equipped_base()
		local applicable = base ~= nil and not api.skip_weapon(base)

		if cfg.overlay_always and cfg.enabled then
			local want = not paused and applicable

			if want ~= (cfg.panel_visible and true or false) then
				api.set_panel(want)
			end
		end

		if cfg.holster == "refill" and not reload_held(self) then
			holster_release("refill")
		end

		if paused then
			clear_pickup()
		else
			update_pickup(self, t)
		end

		if not paused and cfg.panel_visible and (not rcfg.last_tick_t or rcfg.last_tick_t ~= t) then
			rcfg.last_tick_t = t

			if cfg.holster == "refill" and holstered(self, t) then
				api.tick(dt)
			end

			if applicable then
				local clip = base:get_ammo_remaining_in_clip()

				if clip ~= cfg.last_clip then
					cfg.last_clip = clip
					cfg.panel_dirty = true
				end
			end

			if cfg.panel_dirty then
				cfg.panel_dirty = false
				api.refresh_panel()
			end
		end

		return input
	end
end

install_gameplay_hooks()
