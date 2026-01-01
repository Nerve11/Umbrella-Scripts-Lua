---@diagnostic disable: undefined-global
local script = {}

--#region Configuration
-- Настройки для героев. Легко добавлять новых.
-- menu_path: Путь к категории, где должен появиться свитч AI Threshold
-- slider_name: Имя существующего слайдера, который нужно менять
-- min_val: Значение слайдера на 1 уровне
-- max_val: Значение слайдера на максимальном уровне (18/30)
local HeroConfig = {
    ["npc_dota_hero_oracle"] = {
        menu_path = {"Heroes", "Hero List", "Oracle", "Auto Usage", "False Promise"},
        slider_name = "HP% Threshold",
        min_val = 20, 
        max_val = 30
    },
    ["npc_dota_hero_dazzle"] = {
        menu_path = {"Heroes", "Hero List", "Dazzle", "Main Settings", "Shallow Grave"},
        slider_name = "HP Threshold",
        min_val = 20, 
        max_val = 30
    }
}
--#endregion

--#region State
-- Хранение состояния скрипта
local State = {
    hero = nil,           -- Текущий объект героя
    hero_name = nil,      -- Имя героя
    last_level = -1,      -- Уровень в прошлом кадре
    config = nil,         -- Активная конфигурация
    menu = {              -- Ссылки на элементы меню
        switch = nil,
        slider = nil
    },
    is_initialized = false
}
--#endregion

--#region Helpers
-- Сброс состояния при смене героя или матча
local function ResetState()
    State.hero = nil
    State.hero_name = nil
    State.last_level = -1
    State.config = nil
    State.menu.switch = nil
    State.menu.slider = nil
    State.is_initialized = false
end

-- Инициализация меню. Пытается найти нужные элементы.
-- Возвращает true, если успешно, false - если меню еще не создано другими скриптами.
local function TryInitializeMenu(heroName)
    local cfg = HeroConfig[heroName]
    if not cfg then return false end

    -- Поиск родительского меню (unpack для Lua 5.1, table.unpack для 5.3+)
    local unpack = table.unpack or unpack
    local parentMenu = Menu.Find(unpack(cfg.menu_path))

    -- Если родительского меню нет, значит основной скрипт героя еще не прогрузился
    if not parentMenu then return false end

    -- Создаем наш переключатель (или получаем существующий)
    local aiSwitch = parentMenu:Switch("AI Threshold", false)
    if aiSwitch then
        aiSwitch:Icon("\u{f72b}")
        aiSwitch:ToolTip("Automatically scales threshold based on hero level")
    end

    -- Формируем путь к слайдеру
    local sliderPath = {}
    for _, v in ipairs(cfg.menu_path) do table.insert(sliderPath, v) end
    table.insert(sliderPath, cfg.slider_name)

    -- Ищем целевой слайдер
    local targetSlider = Menu.Find(unpack(sliderPath))

    if aiSwitch and targetSlider then
        State.menu.switch = aiSwitch
        State.menu.slider = targetSlider
        State.config = cfg
        State.is_initialized = true
        return true
    end

    return false
end

-- Расчет значения на основе уровня (Линейная интерполяция)
local function CalculateThreshold(level, minVal, maxVal)
    local MIN_LEVEL = 1
    local MAX_LEVEL = 18 -- Можно изменить на 30, если нужно скалирование до лейта

    -- Ограничиваем уровень рамками
    if level < MIN_LEVEL then level = MIN_LEVEL end
    if level > MAX_LEVEL then level = MAX_LEVEL end

    -- Формула: Min + (Разница * Процент_прогресса)
    local progress = (level - MIN_LEVEL) / (MAX_LEVEL - MIN_LEVEL)
    local result = math.floor(minVal + (maxVal - minVal) * progress)

    return result
end
--#endregion

--#region Callbacks

function script.OnUpdate()
    local localHero = Heroes.GetLocal()
    if not localHero then 
        if State.hero then ResetState() end
        return 
    end

    -- 1. Обработка смены героя или первого запуска
    if State.hero ~= localHero then
        ResetState()
        State.hero = localHero
        State.hero_name = NPC.GetUnitName(localHero)
        
        -- Если герой не поддерживается, помечаем инициализацию как проваленную навсегда для этого героя
        if not HeroConfig[State.hero_name] then
            State.is_initialized = true -- Блокируем дальнейшие попытки поиска
            State.config = nil
        end
    end

    -- Если герой не поддерживается, выходим
    if not State.config and State.is_initialized then return end

    -- 2. Ленивая инициализация меню (пытаемся найти меню, пока не найдем)
    if not State.is_initialized then
        TryInitializeMenu(State.hero_name)
        return -- Ждем следующего кадра
    end

    -- 3. Основная логика
    -- Проверяем, включен ли свитч и существуют ли элементы меню (на случай перезагрузки луа)
    if not State.menu.switch or not State.menu.slider then
        State.is_initialized = false -- Потеряли меню, ищем заново
        return
    end

    if not State.menu.switch:Get() then
        State.last_level = -1 -- Сбрасываем уровень, чтобы при включении пересчет сработал сразу
        return
    end

    -- 4. Проверка изменения уровня (Trigger-based logic)
    -- Мы не пересчитываем математику каждый кадр, только если уровень изменился
    local currentLevel = NPC.GetCurrentLevel(localHero)
    
    if currentLevel ~= State.last_level then
        local cfg = State.config
        local newValue = CalculateThreshold(currentLevel, cfg.min_val, cfg.max_val)
        
        -- Применяем значение
        State.menu.slider:Set(newValue)
        
        -- Обновляем сохраненный уровень
        State.last_level = currentLevel
        
        -- (Опционально) Вывод в лог для отладки
        -- Log.Write(string.format("[AI Threshold] Updated %s value to %d (Level: %d)", State.hero_name, newValue, currentLevel))
    end
end

function script.OnGameEnd()
    ResetState()
end

--#endregion

return script
