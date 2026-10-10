-- Einstieg: laedt die Teildateien in Lesereihenfolge.

local dir = rawget(_G, "ModPath")

if type(dir) ~= "string" or dir == "" then
	local src = debug.getinfo(1, "S").source
	dir = (src:sub(1, 1) == "@" and src:sub(2):match("^(.*[/\\])")) or ""
end

if dir ~= "" and not dir:match("[/\\]$") then
	dir = dir .. "/"
end

local PARTS = {
	"state",
	"hud",
	"hooks_weapon",
	"hooks_player",
	"menu"
}

for i = 1, #PARTS do
	local name = "lua/" .. PARTS[i] .. ".lua"
	local ok, err = pcall(dofile, dir .. name)

	if not ok then
		local out = "[nqr_mags] " .. name .. " failed: " .. tostring(err)

		if _G.log then
			_G.log(out)
		else
			print(out)
		end
	end
end
