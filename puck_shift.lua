local script = {}
local myHero = nil

-- Menu Creation
local tabMain = Menu.Create("Heroes", "Hero List", "Puck")
local generalGroup = tabMain:Create("Auto Phase Shift"):Create("Global")
local attackGroup = tabMain:Create("Auto Phase Shift"):Create("Main")
local visualGroup = tabMain:Create("Auto Phase Shift"):Create("Visual")

-- UI Configuration
local ui = {}
ui.masterEnable = generalGroup:Switch("Enable Script", true, "\u{f058}")
ui.logicEnable = attackGroup:Switch("Enable Logic", true, "\u{f00c}")
ui.projectileCount = attackGroup:Slider("Min Active Projectiles", 1, 5, 2, function(v) 
    return tostring(v) 
end)
ui.showDebug = attackGroup:Switch("Verbose Debug (console)", true, "\u{f188}")
ui.iconSize = visualGroup:Slider("Icon Size", 32, 256, 64, function(v) 
    return tostring(v) 
end)
ui.ctrlToDrag = visualGroup:Switch("Ctrl+LMB to Drag", true, "\u{f0b2}")
ui.shadowEnable = visualGroup:Switch("Enable Shadow", true, "\u{f19c}")
ui.shadowColor = visualGroup:ColorPicker("Shadow Color", Color(0, 128, 255), "\u{f0db}")
ui.shadowThickness = visualGroup:Slider("Shadow Thickness", 1, 50, 4, function(v) 
    return tostring(v) 
end)

-- Data Storage
local info = db.puckIndicator or {}
db.puckIndicator = info

-- Constants
local ICON_PATH = "panorama/images/spellicons/puck_phase_shift_png.vtex_c"
local iconHandle = Render.LoadImage(ICON_PATH)
local iconPos = Vec2(info.x or 100, info.y or 100)
local KEY_CTRL = Enum.ButtonCode.KEY_LCONTROL
local KEY_LMB = Enum.ButtonCode.KEY_MOUSE1

-- Fonts
local debugFont = Renderer.LoadFont("Tahoma", 12, 4, 4)
local countFont = Renderer.LoadFont("Tahoma", 14, 4, 4)

-- Debug System
local debugMessages = {}

local function Debug(msg)
    table.insert(debugMessages, {
        text = msg,
        time = GameRules.GetGameTime()
    })
    
    if #debugMessages > 10 then
        table.remove(debugMessages, 1)
    end
    
    if ui.showDebug and ui.showDebug:Get() then
        print("[Puck] " .. msg)
    end
end

-- Utility Functions
local function isTrue(val)
    return (val == true) or (val == "true") or (val == 1) or (val == "1")
end

local function Hero()
    if not myHero then
        myHero = Heroes.GetLocal()
        if myHero then
            Debug("Hero found: " .. NPC.GetUnitName(myHero))
        end
    end
    return myHero
end

-- Projectile Management
local activeProjectiles = {}
local lastCastTime = 0

local function IsTargetingHero(proj, hero)
    if proj.target and (proj.target == hero) then
        return true
    end
    
    local targetName = proj["[m]target_name"]
    return targetName and (targetName == NPC.GetUnitName(hero))
end

local function CountProjectiles(now)
    local count = 0
    for _, data in pairs(activeProjectiles) do
        if data.eta > now then
            count = count + 1
        end
    end
    return count
end

local function Purge(now)
    for handle, data in pairs(activeProjectiles) do
        if data.eta <= now then
            activeProjectiles[handle] = nil
        end
    end
end

local function Register(proj)
    local hero = Hero()
    if not hero then
        return
    end
    
    -- Check if projectile targets our hero
    if not IsTargetingHero(proj, hero) then
        return
    end
    
    -- Skip friendly projectiles
    if Entity.IsSameTeam(hero, proj.source) then
        return
    end
    
    -- Only handle dodgeable projectiles or attacks
    if not (isTrue(proj.dodgeable) or isTrue(proj.isAttack)) then
        return
    end
    
    -- Calculate projectile impact time
    local handle = proj.handle or tostring(math.random(1000000000))
    local speed = tonumber(proj.moveSpeed) or 1000
    
    if speed < 50 then
        speed = 1000
    end
    
    local now = GameRules.GetGameTime()
    local eta
    
    if proj.maxImpactTime and tonumber(proj.maxImpactTime) and (tonumber(proj.maxImpactTime) > 0) then
        eta = now + tonumber(proj.maxImpactTime)
    else
        local srcPos = Entity.GetAbsOrigin(proj.source)
        local trgPos = Entity.GetAbsOrigin(hero)
        local dist = (trgPos and srcPos and (trgPos - srcPos):Length2D()) or 600
        eta = now + (dist / speed)
    end
    
    -- Store projectile data
    activeProjectiles[handle] = {
        name = proj.name or "unknown",
        source = proj["[m]unit_name"] or "?",
        eta = eta
    }
    
    Debug(string.format("Registered ➜ %s from %s (ETA %.2fs)", 
        proj.name or "?", 
        proj["[m]unit_name"] or "?", 
        eta - now))
end

