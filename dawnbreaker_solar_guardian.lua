local DawnbreakerScript = {}

-- Menu Setup

local settingsGroup = nil
local settings = {}

local success, err = pcall(function()
    Log.Write("Dawnbreaker Helper: Initializing menu...")
    local heroTab = Menu.Create("Heroes", "Hero List", "Dawnbreaker")
    if not heroTab then
        Log.Write("Dawnbreaker Helper Error: Failed to create hero tab 'Dawnbreaker'. Make sure the 'Hero List' section exists.")
        return
    end
    heroTab:Icon("panorama/images/heroes/icons/npc_dota_hero_dawnbreaker_png.vtex_c")

    local scriptTab = heroTab:Create("Auto Solar Guardian")
    if not scriptTab then
        Log.Write("Dawnbreaker Helper Error: Failed to create script tab 'Auto Solar Guardian'.")
        return
    end

    settingsGroup = scriptTab:Create("Settings")
    if not settingsGroup then
        Log.Write("Dawnbreaker Helper Error: Failed to create 'Settings' group.")
        return
    end

    settings.masterEnable = settingsGroup:Switch("Enable Script", true, "✓")
    settings.allyToSave = settingsGroup:Combo("Ally to Save", {"None"}, 0)
    settings.minAttackers = settingsGroup:Slider("Min Attackers", 2, 5, 3, "%d")
    settings.checkRadius = settingsGroup:Slider("Check Radius", 400, 1200, 800, "%d")

    settings.allyToSave:ToolTip("Select a single ally to protect with Solar Guardian.")
    settings.minAttackers:ToolTip("The number of enemy heroes required near the ally to trigger the ultimate.")
    settings.checkRadius:ToolTip("The radius around the ally to check for enemy heroes.")

    -- Callback to manage the enabled/disabled state of the controls.
    local function updateMenuState()
        if settings.masterEnable then
            local isEnabled = settings.masterEnable:Get()
            if settings.allyToSave then settings.allyToSave:Disabled(not isEnabled) end
            if settings.minAttackers then settings.minAttackers:Disabled(not isEnabled) end
            if settings.checkRadius then settings.checkRadius:Disabled(not isEnabled) end
        end
    end
    settings.masterEnable:SetCallback(updateMenuState, true)

    Log.Write("Dawnbreaker Helper: Menu and widgets created successfully.")
end)

if not success then
    Log.Write("Dawnbreaker Helper FATAL ERROR during menu setup: " .. tostring(err))
    return DawnbreakerScript -- Return an empty table to prevent the script from running with a broken menu.
end

-- Script Variables
local localHero = nil
local alliesPopulated = false
local allyList = {"None"}


-- Helper Functions
local function getLocalHero()
    if not localHero then
        localHero = Heroes.GetLocal()
    end
    return localHero
end

local function populateAllyList(hero)
    if alliesPopulated or not settings.allyToSave then return end

    allyList = {"None"}
    local myTeam = Entity.GetTeamNum(hero)
    local allHeroes = Heroes.GetAll()

    for _, ally in pairs(allHeroes) do
        if ally and Entity.GetTeamNum(ally) == myTeam and ally ~= hero then
            table.insert(allyList, NPC.GetUnitName(ally))
        end
    end

    local currentSelection = settings.allyToSave:Get()
    settings.allyToSave:Update(allyList, currentSelection)
    alliesPopulated = true
end


-- Main Logic
DawnbreakerScript.OnUpdate = function()
    if not settings.masterEnable or not settings.masterEnable:Get() then
        return
    end

    if not Engine.IsInGame() then
        if alliesPopulated then
            alliesPopulated = false
            allyList = {"None"}
            if settings.allyToSave then
                settings.allyToSave:Update(allyList, 0)
            end
        end
        localHero = nil
        return
    end

    local hero = getLocalHero()
    if not hero or NPC.GetUnitName(hero) ~= "npc_dota_hero_dawnbreaker" or not Entity.IsAlive(hero) then
        return
    end

    populateAllyList(hero)

    local solarGuardian = NPC.GetAbility(hero, "dawnbreaker_solar_guardian")
    if not solarGuardian or not Ability.IsReady(solarGuardian) then
        return
    end

    local selectedAllyIndex = settings.allyToSave:Get()
    if selectedAllyIndex == 0 then
        return
    end

    local selectedAllyName = allyList[selectedAllyIndex + 1]
    if not selectedAllyName then return end

    local minAttackers = settings.minAttackers:Get()
    local checkRadius = settings.checkRadius:Get()

    local allyHero = nil
    local allHeroes = Heroes.GetAll()
    for _, h in pairs(allHeroes) do
        if h and NPC.GetUnitName(h) == selectedAllyName then
            allyHero = h
            break
        end
    end

    if not allyHero or not Entity.IsAlive(allyHero) then
        return
    end

    local enemiesNear = Entity.GetHeroesInRadius(allyHero, checkRadius, Enum.TeamType.TEAM_ENEMY, true, true)

    if #enemiesNear >= minAttackers then
        Ability.CastPosition(solarGuardian, Entity.GetAbsOrigin(allyHero))
    end
end

DawnbreakerScript.OnFrame = function()
    localHero = nil
end

return DawnbreakerScript