--[[
Glyph Timer Script for Dota 2 (Lua 5.4).

Displays dynamic duration timer progress bars over entities (creeps and structures) 
currently affected by the Fortification Glyph modifier. Supports spatial clustering, 
custom visual styles, team filtering, and custom font rendering.
--]]

local script = {}

-- Constant definitions
local GLYPH_MODIFIER = "modifier_fountain_glyph"
local DEFAULT_DURATION = 5.0
local FONT_NAMES = { "Arial", "Verdana", "Tahoma", "MuseoSansEx" }

--- Appends a non-breaking space character to a menu label string.
--
--  Args:
--      s (string): The original menu label string.
--
--  Returns:
--      string: The menu label string appended with standard unicode non-breaking space.
local function en(s) return s .. "\u{A0}" end

-- ============================================================================
-- UI Menu Construction
-- ============================================================================

local tab = Menu.Create("General", "Main", "Glyph Timer")
tab:Icon("\u{f017}")

local general_group = tab:Create(en("General")):Create(en("Settings"))
local targets_group = tab:Create(en("Targets")):Create(en("Filter"))
local style_group   = tab:Create(en("Style")):Create(en("Bar"))
local colors_group  = tab:Create(en("Colors")):Create(en("Colors"))

local ui = {}

-- General settings
ui.enabled                  = general_group:Switch(en("Enabled"), true, "\u{f00c}")
ui.cluster                  = general_group:Switch(en("Cluster Nearby"), true)
ui.cluster_radius_creeps    = general_group:Slider(en("Cluster Radius (Creeps)"), 0, 400, 90)
ui.cluster_radius_buildings = general_group:Slider(en("Cluster Radius (Buildings)"), 0, 400, 0)
ui.show_count               = general_group:Switch(en("Show Count"), true)

-- Target filters
ui.show_creeps    = targets_group:Switch(en("Creeps"), true)
ui.show_buildings = targets_group:Switch(en("Buildings"), true)
ui.show_allies    = targets_group:Switch(en("Allies"), true)
ui.show_enemies   = targets_group:Switch(en("Enemies"), true)

-- Bar styling settings
ui.bar_width   = style_group:Slider(en("Bar Width"), 24, 200, 64)
ui.bar_height  = style_group:Slider(en("Bar Height"), 8, 40, 18)
ui.rounding    = style_group:Slider(en("Rounding"), 0, 20, 6)
ui.offset      = style_group:Slider(en("Height Offset"), -150, 400, 50)
ui.font_size   = style_group:Slider(en("Font Size"), 8, 40, 14)
ui.decimals    = style_group:Switch(en("Decimal Seconds"), false)
ui.show_number = style_group:Switch(en("Show Number"), true)
ui.show_shadow = style_group:Switch(en("Shadow"), true)

ui.glow_style = style_group:Switch(en("Glow Style"), false)
ui.outer_glow = style_group:Switch(en("Outer Glow"), true)

-- Font selection menu initializer
ui.font_index = nil
do
    local ok, combo = pcall(function()
        return style_group:Combo(en("Font"), FONT_NAMES, 0)
    end)
    if ok then ui.font_index = combo end
end

-- Color scheme setup
ui.color_bg     = colors_group:ColorPicker(en("Background"), Color(20, 20, 20, 200))
ui.color_fill   = colors_group:ColorPicker(en("Fill"), Color(76, 175, 80, 255))
ui.color_text   = colors_group:ColorPicker(en("Text"), Color(255, 255, 255, 255))
ui.color_border = colors_group:ColorPicker(en("Border Color"), Color(150, 165, 200, 80))
ui.color_glow   = colors_group:ColorPicker(en("Glow Color"), Color(120, 150, 220, 90))

-- Load system font handles
local FONT_FLAGS = Enum.FontCreate.FONTFLAG_ANTIALIAS
local fonts = {}
for i, name in ipairs(FONT_NAMES) do
    fonts[i] = Render.LoadFont(name, FONT_FLAGS, 500)
end

