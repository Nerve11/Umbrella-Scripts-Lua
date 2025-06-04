local script = {}

-- Добавляем переключатель AI Threshold для Oracle
local oracleAIThresholdSwitch = Menu.Find("Heroes", "Hero List", "Oracle", "Auto Usage", "False Promise")
if oracleAIThresholdSwitch then
    local switch = oracleAIThresholdSwitch:Switch("AI Threshold", false)
    switch:Icon("\u{f72b}") 
end

-- Добавляем переключатель AI Threshold для Dazzle
local dazzleAIThresholdSwitch = Menu.Find("Heroes", "Hero List", "Dazzle", "Main Settings", "Shallow Grave")
if dazzleAIThresholdSwitch then
    local switch = dazzleAIThresholdSwitch:Switch("AI Threshold", false)
    switch:Icon("\u{f72b}")
end

-- Получает текущий уровень локального героя
local function GetHeroLevel()
    local hero = Heroes.GetLocal()
    if not hero then return 1 end
    return NPC.GetCurrentLevel(hero)
end

-- Устанавливает пороговое значение HP% в зависимости от героя
local function SetThreshold(heroName, value)
    if heroName == "npc_dota_hero_oracle" then
        local threshold = Menu.Find("Heroes", "Hero List", "Oracle", "Auto Usage", "False Promise", "HP% Threshold")
        if threshold then threshold:Set(value) end
    elseif heroName == "npc_dota_hero_dazzle" then
        local threshold = Menu.Find("Heroes", "Hero List", "Dazzle", "Main Settings", "Shallow Grave", "HP Threshold")
        if threshold then threshold:Set(value) end
    end
end

-- Проверяет, активен ли AI Threshold для данного героя
local function IsAIThresholdEnabled(heroName)
    if heroName == "npc_dota_hero_oracle" then
        local toggle = Menu.Find("Heroes", "Hero List", "Oracle", "Auto Usage", "False Promise", "AI Threshold")
        return toggle and toggle:Get()
    elseif heroName == "npc_dota_hero_dazzle" then
        local toggle = Menu.Find("Heroes", "Hero List", "Dazzle", "Main Settings", "Shallow Grave", "AI Threshold")
        return toggle and toggle:Get()
    end
    return false
end

-- Вычисляет значение HP% на основе уровня героя
local function CalculateHPThreshold(level)
    local minLevel, maxLevel = 1, 18
    local minValue, maxValue = 20, 30

    level = math.max(minLevel, math.min(maxLevel, level))
    local result = math.floor(minValue + ((maxValue - minValue) * (level - minLevel)) / (maxLevel - minLevel))
    return result
end

-- Основная логика обновления
script.OnUpdate = function()
    local hero = Heroes.GetLocal()
    if not hero then return end

    local heroName = NPC.GetUnitName(hero)
    if heroName ~= "npc_dota_hero_oracle" and heroName ~= "npc_dota_hero_dazzle" then return end
    if not IsAIThresholdEnabled(heroName) then return end

    local level = GetHeroLevel()
    local threshold = CalculateHPThreshold(level)

    SetThreshold(heroName, threshold)
end

-- Загрузка скрипта
script.OnLoad = function()
    print("Auto Threshold script loaded!")
end

return script