-- Script Event Handlers
script.OnProjectile = function(proj)
    Debug(string.format("Projectile callback: %s | isAttack=%s | dodgeable=%s",
        tostring(proj.name),
        tostring(proj.isAttack),
        tostring(proj.dodgeable)))
    
    if not ui.masterEnable:Get() or not ui.logicEnable:Get() then
        return
    end
    
    local hero = Hero()
    if not hero then
        return
    end
    
    if NPC.GetUnitName(hero) ~= "npc_dota_hero_puck" then
        return
    end
    
    if not Entity.IsAlive(hero) then
        return
    end
    
    Register(proj)
end

script.OnUpdate = function()
    if not ui.masterEnable:Get() or not ui.logicEnable:Get() then
        return
    end
    
    local hero = Hero()
    if not hero then
        return
    end
    
    if NPC.GetUnitName(hero) ~= "npc_dota_hero_puck" then
        return
    end
    
    if not Entity.IsAlive(hero) then
        return
    end
    
    local now = GameRules.GetGameTime()
    Purge(now)
    
    local count = CountProjectiles(now)
    
    -- Cast Phase Shift if enough projectiles are active
    if (count >= ui.projectileCount:Get()) and ((now - lastCastTime) > 1) then
        local ability = NPC.GetAbility(hero, "puck_phase_shift")
        
        if ability and Ability.IsReady(ability) then
            Debug("Casting Phase Shift – «" .. count .. "» active")
            Ability.CastNoTarget(ability)
            lastCastTime = now
            activeProjectiles = {}
        end
    end
end

script.OnDraw = function()
    if not ui.masterEnable:Get() then
        return
    end
    
    local hero = Hero()
    if not hero then
        return
    end
    
    -- Icon positioning and sizing
    local size = Vec2(ui.iconSize:Get(), ui.iconSize:Get())
    local half = size * 0.5
    local topLeft = iconPos - half
    local bottomRight = iconPos + half
    local mouseX, mouseY = Input.GetCursorPos()
    local mousePos = Vec2(mouseX, mouseY)
    
    -- Handle icon clicks (toggle logic)
    if Input.IsKeyDownOnce(KEY_LMB) and 
       not (ui.ctrlToDrag:Get() and Input.IsKeyDown(KEY_CTRL)) and
       (mousePos.x >= topLeft.x) and (mousePos.x <= bottomRight.x) and
       (mousePos.y >= topLeft.y) and (mousePos.y <= bottomRight.y) then
        
        ui.logicEnable:Set(not ui.logicEnable:Get())
        Debug("Logic toggled: " .. tostring(ui.logicEnable:Get()))
    end
    
    -- Handle icon dragging
    if ui.ctrlToDrag:Get() and Input.IsKeyDown(KEY_CTRL) and 
       Input.IsKeyDownOnce(KEY_LMB) and
       (mousePos.x >= topLeft.x) and (mousePos.x <= bottomRight.x) and
       (mousePos.y >= topLeft.y) and (mousePos.y <= bottomRight.y) then
        
        dragging = true
        dragOffset = iconPos - mousePos
    end
    
    if dragging and Input.IsKeyDown(KEY_LMB) then
        local cursorX, cursorY = Input.GetCursorPos()
        iconPos = Vec2(cursorX, cursorY) + dragOffset
    end
    
    if dragging and not Input.IsKeyDown(KEY_LMB) then
        dragging = false
        info.x, info.y = iconPos.x, iconPos.y
    end
    
    -- Render icon
    local color = (ui.logicEnable:Get() and Color(255, 255, 255)) or Color(128, 128, 128)
    
    if ui.shadowEnable:Get() then
        Render.Shadow(topLeft, bottomRight, ui.shadowColor:Get(), 
            ui.shadowThickness:Get(), size.x * 0.2, 
            Enum.DrawFlags.RoundCornersAll, Vec2(0, 0))
    end
    
    Render.ImageCentered(iconHandle, iconPos, size, color, size.x * 0.2)
    
    -- Render projectile count
    local projectileCount = CountProjectiles(GameRules.GetGameTime())
    Render.Text(countFont, 14, tostring(projectileCount), 
        Vec2(iconPos.x, iconPos.y + (size.y * 0.6)), color)
    
    -- Render debug information
    if ui.showDebug:Get() then
        local yPos = iconPos.y + size.y + 4
        local lineStep = 16
        local now = GameRules.GetGameTime()
        
        Render.Text(debugFont, 12, string.format("Time: %.2f", now),
            Vec2(iconPos.x, yPos), Color(255, 255, 255))
        yPos = yPos + lineStep
        
        for _, msg in ipairs(debugMessages) do
            local alpha = 255 * math.max(0, 1 - ((now - msg.time) / 10))
            Render.Text(debugFont, 12, msg.text,
                Vec2(iconPos.x, yPos), Color(200, 255, 200, alpha))
            yPos = yPos + lineStep
        end
    end
end

script.OnScriptLoad = function()
    Debug("Script loaded – v1.1")
    
    local hero = Hero()
    if hero and (NPC.GetUnitName(hero) ~= "npc_dota_hero_puck") then
        Debug("WARNING: Not playing Puck – disabling")
        ui.masterEnable:Set(false)
    end
end

return script