--- Retrieves the active font object based on current UI combo selection.
--
--  Returns:
--      Font: The loaded font object to use for rendering text.
local function get_font()
    local idx = 1
    if ui.font_index then
        idx = (ui.font_index:Get() or 0) + 1
    end
    if idx < 1 then idx = 1 end
    if idx > #fonts then idx = #fonts end
    return fonts[idx] or fonts[1]
end

-- Cache standard math utilities
local ceil  = math.ceil
local min   = math.min
local floor = math.floor

-- ============================================================================
-- Low-level Render Helpers
-- ============================================================================

--- Draws a solid filled rectangle.
--
--  Args:
--      a (Vec2): Top-left screen coordinate.
--      b (Vec2): Bottom-right screen coordinate.
--      color (Color): Fill RGBA color.
--      round (number): Corner rounding radius in pixels.
local function filled_rect(a, b, color, round)
    Render.FilledRect(a, b, color, round)
end

--- Draws an outlined rectangle frame.
--
--  Args:
--      a (Vec2): Top-left screen coordinate.
--      b (Vec2): Bottom-right screen coordinate.
--      color (Color): Border RGBA color.
--      round (number): Corner rounding radius in pixels.
--      thickness (number|nil): Line border thickness in pixels. Defaults to 1.
local function rect_outline(a, b, color, round, thickness)
    Render.Rect(a, b, color, round, 0, thickness or 1)
end

-- ============================================================================
-- Entity Inspection Functions
-- ============================================================================

--- Searches for and returns the active glyph modifier handle on a target unit.
--
--  Args:
--      unit (Entity): Target game entity to inspect.
--
--  Returns:
--      Modifier|nil: Active glyph modifier instance if present, nil otherwise.
local function get_glyph_modifier(unit)
    local mods = NPC.GetModifiers(unit)
    if not mods then return nil end
    for _, mod in pairs(mods) do
        if Modifier.GetName(mod) == GLYPH_MODIFIER then
            return mod
        end
    end
    return nil
end

--- Calculates the remaining time and total duration of a glyph modifier.
--
--  Args:
--      mod (Modifier): Active glyph modifier object.
--
--  Returns:
--      number: Remaining active time in seconds.
--      number: Total active modifier duration in seconds.
local function get_remaining(mod)
    local duration = Modifier.GetDuration(mod)
    if not duration or duration <= 0 then duration = DEFAULT_DURATION end

    local remaining = Modifier.GetDieTime(mod) - GameRules.GetGameTime()
    if remaining < 0 then remaining = 0 end
    if remaining > duration then duration = remaining end
    return remaining, duration
end

--- Checks if a given unit entity is classified as a building or structure.
--
--  Args:
--      unit (Entity): Target game entity to check.
--
--  Returns:
--      boolean: True if the unit is a structure, tower, or barracks.
local function is_building(unit)
    return NPC.IsStructure(unit) or NPC.IsTower(unit) or NPC.IsBarracks(unit)
end

--- Fetches the team ID integer associated with the local player hero.
--
--  Returns:
--      number|nil: Team number index or nil if unavailable.
local function get_local_team()
    local hero = Heroes.GetLocal()
    if hero and Entity.GetTeamNum then
        return Entity.GetTeamNum(hero)
    end
    return nil
end

-- ============================================================================
-- Rendering Pipeline
-- ============================================================================

--- Renders a standard styled progress bar.
--
--  Args:
--      center_x (number): Horizontal center point on screen.
--      top_y (number): Vertical top edge position on screen.
--      frac (number): Normalized progress fraction between 0.0 and 1.0.
--      text (string|nil): Optional formatted timer text overlay.
local function draw_bar(center_x, top_y, frac, text)
    local width  = ui.bar_width:Get()
    local height = ui.bar_height:Get()
    local round  = ui.rounding:Get()

    local half = width / 2
    local x1, y1 = center_x - half, top_y
    local x2, y2 = center_x + half, top_y + height

    -- Optional background drop shadow
    if ui.show_shadow:Get() then
        local s = 3
        filled_rect(Vec2(x1, y1 + s), Vec2(x2, y2 + s), Color(0, 0, 0, 120), round)
    end

    -- Draw background frame
    filled_rect(Vec2(x1, y1), Vec2(x2, y2), ui.color_bg:Get(), round)

    -- Draw progress fill
    local fill_w = width * frac
    if fill_w > 0 then
        local fill_round = min(round, fill_w / 2)
        filled_rect(Vec2(x1, y1), Vec2(x1 + fill_w, y2), ui.color_fill:Get(), fill_round)
    end

    -- Overlay centered text label
    if ui.show_number:Get() and text then
        local font = get_font()
        local size = ui.font_size:Get()
        local ts = Render.TextSize(font, size, text)
        local tx = center_x - ts.x / 2
        local ty = y1 + (height - ts.y) / 2

        Render.Text(font, size, text, Vec2(tx + 1, ty + 1), Color(0, 0, 0, 180))
        Render.Text(font, size, text, Vec2(tx, ty), ui.color_text:Get())
    end
