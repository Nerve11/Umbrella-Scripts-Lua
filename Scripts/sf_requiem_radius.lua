---@diagnostic disable: undefined-global, lowercase-global
local script = {}


-- #Menu & UI Configuration

local menu_root = Menu.Create("Heroes", "Hero List", "Shadow Fiend", "Requiem Radius")
local group = menu_root:Create("Main")

local ui = {}
ui.enabled = group:Switch("Enable", true)
ui.draw_mode = group:Combo("Display Mode", {
    "When Ready",
    "On Cast",
    "Always"
}, 1)
ui.color = group:ColorPicker("Color", Color(255, 50, 50, 150))
ui.thickness = group:Slider("Thickness", 1, 5, 2)
ui.effect = group:Combo("Effect", {
    "Circle",
    "Shadow Ring",
    "Pulse Dash"
}, 0)

-- State cache for optimal performance
local state = {
    ability = nil,
    is_sf = false
}


-- #Helper Functions

--- Calculates the dynamic radius of Requiem of Souls based on level and soul count
-- @param ability Entity: Ability handle for Requiem of Souls
-- @param hero Entity: Local hero handle
-- @return number: Calculated visual radius in game units
local function get_requiem_radius(ability, hero)
    if not ability then return 0 end
    local level = Ability.GetLevel(ability)
    if level <= 0 then return 0 end

    -- Retrieve base radius from ability key-values
    local base = Ability.GetLevelSpecialValueFor(ability, "RequiemRadius", level)
    if not base or base <= 0 then
        base = Ability.GetLevelSpecialValueFor(ability, "radius", level)
    end
    if not base or base <= 0 then
        base = 700 -- Fallback default radius
    end

    -- Retrieve additional radius scaling per soul stack
    local per_soul = Ability.GetLevelSpecialValueFor(ability, "RequiemRadiusPerSoul", level)
    if not per_soul or per_soul <= 0 then
        per_soul = 0
    end

    -- Query current soul stack count safely
    local souls = 0
    local ok, stack = pcall(function()
        return NPC.GetModifierStackCount(hero, "modifier_nevermore_requiem_soul")
    end)
    if ok and type(stack) == "number" then souls = stack end

    -- Custom multiplier for accurate visual coverage matching game mechanics
    local mult = 1.65
    return (base + per_soul * souls) * mult
end


-- #Rendering Routines


--- Renders a standard smooth 2D world circle projected from 3D space
local function draw_world_circle(center, radius, color, thickness)
    if radius <= 0 then return end
    local segments = 120
    local points = {}
    local step = (math.pi * 2) / segments
    
    -- Calculate 3D world points and project to 2D screen space
    for i = 0, segments do
        local angle = i * step
        local x = center.x + math.cos(angle) * radius
        local y = center.y + math.sin(angle) * radius
        local p = Vector(x, y, center.z)
        local screen, ok = Render.WorldToScreen(p)
        if ok and screen and screen.x > 0 and screen.y > 0 then
            table.insert(points, { x = screen.x, y = screen.y })
        else
            table.insert(points, false)
        end
    end
    
    -- Connect screen points with lines
    for i = 1, #points do
        local j = i % #points + 1
        local p1 = points[i]
        local p2 = points[j]
        
        if p1 and p2 then
            Render.Line(Vector(p1.x, p1.y, 0), Vector(p2.x, p2.y, 0), color, thickness)
        end
    end
end

--- Renders an animated rotating "Shadow Ring" effect with dynamic spikes
local function draw_world_sticks(center, radius, color, thickness)
    if radius <= 0 then return end
    local segments = 120
    local points = {}
    local step = (math.pi * 2) / segments

    -- Calculate continuous rotation offset using system clock
    local time = os.clock()
    local rotation_speed = 1.5
    local offset = time * rotation_speed

    for i = 0, segments do
        local angle = i * step + offset
        local x = center.x + math.cos(angle) * radius
        local y = center.y + math.sin(angle) * radius
        local p = Vector(x, y, center.z)
        local screen, ok = Render.WorldToScreen(p)
        if ok and screen and screen.x > 0 and screen.y > 0 then
            table.insert(points, { x = screen.x, y = screen.y, angle = angle })
        else
            table.insert(points, false)
        end
    end

    -- Draw dynamic perpendicular lines (sticks/spikes) along the perimeter
    for i = 1, #points do
        local p1 = points[i]
        if p1 then
            local stick_len = 6 + 6 * math.abs(math.sin(time * 2.5 + i * 0.3))
            local perp_angle = p1.angle + math.pi / 2
            
            local x1 = p1.x + math.cos(perp_angle) * stick_len
            local y1 = p1.y + math.sin(perp_angle) * stick_len
            local x2 = p1.x - math.cos(perp_angle) * stick_len
            local y2 = p1.y - math.sin(perp_angle) * stick_len
            
            Render.Line(Vector(x1, y1, 0), Vector(x2, y2, 0), color, thickness)
        end
    end
