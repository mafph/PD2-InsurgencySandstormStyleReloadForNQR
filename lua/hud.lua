local cfg = rawget(_G, "ISSR")
local api = cfg.api

local BOX_COLOR = Color(0.30, 0.30, 0.30, 0.9)
local FILL_COLOR = Color(0.62, 0.62, 0.62, 0.95)
local BG_COLOR = Color(0, 0, 0, 0.35)
local LINE_COLOR = Color(1, 1, 1, 1)
local FONT = "fonts/font_medium_mf"

local BOX_W = 20
local BOX_H = 28
local BOX_GAP = 4

local function collect_rows()
	local wep = api.equipped_base()

	if not wep or api.skip_weapon(wep) then return nil end

	local queue, _, _, caliber, capacity = api.queue_of(wep)

	if not queue then return nil end

	api.sort_queue(queue)

	local installed = wep._issr_mag_installed or api.new_mag(0)

	installed.rounds = math.max(0, wep:get_ammo_remaining_in_clip() - api.chamber_of(wep))

	return {
		queue = queue,
		caliber = caliber,
		capacity = capacity,
		installed = installed,
		no_mag = wep._issr_no_mag and true or false,
		loose = api.loose_of(wep)
	}
end

local function hud_panel()
	local hud = managers.hud and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_PD2)

	return hud and hud.panel
end

local function remove_panel()
	if not cfg.panel then return end

	local root = hud_panel()

	if root then
		pcall(function() root:remove(cfg.panel) end)
	end

	cfg.panel = nil
end

local function add_text(panel, name, x, y, w, h, size, text, align)
	panel:text({
		name = name,
		x = x,
		y = y,
		w = w,
		h = h,
		layer = 11,
		color = LINE_COLOR,
		font = FONT,
		font_size = size,
		text = text,
		vertical = "center",
		align = align or "left"
	})
end

