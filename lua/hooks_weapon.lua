-- Waffen-Hooks: Nachladen (Kammer+1), Loot, Ammo-Bag, Bag-Interaktion.

local cfg = rawget(_G, "NQR_MAGS")
local rcfg = rawget(_G, "NQR_MAGFILL")
local api = cfg.api
local dbg = api.log
local rdbg = rcfg.api.log

local function make_on_reload_hook(orig)
	local function hook(self, ...)
		if api.skip_weapon(self) then
			return orig(self, ...)
		end

		local queue, _, _, _, capacity = api.queue_of(self)

		if not queue then
			return orig(self, ...)
		end

		api.loose_of(self)

		local drops = self._nqr_drop_count or 0

		self._nqr_drop_count = 0

		local chamber = api.chamber_of(self)
		local clip = self:get_ammo_remaining_in_clip()
		local kept = math.max(0, math.min(chamber, clip))

		dbg("reload: clip=" .. tostring(clip) .. " chamber=" .. tostring(chamber) .. " drops=" .. tostring(drops)
			.. " loose=" .. tostring(api.loose_of(self)) .. " queue=" .. tostring(#queue))

		if drops < 1 then
			local old_mag = self._nqr_mag_installed
			local actual = math.max(0, clip - chamber)

			if not old_mag then
				old_mag = api.new_mag(actual)
				dbg("reload: no installed mag recorded, created rounds=" .. tostring(actual))
			else
				-- .rounds wird nur beim Einsetzen/HUD aktualisiert: nach Schuessen ist der Wert veraltet.
				if (old_mag.rounds or 0) ~= actual then
					dbg("reload: stale mag rounds " .. tostring(old_mag.rounds) .. " -> " .. tostring(actual)
						.. " (clip=" .. tostring(clip) .. " chamber=" .. tostring(chamber) .. ")")
				end

				old_mag.rounds = actual
			end

			queue[#queue + 1] = old_mag
		end

		api.sort_queue(queue)

		local next_mag = table.remove(queue, 1)

		self._nqr_mag_installed = next_mag or api.new_mag(0)

		local total = (next_mag and next_mag.rounds or 0) + kept

		self:set_ammo_total(total)

		local ret = orig(self, ...)

		self._nqr_mag_installed.rounds = math.max(0, self:get_ammo_remaining_in_clip() - chamber)

		api.sync_total(self)

		cfg.panel_dirty = true

		dbg("loaded " .. tostring(self._nqr_mag_installed.rounds) .. "/" .. tostring(capacity + chamber)
			.. " chamber=" .. tostring(chamber) .. " queue=" .. tostring(#queue)
			.. " loose=" .. tostring(api.loose_of(self)))

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

						dbg("dropped mag rounds=" .. tostring(rounds) .. " key=" .. tostring(key))
					end
				end
			end
		end

		return ret
	end

	return hook
end

local function ensure_drop_hook()
	local cls = rawget(_G, "NewRaycastWeaponBase")

	if not cls or not cls.drop_magazine_object then return end
	if cls.drop_magazine_object == cfg.drop_hook then return end

	cfg.drop_hook = make_drop_hook(cls.drop_magazine_object)
	cls.drop_magazine_object = cfg.drop_hook
end

local function ensure_on_reload_hook()
	local cls = rawget(_G, "NewRaycastWeaponBase")

	if not cls or not cls.on_reload then return end
	if cls.on_reload == cfg.on_reload_hook then return end

	cfg.on_reload_hook = make_on_reload_hook(cls.on_reload)
	cls.on_reload = cfg.on_reload_hook
end

local function ensure_can_reload_hook()
	local cls = rawget(_G, "NewRaycastWeaponBase")

	if not cls or not cls.can_reload then return end
	if cls.can_reload == cfg.can_reload_hook then return end

	local orig = cls.can_reload

	cfg.can_reload_hook = function(self, ...)
		if cfg.enabled and not api.skip_weapon(self) then
			api.sync_total(self)
		end

		return orig(self, ...)
	end

	cls.can_reload = cfg.can_reload_hook
end

local function ensure_add_ammo_hook()
	local cls = rawget(_G, "RaycastWeaponBase")

	if not cls or not cls.add_ammo then return end
	if cls.add_ammo == cfg.add_ammo_hook then return end

	local orig = cls.add_ammo

	cfg.add_ammo_hook = function(self, ratio, add_amount_override)
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

		-- Obergrenze ist ammo_max der Waffe (wird in hooks_player gesetzt)
		local room = math.max(0, self:get_ammo_max() - self:get_ammo_total())

		if add_amount > room then
			dbg("loot " .. tostring(add_amount) .. " capped to " .. tostring(room) .. " (ammo_max " .. tostring(self:get_ammo_max()) .. ")")
			add_amount = room
		end

		if add_amount <= 0 then
			api.sync_total(self)
			return false, 0
		end

		api.set_loose(self, api.loose_of(self) + add_amount)
		api.sync_total(self)
		cfg.panel_dirty = true

		dbg("loot " .. tostring(add_amount) .. " -> loose " .. tostring(api.loose_of(self))
			.. " on " .. tostring(self._name_id))

		return true, add_amount
	end

	cls.add_ammo = cfg.add_ammo_hook
end

local function ensure_bag_hooks()
	local cls = rawget(_G, "RaycastWeaponBase")

	if not cls or not cls.add_ammo_from_bag then return end
	if cls.add_ammo_from_bag == rcfg.bag_hook then return end

	local orig_add_ammo_from_bag = cls.add_ammo_from_bag

	local function hook(self, available, special)
		if not rcfg.enabled or api.skip_weapon(self) then
			return orig_add_ammo_from_bag(self, available, special)
		end

		api.sync_total(self)

		local before = self:get_ammo_total()
		local ret = orig_add_ammo_from_bag(self, available, special)
		local added = self:get_ammo_total() - before

		if added > 0 then
			api.set_loose(self, api.loose_of(self) + added)
			api.sync_total(self)

			rdbg("bag gave " .. tostring(added) .. " to " .. tostring(self._name_id)
				.. " loose=" .. tostring(api.loose_of(self)))
		end

		return ret
	end

	rcfg.bag_hook = hook
	cls.add_ammo_from_bag = hook
end

local function ensure_need_ammo_hook()
	local cls = rawget(_G, "PlayerInventory")

	if not cls or not cls.need_ammo then return end
	if cls.need_ammo == rcfg.need_ammo_hook then return end

	local orig = cls.need_ammo

	rcfg.need_ammo_hook = function(self)
		if orig(self) then
			return true
		end

		if rcfg.enabled and rcfg.unblock_bag then
			local player = managers.player and managers.player:player_unit()

			if player and player:inventory() == self and api.magazines_need_fill(player) then
				return true
			end
		end

		return false
	end

	cls.need_ammo = rcfg.need_ammo_hook
end

local function install_weapon_hooks()
	ensure_can_reload_hook()
	ensure_on_reload_hook()
	ensure_add_ammo_hook()
	ensure_drop_hook()
	ensure_bag_hooks()
	ensure_need_ammo_hook()
end

cfg.api.ensure_on_reload_hook = ensure_on_reload_hook
cfg.api.ensure_add_ammo_hook = ensure_add_ammo_hook
cfg.api.ensure_drop_hook = ensure_drop_hook
cfg.api.ensure_bag_hooks = ensure_bag_hooks
cfg.api.ensure_need_ammo_hook = ensure_need_ammo_hook

install_weapon_hooks()