end

--- Renders an enhanced glowing timer progress bar.
--
--  Args:
--      center_x (number): Horizontal center point on screen.
--      top_y (number): Vertical top edge position on screen.
--      frac (number): Normalized progress fraction between 0.0 and 1.0.
--      text (string|nil): Optional formatted timer text overlay.
local function draw_glow_bar(center_x, top_y, frac, text)
    local width  = ui.bar_width:Get()
    local height = ui.bar_height:Get()
    local round  = ui.rounding:Get()

    local half = width / 2
    local x1, y1 = center_x - half, top_y
    local x2, y2 = center_x + half, top_y + height

    -- Shadow layer
    if ui.show_shadow:Get() then
        filled_rect(Vec2(x1, y1 + 3), Vec2(x2, y2 + 4), Color(0, 0, 0, 110), round)
    end

    -- Outer multi-layered glow effect
    if ui.outer_glow:Get() then
        local g = ui.color_glow:Get()
        for i = 1, 3 do
            local e = i
            local alpha = floor((g.a or 90) * (1 - (i - 1) / 3) * 0.6)
            rect_outline(Vec2(x1 - e, y1 - e), Vec2(x2 + e, y2 + e),
                Color(g.r, g.g, g.b, alpha), round + e, 1)
        end
    end

    -- Background frame
    filled_rect(Vec2(x1, y1), Vec2(x2, y2), ui.color_bg:Get(), round)

    -- Filled timer portion
    local fill_w = width * frac
    if fill_w > 0 then
        local fill_round = min(round, fill_w / 2)
        filled_rect(Vec2(x1, y1), Vec2(x1 + fill_w, y2), ui.color_fill:Get(), fill_round)
    end

    -- Inner border ring
    rect_outline(Vec2(x1, y1), Vec2(x2, y2), ui.color_border:Get(), round, 1)

    -- Centered text label
    if ui.show_number:Get() and text then
        local font = get_font()
        local size = ui.font_size:Get()
        local ts = Render.TextSize(font, size, text)
        local tx = center_x - ts.x / 2
        local ty = y1 + (height - ts.y) / 2

        Render.Text(font, size, text, Vec2(tx + 1, ty + 1), Color(0, 0, 0, 180))
        Render.Text(font, size, text, Vec2(tx, ty), ui.color_text:Get())
    end
end

--- Router function to draw progress bar depending on active style toggle.
--
--  Args:
--      center_x (number): Horizontal center coordinate.
--      top_y (number): Vertical top edge coordinate.
--      frac (number): Progress percentage (0.0 to 1.0).
--      text (string|nil): Text label to display.
local function draw_timer(center_x, top_y, frac, text)
    if ui.glow_style:Get() then
        draw_glow_bar(center_x, top_y, frac, text)
    else
        draw_bar(center_x, top_y, frac, text)
    end
end

--- Formats raw time numbers into formatted text string based on decimal toggle.
--
--  Args:
--      remaining (number): Raw seconds remaining.
--
--  Returns:
--      string: String representation (formatted to 1 decimal place or rounded up integer).
local function format_time(remaining)
    if ui.decimals:Get() then
        return ("%.1f"):format(remaining)
    end
    return tostring(ceil(remaining))
end

-- ============================================================================
-- Spatial Clustering & Processing Logic
-- ============================================================================

