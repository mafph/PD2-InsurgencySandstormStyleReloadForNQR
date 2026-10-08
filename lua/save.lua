-- Speicherstand: Magazin-Queue im Savegame-Cache sichern.

local cfg = rawget(_G, "NQR_MAGS")
local dbg = cfg.api.log

local function install_save_hooks()
	if cfg.save_hooks_installed then return end
	if not SavefileManager or not SavefileManager._set_cache or not SavefileManager._load_cache then return end

	cfg.save_hooks_installed = true

	local orig_set_cache = SavefileManager._set_cache

	SavefileManager._set_cache = function(self, slot, cache, force)
		if type(cache) == "table" and slot ~= self.SETTING_SLOT then
			cache.nqr_mags = cfg.mags
		end

		return orig_set_cache(self, slot, cache, force)
	end

	local orig_load_cache = SavefileManager._load_cache

	SavefileManager._load_cache = function(self, slot)
		if slot ~= self.SETTING_SLOT then
			local ok, meta_data = pcall(function() return self:_meta_data(slot) end)
			local data = ok and meta_data and type(meta_data.cache) == "table" and meta_data.cache.nqr_mags

			if type(data) == "table" then
				cfg.mags = data

				local count = 0

				for _ in pairs(cfg.mags) do
					count = count + 1
				end

				dbg("loaded mag store, keys=" .. tostring(count))
			end
		end

		return orig_load_cache(self, slot)
	end
end

cfg.api.install_save_hooks = install_save_hooks

install_save_hooks()
