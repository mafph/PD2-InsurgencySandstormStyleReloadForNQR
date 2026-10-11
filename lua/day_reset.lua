if not GameSetup or rawget(_G, "NQR_MAGS_DAY_RESET") then return end

_G.NQR_MAGS_DAY_RESET = true

Hooks:PostHook(GameSetup, "init_finalize", "NQR_MAGS_day_reset", function()
	local c = rawget(_G, "NQR_MAGS")

	if not c then return end

	c.mags = {}
	c.holster = nil
	c.pickup_tag = nil
	c.pickup_t = nil

	for k in pairs(c.dropped or {}) do
		c.dropped[k] = nil
	end
end)