--- Groups nearby unit UI nodes within a pixel radius into single merged clusters.
--
--  Args:
--      list (table): List of target data entries containing screen X, Y, and durations.
--      radius (number): Clustering distance threshold in screen pixels.
local function cluster_and_draw(list, radius)
    if #list == 0 then return end
    local r2 = radius * radius
    local show_count = ui.show_count:Get()
    local clusters = {}

    -- Group targets inside spatial threshold
    for _, c in ipairs(list) do
        local placed = false
        for _, cl in ipairs(clusters) do
            local cx = cl.sum_x / cl.count
            local cy = cl.sum_y / cl.count
            local dx = c.x - cx
            local dy = c.y - cy
            if dx * dx + dy * dy <= r2 then
                cl.sum_x = cl.sum_x + c.x
                cl.sum_y = cl.sum_y + c.y
                cl.count = cl.count + 1
                if c.y < cl.top_y then cl.top_y = c.y end
                if c.remaining > cl.remaining then
                    cl.remaining = c.remaining
                    cl.duration  = c.duration
                end
                placed = true
                break
            end
        end
        if not placed then
            clusters[#clusters + 1] = {
                sum_x = c.x, sum_y = c.y,
                top_y = c.y, count = 1,
                remaining = c.remaining, duration = c.duration,
            }
        end
    end

    -- Draw merged UI clusters
    for _, cl in ipairs(clusters) do
        local center_x = cl.sum_x / cl.count
        local frac = cl.remaining / cl.duration
        if frac > 1 then frac = 1 end

        local text = format_time(cl.remaining)
        if show_count and cl.count > 1 then
            text = text .. (" x%d"):format(cl.count)
        end

        draw_timer(center_x, cl.top_y, frac, text)
    end
end

--- Core execution loop. Collects entity information, evaluates target visibility,
-- applies custom offsets/filters, and handles cluster rendering.
local function process()
    if not ui.enabled:Get() then return end

    local show_creeps    = ui.show_creeps:Get()
    local show_buildings = ui.show_buildings:Get()
    local show_allies    = ui.show_allies:Get()
    local show_enemies   = ui.show_enemies:Get()
    local offset         = ui.offset:Get()

    local my_team = get_local_team()

    local list = NPCs.GetAll()
    if not list then return end

    local candidates = {}
    for _, unit in pairs(list) do
        if not unit or not Entity.IsAlive(unit) then goto continue end

        -- Target type filtering (creeps vs structures)
        local building = is_building(unit)
        if building and not show_buildings then goto continue end
        if (not building) and not show_creeps then goto continue end

        -- Team affiliation filtering
        if my_team and Entity.GetTeamNum then
            local same = Entity.GetTeamNum(unit) == my_team
            if same and not show_allies then goto continue end
            if (not same) and not show_enemies then goto continue end
        end

        -- Modifier validity check
        local mod = get_glyph_modifier(unit)
        if not mod then goto continue end

        local remaining, duration = get_remaining(mod)
        if remaining <= 0 then goto continue end

        -- Convert world origin space to 2D screen coordinates
        local origin = Entity.GetAbsOrigin(unit)
        local hb = 0
        if NPC.GetHealthBarOffset then hb = NPC.GetHealthBarOffset(unit) end
        local screen, visible = Render.WorldToScreen(origin + Vector(0, 0, hb))
        if not visible then goto continue end

        candidates[#candidates + 1] = {
            x = screen.x,
            y = screen.y - offset,
            remaining = remaining,
            duration = duration,
            building = building,
        }

        ::continue::
    end

    if #candidates == 0 then return end

    -- Draw individual non-clustered timers if spatial clustering is disabled
    if not ui.cluster:Get() then
        for _, c in ipairs(candidates) do
            local frac = c.remaining / c.duration
            if frac > 1 then frac = 1 end
            draw_timer(c.x, c.y, frac, format_time(c.remaining))
        end
        return
    end

    -- Group and cluster by category
    local creeps, buildings = {}, {}
    for _, c in ipairs(candidates) do
        if c.building then buildings[#buildings + 1] = c else creeps[#creeps + 1] = c end
    end

    cluster_and_draw(creeps, ui.cluster_radius_creeps:Get())
    cluster_and_draw(buildings, ui.cluster_radius_buildings:Get())
end

--- Frame render callback entry point.
function script.OnDraw()
    process()
end

return script