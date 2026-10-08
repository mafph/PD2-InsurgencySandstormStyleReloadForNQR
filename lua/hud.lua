-- Sandstorm-HUD: Magazin-Reihen als Kaesten, unten rechts.

local cfg = rawget(_G, "NQR_MAGS")
local api = cfg.api

local BOX_COLOR = Color(0.30, 0.30, 0.30, 0.9)
local FILL_COLOR = Color(0.62, 0.62, 0.62, 0.95)
local BG_COLOR = Color(0, 0, 0, 0.35)
local LINE_COLOR = Color(1, 1, 1, 1)
local FONT = "fonts/font_medium_mf"

local function panel_rows()
	local wep = api.equipped_base()

	if not wep or api.skip_weapon(wep) then return nil end

	local queue, key, pid, caliber, capacity = api.queue_of(wep)

	if not queue then return nil end

	api.sort_queue(queue)

	local installed = wep._nqr_mag_installed or api.new_mag(0)

	installed.rounds = wep:get_ammo_remaining_in_clip()

	return {
		queue = queue,
		key = key,
		caliber = caliber,
		capacity = capacity,
		full = capacity + api.chamber_of(wep),
		installed = installed,
		loose = api.loose_of(wep)
	}
end

local function remove_panel()
	if not cfg.panel then return end

	local hud = managers.hud and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_PD2)

	if hud then
		pcall(function() hud.panel:remove(cfg.panel) end)
	end

	cfg.panel = nil
end

local function build_panel(rows)
	local hud = managers.hud and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_PD2)

	if not hud then return nil end

	local root = hud.panel
	local pw = root:w()
	local ph = root:h()
	local list = { rows.installed }

	for i = 1, #rows.queue do
		list[#list + 1] = rows.queue[i]
	end

	local shown = math.min(#list, cfg.max_boxes)
	local row_w = (cfg.box_w + cfg.box_gap) * cfg.max_boxes + cfg.box_gap
	local head_h = cfg.show_counts and (cfg.font_size + 2) or 0
	local foot_h = cfg.show_counts and (cfg.font_size + 2) or 0
	local panel_h = head_h + cfg.box_h + 6 + foot_h
	local panel = root:panel({
		name = "nqr_mags_panel",
		x = pw - row_w - cfg.pad_right,
		y = ph - panel_h - cfg.pad_bottom,
		w = row_w,
		h = panel_h,
		layer = 10
	})

	panel:rect({
		name = "nqr_mags_bg",
		x = 0,
		y = 0,
		w = row_w,
		h = panel_h,
		layer = 9,
		color = BG_COLOR
	})

	if cfg.show_counts then
		panel:text({
			name = "nqr_mags_header",
			x = 2,
			y = 0,
			w = row_w - 4,
			h = cfg.font_size,
			layer = 11,
			color = LINE_COLOR,
			font = FONT,
			font_size = cfg.font_size,
			text = "MAGS " .. tostring(#rows.queue) .. "    LOSE " .. tostring(rows.loose),
			vertical = "center",
			align = "left"
		})
	end

	for i = 1, shown do
		local mag = list[i]
		local x = cfg.box_gap + (i - 1) * (cfg.box_w + cfg.box_gap)
		local y = head_h
		local max_rounds = (i == 1) and rows.full or rows.capacity
		local ratio = math.max(0, math.min(1, (mag.rounds or 0) / math.max(1, max_rounds)))

		if i == 1 then
			panel:rect({
				name = "nqr_mag_line_" .. i,
				x = x,
				y = y - 3,
				w = cfg.box_w,
				h = 2,
				layer = 12,
				color = LINE_COLOR
			})
		end

		panel:rect({
			name = "nqr_mag_box_" .. i,
			x = x,
			y = y,
			w = cfg.box_w,
			h = cfg.box_h,
			layer = 10,
			color = BOX_COLOR
		})

		if ratio > 0 then
			local fh = math.max(2, (cfg.box_h - 4) * ratio)

			panel:rect({
				name = "nqr_mag_fill_" .. i,
				x = x + 2,
				y = y + cfg.box_h - 2 - fh,
				w = cfg.box_w - 4,
				h = fh,
				layer = 11,
				color = FILL_COLOR
			})
		end
	end

	if cfg.show_counts then
		local text = "NEXT " .. tostring(list[1] and list[1].rounds or 0) .. "/" .. tostring(rows.full)

		if cfg.show_ammo_type then
			text = text .. "    " .. tostring(rows.caliber)
		end

		panel:text({
			name = "nqr_mags_footer",
			x = 2,
			y = head_h + cfg.box_h + 4,
			w = row_w - 4,
			h = cfg.font_size,
			layer = 11,
			color = LINE_COLOR,
			font = FONT,
			font_size = cfg.font_size,
			text = text,
			vertical = "center",
			align = "left"
		})
	end

	return panel
end

local function set_panel(want)
	if want == cfg.panel_visible then return end

	if not want then
		cfg.panel_visible = false
		remove_panel()
		return
	end

	local rows = panel_rows()

	if not rows then return end

	remove_panel()
	cfg.panel = build_panel(rows)
	cfg.panel_visible = cfg.panel ~= nil
end

local function refresh_panel()
	if not cfg.panel_visible then return end

	local rows = panel_rows()

	if not rows then return end

	remove_panel()
	cfg.panel = build_panel(rows)
	cfg.panel_visible = cfg.panel ~= nil
end

cfg.api.set_panel = set_panel
cfg.api.refresh_panel = refresh_panel
