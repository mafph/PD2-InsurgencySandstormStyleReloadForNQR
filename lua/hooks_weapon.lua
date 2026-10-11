local cfg = rawget(_G, "NQR_MAGS")
local rcfg = rawget(_G, "NQR_MAGFILL")
local api = cfg.api

local function make_on_reload_hook(orig)
	local function hook(self, ...)
		if api.skip_weapon(self) then
			return orig(self, ...)
		end

		local queue = api.queue_of(self)

		if not queue then
			return orig(self, ...)
		end

		api.loose_of(self)

		local chamber = api.chamber_of(self)
		local kept = math.max(0, math.min(chamber, self:get_ammo_remaining_in_clip()))

		local drops = self._nqr_drop_count or 0
		local clip = self:get_ammo_remaining_in_clip()

		self._nqr_drop_count = 0

		local gone = self._nqr_mag_gone

		self._nqr_mag_gone = nil

		if drops < 1 and not gone then
			local old_mag = self._nqr_mag_installed
			local actual = self._nqr_mag_left_rounds

			if actual == nil then
				actual = math.max(0, clip - chamber)
			end

			if not old_mag then
				old_mag = api.new_mag(actual)
			else
				old_mag.rounds = actual
			end

			queue[#queue + 1] = old_mag
		end

		self._nqr_mag_left_rounds = nil

		api.sort_queue(queue)

		local next_mag = table.remove(queue, 1)

		self._nqr_mag_installed = next_mag or api.new_mag(0)
		self._nqr_no_mag = nil

		local installed = self._nqr_mag_installed
		local total = (installed.rounds or 0) + kept

		self:set_ammo_total(total)

		local ret = orig(self, ...)

		installed.rounds = math.max(0, self:get_ammo_remaining_in_clip() - chamber)

		api.sync_total(self)

		cfg.panel_dirty = true

		return ret
	end

	return hook
end

local function make_drop_hook(orig)
	local function hook(self, ...)
		if api.skip_weapon(self) then
			return orig(self, ...)
		end

		local mags = managers.enemy and managers.enemy._magazines
		local before = mags and #mags or 0
		local ret = orig(self, ...)

		if mags then
			local rounds = math.max(self:get_ammo_remaining_in_clip() - api.chamber_of(self), 0)
			local queue, key, pid, caliber = api.queue_of(self)

			if queue and key then
				for i = before + 1, #mags do
					local entry = mags[i]
					local col_unit = entry[2]

					if alive(col_unit) then
						col_unit:set_scale(Vector3(3, 3, 3))

						api.dropped[col_unit:key()] = {
							key = col_unit:key(),
							col = col_unit,
							mag = entry[1],
							rounds = rounds,
							queue_key = key,
							pid = pid,
							caliber = caliber,
							name_id = self._name_id
						}

						self._nqr_drop_count = (self._nqr_drop_count or 0) + 1

						cfg.panel_dirty = true
					end
				end
			end
		end

		return ret
	end

	return hook
end

local function make_stage_hook(orig)
	return function(self, t)
		local ret = orig(self, t)

		if not cfg.enabled or api.skip_weapon(self) then return ret end

		local cycle = self.r_cycle
		local stage = self.r_stage
		local name = cycle and stage and cycle[stage] or nil

		if name ~= self._nqr_mags_stage then
			self._nqr_mags_stage = name

			if name == "r_mag_out" then
				api.mag_left(self)
			elseif name == "r_get_new_mag_in" then
				api.mag_entered(self)
			end
		end

		return ret
	end
end

local function make_can_reload_hook(orig)
	return function(self, ...)
		if cfg.enabled and not api.skip_weapon(self) then
			api.sync_total(self)
		end

		return orig(self, ...)
	end
end

local function make_add_ammo_hook(orig)
	return function(self, ratio, add_amount_override)
		if api.skip_weapon(self) then
			return orig(self, ratio, add_amount_override)
		end

		local add_amount = add_amount_override

		if not add_amount then
			local pickup = self._ammo_pickup

			if pickup then
				add_amount = pickup[1] + (pickup[2] - pickup[1]) * math.random()
				add_amount = math.floor(add_amount + 0.5)
			else
				add_amount = 0
			end
		end

		add_amount = math.floor(add_amount * (ratio or 1))

		if add_amount <= 0 then
			return false, 0
		end

		local room = math.max(0, self:get_ammo_max() - self:get_ammo_total())

		if add_amount > room then
			add_amount = room
		end

		if add_amount <= 0 then
			api.sync_total(self)
			return false, 0
		end

		api.set_loose(self, api.loose_of(self) + add_amount)
		api.sync_total(self)
		cfg.panel_dirty = true

		return true, add_amount
	end
end

local function make_bag_hook(orig)
	return function(self, available, special)
		if not rcfg.enabled or api.skip_weapon(self) then
			return orig(self, available, special)
		end

		api.sync_total(self)

		local before = self:get_ammo_total()
		local ret = orig(self, available, special)
		local added = self:get_ammo_total() - before

		if added > 0 then
			local left = api.fill_mags(self, added + api.loose_of(self))

			api.set_loose(self, left)
			api.sync_total(self)
			cfg.panel_dirty = true
			api.refresh_hud()
		end

		return ret
	end
end

local function make_need_ammo_hook(orig)
	return function(self)
		if orig(self) then
			return true
		end

		if rcfg.enabled and rcfg.unblock_bag then
			local player = api.player_unit()

			if player and player:inventory() == self and api.magazines_need_fill(player) then
				return true
			end
		end

		return false
	end
end

local function install_weapon_hooks()
	api.wrap("NewRaycastWeaponBase", "can_reload", make_can_reload_hook)
	api.wrap("NewRaycastWeaponBase", "on_reload", make_on_reload_hook)
	api.wrap("NewRaycastWeaponBase", "update_r_stage", make_stage_hook)
	api.wrap("NewRaycastWeaponBase", "drop_magazine_object", make_drop_hook)
	api.wrap("RaycastWeaponBase", "add_ammo", make_add_ammo_hook)
	api.wrap("RaycastWeaponBase", "add_ammo_from_bag", make_bag_hook)
	api.wrap("PlayerInventory", "need_ammo", make_need_ammo_hook)
end

api.install_weapon_hooks = install_weapon_hooks

install_weapon_hooks()
