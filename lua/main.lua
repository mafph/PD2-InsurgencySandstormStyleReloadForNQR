local dir = rawget(_G, "ModPath")

if type(dir) ~= "string" or dir == "" then
	local src = debug.getinfo(1, "S").source
	dir = (src:sub(1, 1) == "@" and src:sub(2):match("^(.*[/\\])")) or ""
end

if dir ~= "" and not dir:match("[/\\]$") then
	dir = dir .. "/"
end

local function report(name, err)
	local out = "[issr] " .. name .. " failed: " .. tostring(err)

	if _G.log then
		_G.log(out)
	else
		print(out)
	end
end

local function load_part(name)
	local ok, err = pcall(dofile, dir .. "lua/" .. name .. ".lua")

	if not ok then
		report(name, err)
	end

	return ok
end

local cfg = rawget(_G, "ISSR")

if not (cfg and cfg.api) then
	if not load_part("state") then return end
end

for _, name in ipairs({ "hud", "hooks_weapon", "hooks_player" }) do
	load_part(name)
end