end

--- Renders an animated dashed ring with multi-layered glow effects
local function draw_world_pulse_dash(center, radius, color, thickness)
    if radius <= 0 then return end
    local segments = 120
    local points = {}
    local step = (math.pi * 2) / segments

    local time = os.clock()
    local rotation_speed = 1.0
    local offset = time * rotation_speed

    for i = 0, segments do
        local angle = i * step + offset
        local x = center.x + math.cos(angle) * radius
        local y = center.y + math.sin(angle) * radius
        local p = Vector(x, y, center.z)
        local screen, ok = Render.WorldToScreen(p)
        if ok and screen and screen.x > 0 and screen.y > 0 then
            table.insert(points, { x = screen.x, y = screen.y, angle = angle })
        else
            table.insert(points, false)
        end
    end

    local dash_ratio = 0.4
    local glow_layers = 4

    for i = 1, #points do
        local j = i % #points + 1
        local p1 = points[i]
        local p2 = points[j]

        if p1 and p2 then
            local seg_index = i - 1
            local dash_on = (seg_index % 3) < (3 * dash_ratio)

            if dash_on then
                -- Render multi-layered alpha glow behind the main line
                for g = glow_layers, 1, -1 do
                    local glow_alpha = color.a * (0.15 / g)
                    local glow_color = Color(color.r, color.g, color.b, glow_alpha)
                    local glow_thick = thickness + g * 2.5
                    Render.Line(Vector(p1.x, p1.y, 0), Vector(p2.x, p2.y, 0), glow_color, glow_thick)
                end
                -- Core segment line
                Render.Line(Vector(p1.x, p1.y, 0), Vector(p2.x, p2.y, 0), color, thickness)
            end
        end
    end
end


-- #Script Event Callbacks


--- Main logic tick: updates hero state, ability handle, and unit verification
function script.OnUpdate()
    if not ui.enabled:Get() then return end
    if not Engine.IsInGame() then return end

    local hero = Heroes.GetLocal()
    if not hero then 
        state.is_sf = false
        return 
    end
    
    -- Verify local hero is Shadow Fiend
    state.is_sf = (NPC.GetUnitName(hero) == "npc_dota_hero_nevermore")
    if not state.is_sf then return end

    -- Cache ultimate ability handle
    state.ability = NPC.GetAbility(hero, "nevermore_requiem")
end

--- Render tick: handles display conditions and draws chosen visual effect
function script.OnDraw()
    if not ui.enabled:Get() then return end
    if not state.is_sf then return end

    local hero = Heroes.GetLocal()
    if not hero then return end

    local ability = state.ability
    if not ability then return end

    local level = Ability.GetLevel(ability)
    if level <= 0 then return end

    -- Check casting and channeling conditions
    local in_phase = Ability.IsInAbilityPhase(ability)
    local channeling = false
    local channel_ability = NPC.GetChannellingAbility(hero)
    if channel_ability and Entity.IsAbility(channel_ability) then
        channeling = (Ability.GetName(channel_ability) == "nevermore_requiem")
    end

    -- Evaluate display mode filters
    local should_draw = false
    local mode = ui.draw_mode:Get()
    if mode == 0 and Ability.IsReady(ability) then
        should_draw = true
    elseif mode == 1 and (in_phase or channeling) then
        should_draw = true
    elseif mode == 2 then
        should_draw = true
    end

    if not should_draw then return end

    local origin = Entity.GetAbsOrigin(hero)
    if not origin then return end

    local radius = get_requiem_radius(ability, hero)
    if radius <= 0 then return end

    local color = ui.color:Get()
    local thickness = ui.thickness:Get()
    local effect = ui.effect:Get()

    -- Dispatch rendering based on selected effect type
    if effect == 0 then
        draw_world_circle(origin, radius, color, thickness)
    elseif effect == 1 then
        draw_world_sticks(origin, radius, color, thickness)
    else
        draw_world_pulse_dash(origin, radius, color, thickness)
    end
end

--- Cleanup callback when match ends or disconnects
function script.OnGameEnd()
    state.ability = nil
    state.is_sf = false
end

return script