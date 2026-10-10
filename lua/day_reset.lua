-- Neuer Tag (jeder Level-Start): Magazin-Lager und liegende Magazine zuruecksetzen.

-- cfg wird erst im Callback gelesen: dieser Hook kann vor main.lua geladen werden.
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

	if c.api and c.api.log then
		c.api.log("new day: mag store reset")
	end
end)