local function draw_header(panel, rows, row_w)
	local parts = {}

	if cfg.show_mags then
		parts[#parts + 1] = api.L("issr_hud_mags", "MAGS") .. " " .. tostring(#rows.queue)
	end

	if cfg.show_loose then
		parts[#parts + 1] = api.L("issr_hud_loose", "LOSE") .. " " .. tostring(rows.loose)
	end

	add_text(panel, "issr_header", 2, 0, row_w - 4, cfg.font_size, cfg.font_size, table.concat(parts, "    "))
end

local function draw_no_mag(panel, x, y)
	local dash, gap, t = 4, 3, 2

	local function dashes(name, x0, y0, len, horizontal)
		local pos, n = 0, 0

		while pos < len do
			local l = math.min(dash, len - pos)

			panel:rect({
				name = name .. n,
				x = horizontal and (x0 + pos) or x0,
				y = horizontal and y0 or (y0 + pos),
				w = horizontal and l or t,
				h = horizontal and t or l,
				layer = 11,
				color = LINE_COLOR
			})

			pos = pos + dash + gap
			n = n + 1
		end
	end

	dashes("issr_mag_dash_t", x, y, BOX_W, true)
	dashes("issr_mag_dash_b", x, y + BOX_H - t, BOX_W, true)
	dashes("issr_mag_dash_l", x, y, BOX_H, false)
	dashes("issr_mag_dash_r", x + BOX_W - t, y, BOX_H, false)

	panel:text({
		name = "issr_mag_x",
		x = x,
		y = y,
		w = BOX_W,
		h = BOX_H,
		layer = 13,
		color = LINE_COLOR,
		font = FONT,
		font_size = math.min(cfg.font_size, BOX_H),
		text = "X",
		vertical = "center",
		align = "center"
	})
end

local function draw_mag(panel, index, mag, x, y, capacity)
	local ratio = math.max(0, math.min(1, (mag.rounds or 0) / math.max(1, capacity)))

	panel:rect({
		name = "issr_mag_box_" .. index,
		x = x,
		y = y,
		w = BOX_W,
		h = BOX_H,
		layer = 10,
		color = BOX_COLOR
	})

	if ratio > 0 then
		local fh = math.max(2, (BOX_H - 4) * ratio)

		panel:rect({
			name = "issr_mag_fill_" .. index,
			x = x + 2,
			y = y + BOX_H - 2 - fh,
			w = BOX_W - 4,
			h = fh,
			layer = 11,
			color = FILL_COLOR
		})
	end
end

local function draw_footer(panel, rows, first, row_w, y)
	local text

	if cfg.show_mags then
		if rows.no_mag then
			text = api.L("issr_hud_no_mag", "KEIN MAG")
		else
			text = api.L("issr_hud_next", "NEXT") .. " " .. tostring(first and first.rounds or 0) .. "/" .. tostring(rows.capacity)
		end

		if cfg.show_ammo_type then
			text = text .. "    " .. tostring(rows.caliber)
		end
	else
		text = tostring(rows.caliber)
	end

	add_text(panel, "issr_footer", 2, y, row_w - 4, cfg.font_size, cfg.font_size, text)
end

local function build_panel(rows)
	local root = hud_panel()

	if not root then return nil end

	local list = { rows.installed }

	for i = 1, #rows.queue do
		list[#list + 1] = rows.queue[i]
	end

	local shown = math.min(#list, cfg.max_boxes)
	local row_w = (BOX_W + BOX_GAP) * cfg.max_boxes + BOX_GAP
	local header_on = cfg.show_mags or cfg.show_loose
	local foot_on = cfg.show_mags or cfg.show_ammo_type
	local head_h = header_on and (cfg.font_size + 2) or 0
	local foot_h = foot_on and (cfg.font_size + 2) or 0
	local panel_h = head_h + BOX_H + 6 + foot_h
	local panel = root:panel({
		name = "issr_panel",
		x = root:w() - row_w - cfg.pad_right,
		y = root:h() - panel_h - cfg.pad_bottom,
		w = row_w,
		h = panel_h,
		layer = 10
	})

	panel:rect({
		name = "issr_bg",
		x = 0,
		y = 0,
		w = row_w,
		h = panel_h,
		layer = 9,
		color = BG_COLOR
	})

	if header_on then
		draw_header(panel, rows, row_w)
	end

	for i = 1, shown do
		local x = BOX_GAP + (i - 1) * (BOX_W + BOX_GAP)

		if i == 1 then
			panel:rect({
				name = "issr_mag_line_1",
				x = x,
				y = head_h - 3,
				w = BOX_W,
				h = 2,
				layer = 12,
				color = LINE_COLOR
			})
		end

		if i == 1 and rows.no_mag then
			draw_no_mag(panel, x, head_h)
		else
			draw_mag(panel, i, list[i], x, head_h, rows.capacity)
		end
	end

	if cfg.show_more and #list > shown then
		local x = BOX_GAP + (shown - 1) * (BOX_W + BOX_GAP)

		panel:text({
			name = "issr_more",
			x = x,
			y = head_h,
			w = BOX_W,
			h = BOX_H,
			layer = 13,
			color = LINE_COLOR,
			font = FONT,
			font_size = math.min(cfg.font_size, 14),
			text = "+" .. tostring(#list - shown),
			vertical = "center",
			align = "center"
		})
	end

	if foot_on then
		draw_footer(panel, rows, list[1], row_w, head_h + BOX_H + 4)
	end

	return panel
end

local function rebuild_panel(rows)
	remove_panel()
	cfg.panel = build_panel(rows)
	cfg.panel_visible = cfg.panel ~= nil
end

local function set_panel(want)
	if want == cfg.panel_visible then return end

	if not want then
		cfg.panel_visible = false
		remove_panel()
		return
	end

	local rows = collect_rows()

	if not rows then return end

	rebuild_panel(rows)
end

local function refresh_panel()
	if not cfg.panel_visible then return end

	local rows = collect_rows()

	if not rows then return end

	rebuild_panel(rows)
end

cfg.api.set_panel = set_panel
cfg.api.refresh_panel = refresh_panel
