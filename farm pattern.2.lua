-- Farm Pattern Script для Dota 2
-- Скрипт для расчета оптимальных маршрутов фарма

-- Основные переменные состояния
local farmPattern = {}
local localHero = nil
local localTeam = nil
local fadeAlpha = 0
local fadeSpeed = 10
local animationSpeed = 0.2
local animatedPoints = {}
local pathCheckpoints = {}

-- Создание меню
local mainMenu = Menu.Create("Scripts", "User Scripts", "Farm Pattern")
local optionsMenu = mainMenu:Create("Options"):Create("Main")

-- Настройки интерфейса
local settings = {}
settings.enabled = optionsMenu:Switch("Show Farm Route", true, "⚡")
settings.ctrlToDrag = optionsMenu:Switch("Ctrl-Drag Stats Text", true, "🔩")
settings.optimized = optionsMenu:Switch("Show Optimal Path", true, "📦")
settings.algorithm = optionsMenu:Combo("Algorithm", {"Greedy", "Optimal (Advanced)"}, 1, "⚙")

-- Параметры поиска
settings.searchRadius = optionsMenu:Slider("Search Radius", 500, 6000, 1500, 
    function(value) return tostring(value) end)
settings.allyRadius = optionsMenu:Slider("Ally Exclusion Radius", 300, 1000, 600, 
    function(value) return tostring(value) end)
settings.pointsCount = optionsMenu:Slider("Points to Calculate", 2, 10, 4, 
    function(value) return tostring(value) end)

-- Визуальные настройки
settings.showVisualization = optionsMenu:Switch("Toggle Visualization", true, "🔄")
settings.visualColor = optionsMenu:ColorPicker("Visual Color", Color(0, 255, 128), "👁")
settings.circleSize = optionsMenu:Slider("Point Size", 5, 30, 10, 
    function(value) return tostring(value) end)

-- Параметры фарма
settings.farmTimePerCreep = optionsMenu:Slider("Farm Time/Creep (s)", 0.5, 3, 1, 
    function(value) return string.format("%.1f", value) end)
settings.minEfficiency = optionsMenu:Slider("Min Efficiency (g/s)", 0, 50, 10, 
    function(value) return tostring(value) end)
settings.goldWeight = optionsMenu:Slider("Gold Weight", 0.5, 2, 1, 
    function(value) return string.format("%.1f", value) end)
settings.xpWeight = optionsMenu:Slider("XP Weight", 0, 2, 0.7, 
    function(value) return string.format("%.1f", value) end)

-- Динамические настройки
settings.dynamicUpdate = optionsMenu:Switch("Dynamic Route Updates", true, "🔄")
settings.checkpointCount = optionsMenu:Slider("Checkpoints per Path", 1, 10, 5, 
    function(value) return tostring(value) end)

-- Сохранение позиции UI элементов
db.farmRouteIndicator = db.farmRouteIndicator or {}
local uiPosition = db.farmRouteIndicator
uiPosition.x = uiPosition.x or 10
uiPosition.y = uiPosition.y or 320

-- Переменные для перетаскивания UI
local isDragging = false
local dragOffset = Vec2(0, 0)

-- Состояние маршрута
local farmSpots = {}
local calculatedRoute = {}
local lastUpdateTime = 0
local currentWaypointIndex = 1
local lastHeroPosition = nil

-- Получение игрового времени
local function getGameTime()
    local gameTime = GameRules.GetGameTime() - GameRules.GetGameStartTime()
    if gameTime < 0 then gameTime = 0 end
    return gameTime
end

-- Получение локального героя
local function getLocalHero()
    if not localHero then
        localHero = Heroes.GetLocal()
    end
    return localHero
end

-- Получение команды игрока
local function getLocalTeam()
    if not localTeam then
        local player = Players.GetLocal()
        local playerSlot = Player.GetPlayerSlot(player)
        localTeam = (playerSlot < 5) and Enum.TeamNum.TEAM_RADIANT or Enum.TeamNum.TEAM_DIRE
    end
    return localTeam
end

-- Подсчет элементов в таблице
local function countElements(table)
    local count = 0
    if table then
        for _ in pairs(table) do
            count = count + 1
        end
    end
    return count
end

-- Расчет времени фарма для точки
local function calculateFarmTime(farmSpot)
    local hero = getLocalHero()
    local creepCount = farmSpot.creepCount or 0
    
    -- Оценка количества крипов по количеству золота
    if creepCount == 0 then
        if farmSpot.gold > 150 then
            creepCount = 5
        elseif farmSpot.gold > 100 then
            creepCount = 4
        else
            creepCount = 3
        end
    end
    
    -- Расчет DPS героя
    local heroDamage = NPC.GetTrueDamage(hero)
    local heroAttackSpeed = NPC.GetAttackSpeed(hero)
    local heroDPS = heroDamage * heroAttackSpeed
    local creepHP = 300 -- Средний HP крипа
    
    -- Проверка наличия AoE способностей
    local aoeAbilities = {
        "juggernaut_blade_fury",
        "axe_counter_helix", 
        "antimage_blink",
        "phantom_assassin_stifling_dagger",
        "luna_moon_glaive",
        "sven_great_cleave"
    }
    
    local hasAoE = false
    for _, abilityName in ipairs(aoeAbilities) do
        local ability = NPC.GetAbility(hero, abilityName)
        if ability and Ability.IsReady(ability) then
            hasAoE = true
            break
        end
    end
    
    -- Расчет времени фарма
    local farmTime = creepCount * (creepHP / math.max(50, heroDPS))
    if hasAoE then
        farmTime = farmTime * 0.6 -- Бонус от AoE способностей
    end
    
    return math.max(farmTime, creepCount * settings.farmTimePerCreep:Get())
end

-- Создание промежуточных точек между двумя позициями
local function createCheckpoints(startPos, endPos, checkpointCount)
    local checkpoints = {}
    for i = 1, checkpointCount do
        local ratio = i / (checkpointCount + 1)
        local x = startPos.x + (endPos.x - startPos.x) * ratio
        local y = startPos.y + (endPos.y - startPos.y) * ratio
        local z = startPos.z + (endPos.z - startPos.z) * ratio
        table.insert(checkpoints, Vector(x, y, z))
    end
    return checkpoints
end

-- Проверка наличия союзников рядом
local function hasAlliesNearby(position, radius)
    local hero = getLocalHero()
    if not hero then return false end
    
    local team = getLocalTeam()
    local nearbyAllies = Heroes.InRadius(position, radius, team, Enum.TeamType.TEAM_FRIEND)
    
    for _, ally in ipairs(nearbyAllies) do
        if ally ~= hero and Entity.IsAlive(ally) then
            return true
        end
    end
    return false
end

-- Создание маршрута с промежуточными точками
local function createRouteWithCheckpoints(hero, route, checkpointCount)
    local routeWithCheckpoints = {}
    local heroPosition = Entity.GetAbsOrigin(hero)
    
    if #route > 0 then
        table.insert(routeWithCheckpoints, createCheckpoints(heroPosition, route[1].pos, checkpointCount))
    end
    
    for i = 1, #route - 1 do
        table.insert(routeWithCheckpoints, createCheckpoints(route[i].pos, route[i + 1].pos, checkpointCount))
    end
    
    return routeWithCheckpoints
end

-- Анимация точек маршрута
local function animateRoutePoints()
    for routeIndex, checkpointGroup in ipairs(pathCheckpoints) do
        animatedPoints[routeIndex] = animatedPoints[routeIndex] or {}
        
        for checkpointIndex, checkpoint in ipairs(checkpointGroup) do
            local animatedPoint = animatedPoints[routeIndex][checkpointIndex] or Vector(checkpoint.x, checkpoint.y, checkpoint.z)
            
            -- Плавная анимация к целевой позиции
            animatedPoint.x = animatedPoint.x + (checkpoint.x - animatedPoint.x) * animationSpeed
            animatedPoint.y = animatedPoint.y + (checkpoint.y - animatedPoint.y) * animationSpeed
            animatedPoint.z = animatedPoint.z + (checkpoint.z - animatedPoint.z) * animationSpeed
            
            animatedPoints[routeIndex][checkpointIndex] = animatedPoint
        end
    end
end

-- Жадный алгоритм поиска маршрута
local function calculateGreedyRoute()
    local hero = getLocalHero()
    if not hero then return {} end
    
    local heroPosition = Entity.GetAbsOrigin(hero)
    local heroMoveSpeed = NPC.GetMoveSpeed(hero)
    local availableSpots = {}
    
    -- Копирование доступных точек с расчетом XP
    for _, spot in ipairs(farmSpots) do
        local estimatedXP = spot.gold * 0.8
        table.insert(availableSpots, {
            pos = spot.pos,
            gold = spot.gold,
            xp = estimatedXP,
            creepCount = spot.creepCount,
            isJungle = spot.isJungle
        })
    end
    
    local route = {}
    local currentPosition = heroPosition
    local minEfficiency = settings.minEfficiency:Get()
    local maxPoints = settings.pointsCount:Get()
    local goldWeight = settings.goldWeight:Get()
    local xpWeight = settings.xpWeight:Get()
    
    -- Жадный поиск лучших точек
    while #availableSpots > 0 and #route < maxPoints do
        local bestSpotIndex, bestEfficiency = nil, 0
        
        for i, spot in ipairs(availableSpots) do
            local travelTime = GridNav.GetTravelTime(currentPosition, spot.pos, false, nil, heroMoveSpeed)
            local farmTime = calculateFarmTime(spot)
            local totalValue = (spot.gold * goldWeight) + (spot.xp * xpWeight)
            local efficiency = totalValue / (travelTime + farmTime)
            
            if efficiency >= minEfficiency and efficiency > bestEfficiency then
                bestEfficiency, bestSpotIndex = efficiency, i
            end
        end
        
        if not bestSpotIndex then break end
        
        table.insert(route, availableSpots[bestSpotIndex])
        currentPosition = availableSpots[bestSpotIndex].pos
        table.remove(availableSpots, bestSpotIndex)
    end
    
    return route
end

-- Оптимальный алгоритм поиска маршрута
local function calculateOptimalRoute()
    local hero = getLocalHero()
    if not hero then return {} end
    
    local heroPosition = Entity.GetAbsOrigin(hero)
    local heroMoveSpeed = NPC.GetMoveSpeed(hero)
    local availableSpots = {}
    local goldWeight = settings.goldWeight:Get()
    local xpWeight = settings.xpWeight:Get()
    
    -- Фильтрация и подготовка точек для оптимального алгоритма
    for _, spot in ipairs(farmSpots) do
        local estimatedXP = spot.gold * 0.8
        local travelTime = GridNav.GetTravelTime(heroPosition, spot.pos, false, nil, heroMoveSpeed)
        local farmTime = calculateFarmTime({
            pos = spot.pos,
            gold = spot.gold,
            creepCount = spot.creepCount,
            isJungle = spot.isJungle
        })
        local totalValue = (spot.gold * goldWeight) + (estimatedXP * xpWeight)
        local efficiency = totalValue / (travelTime + farmTime)
        
        if efficiency >= settings.minEfficiency:Get() then
            table.insert(availableSpots, {
                pos = spot.pos,
                gold = spot.gold,
                xp = estimatedXP,
                creepCount = spot.creepCount,
                eff = efficiency,
                isJungle = spot.isJungle
            })
        end
    end
    
    -- Ограничение количества точек для оптимизации
    local maxOptimalPoints = math.min(8, #availableSpots)
    table.sort(availableSpots, function(a, b) return a.eff > b.eff end)
    
    if #availableSpots > maxOptimalPoints then
        local limitedSpots = {}
        for i = 1, maxOptimalPoints do
            limitedSpots[i] = availableSpots[i]
        end
        availableSpots = limitedSpots
    end
    
    -- Функция расчета эффективности маршрута
    local function calculateRouteEfficiency(route, totalTime)
        if totalTime <= 0 then return 0 end
        
        local totalGold, totalXP = 0, 0
        for _, spot in ipairs(route) do
            totalGold = totalGold + spot.gold
            totalXP = totalXP + spot.xp
        end
        
        return ((totalGold * goldWeight) + (totalXP * xpWeight)) / totalTime
    end
    
    -- Рекурсивный поиск оптимального маршрута
    local function findOptimalRoute(remainingSpots, currentPos, currentRoute, currentTime, depth)
        if depth >= settings.pointsCount:Get() or #remainingSpots == 0 then
            return currentRoute, calculateRouteEfficiency(currentRoute, math.max(0.1, currentTime))
        end
        
        local bestRoute, bestEfficiency = currentRoute, calculateRouteEfficiency(currentRoute, math.max(0.1, currentTime))
        
        for i, spot in ipairs(remainingSpots) do
            local newRemainingSpots = {}
            for j, otherSpot in ipairs(remainingSpots) do
                if i ~= j then
                    table.insert(newRemainingSpots, otherSpot)
                end
            end
            
            local travelTime = GridNav.GetTravelTime(currentPos, spot.pos, false, nil, heroMoveSpeed)
            local farmTime = calculateFarmTime(spot)
            local newTotalTime = currentTime + travelTime + farmTime
            
            local newRoute = {table.unpack(currentRoute)}
            table.insert(newRoute, spot)
            
            local optimalRoute, efficiency = findOptimalRoute(newRemainingSpots, spot.pos, newRoute, newTotalTime, depth + 1)
            
            if efficiency > bestEfficiency then
                bestRoute, bestEfficiency = optimalRoute, efficiency
            end
        end
        
        return bestRoute, bestEfficiency
    end
    
    local optimalRoute, _ = findOptimalRoute(availableSpots, heroPosition, {}, 0, 0)
    return optimalRoute
end

-- Выбор алгоритма расчета маршрута
local function calculateFarmRoute()
    if settings.algorithm:Get() == 1 then
        return calculateGreedyRoute()
    else
        return calculateOptimalRoute()
    end
end

-- Константы для управления
local CTRL_KEY = Enum.ButtonCode.KEY_LCONTROL
local LEFT_MOUSE = Enum.ButtonCode.KEY_MOUSE1

-- Функция обновления (вызывается каждый кадр)
farmPattern.OnUpdate = function()
    if not settings.enabled:Get() then return end
    
    local hero = getLocalHero()
    if not hero or not Entity.IsAlive(hero) then return end
    
    local currentTime = GameRules.GetGameTime()
    local heroPosition = Entity.GetAbsOrigin(hero)
    
    -- Обновление данных каждые 0.1 секунды
    if (currentTime - lastUpdateTime) >= 0.1 then
        lastUpdateTime = currentTime
        farmSpots = {}
        local processedPositions = {}
        local searchRadius, allyRadius = settings.searchRadius:Get(), settings.allyRadius:Get()
        
        -- Обработка линейных крипов
        if LIB_HEROES_DATA and LIB_HEROES_DATA.lane_creeps_groups then
            for _, creepGroup in ipairs(LIB_HEROES_DATA.lane_creeps_groups) do
                local position = creepGroup.position
                if (position - heroPosition):Length2D() <= searchRadius then
                    local totalGold = 0
                    for _, creep in pairs(creepGroup.creeps) do
                        totalGold = totalGold + NPC.GetGoldBounty(creep)
                    end
                    
                    local positionKey = tostring(position)
                    if totalGold > 0 and not processedPositions[positionKey] and not hasAlliesNearby(position, allyRadius) then
                        processedPositions[positionKey] = true
                        table.insert(farmSpots, {
                            pos = position,
                            gold = totalGold,
                            isJungle = false,
                            creepCount = countElements(creepGroup.creeps)
                        })
                    end
                end
            end
        end
        
        -- Обработка нейтральных лагерей
        if LIB_HEROES_DATA and LIB_HEROES_DATA.jungle_spots then
            for _, jungleSpot in ipairs(LIB_HEROES_DATA.jungle_spots) do
                local position = jungleSpot.pos or ((jungleSpot.box.min + jungleSpot.box.max) * 0.5)
                if (position - heroPosition):Length2D() <= searchRadius then
                    local goldBounty = Camp.GetGoldBounty(jungleSpot, true)
                    local positionKey = tostring(position)
                    
                    if goldBounty > 0 and not processedPositions[positionKey] and not hasAlliesNearby(position, allyRadius) then
                        processedPositions[positionKey] = true
                        table.insert(farmSpots, {
                            pos = position,
                            gold = goldBounty,
                            isJungle = true
                        })
                    end
                end
            end
        end
        
        -- Расчет оптимального маршрута
        if settings.optimized:Get() then
            calculatedRoute = calculateFarmRoute()
            pathCheckpoints = createRouteWithCheckpoints(hero, calculatedRoute, settings.checkpointCount:Get())
            
            -- Инициализация анимированных точек
            if #animatedPoints ~= #pathCheckpoints then
                animatedPoints = {}
                for i, checkpointGroup in ipairs(pathCheckpoints) do
                    animatedPoints[i] = {}
                    for j, checkpoint in ipairs(checkpointGroup) do
                        animatedPoints[i][j] = Vector(checkpoint.x, checkpoint.y, checkpoint.z)
                    end
                end
            end
            
            currentWaypointIndex = 1
            lastHeroPosition = heroPosition
        else
            calculatedRoute = {}
            pathCheckpoints = {}
            animatedPoints = {}
            currentWaypointIndex = 1
        end
    end
end

-- Функция отрисовки (вызывается каждый кадр)
farmPattern.OnDraw = function()
    if not settings.enabled:Get() then return end
    
    local hero = getLocalHero()
    if not hero or not Entity.IsAlive(hero) then return end
    
    if not settings.optimized:Get() or #calculatedRoute == 0 then return end
    
    -- Анимация точек маршрута
    animateRoutePoints()
    
    local gameTime = getGameTime()
    local gameMinute = math.floor(gameTime % 60)
    local heroPosition = Entity.GetAbsOrigin(hero)
    local heroScreenPos, heroOnScreen = Render.WorldToScreen(heroPosition)
    
    -- Плавное появление/исчезание визуализации
    local targetAlpha = (settings.showVisualization:Get() and 255) or 0
    if fadeAlpha < targetAlpha then
        fadeAlpha = math.min(fadeAlpha + fadeSpeed, targetAlpha)
    elseif fadeAlpha > targetAlpha then
        fadeAlpha = math.max(fadeAlpha - fadeSpeed, targetAlpha)
    end
    
    if fadeAlpha <= 0 then return end
    
    local currentAlpha = math.floor(fadeAlpha)
    local maxPoints = math.min(settings.pointsCount:Get(), #calculatedRoute)
    
    -- Расчет общего золота маршрута
    local totalGold = 0
    for i = 1, maxPoints do
        totalGold = totalGold + calculatedRoute[i].gold
    end
    
    -- Отображение информации о маршруте
    local routeInfo = string.format("Farm Path: %d point(s), ~%d gold", maxPoints, math.floor(totalGold))
    local textWidth, textHeight = Renderer.GetTextSize(1, routeInfo)
    local cursorX, cursorY = Input.GetCursorPos()
    local cursorPos = Vec2(cursorX, cursorY)
    local uiTopLeft = Vec2(uiPosition.x, uiPosition.y)
    local uiBottomRight = Vec2(uiPosition.x + textWidth, uiPosition.y + textHeight)
    
    -- Обработка перетаскивания UI
    if settings.ctrlToDrag:Get() and Input.IsKeyDown(CTRL_KEY) and Input.IsKeyDownOnce(LEFT_MOUSE) and
       cursorPos.x >= uiTopLeft.x and cursorPos.x <= uiBottomRight.x and
       cursorPos.y >= uiTopLeft.y and cursorPos.y <= uiBottomRight.y then
        isDragging = true
        dragOffset = uiTopLeft - cursorPos
    end
    
    if isDragging and Input.IsKeyDown(LEFT_MOUSE) then
        local newCursorX, newCursorY = Input.GetCursorPos()
        uiPosition.x = newCursorX + dragOffset.x
        uiPosition.y = newCursorY + dragOffset.y
    end
    
    if isDragging and not Input.IsKeyDown(LEFT_MOUSE) then
        isDragging = false
    end
    
    -- Отрисовка текста с информацией
    Renderer.SetDrawColor(255, 255, 255, currentAlpha)
    Renderer.DrawText(1, uiPosition.x, uiPosition.y, routeInfo)
    
    -- Отрисовка динамических точек маршрута
    if settings.dynamicUpdate:Get() then
        local animatedCheckpoints = animatedPoints
        
        -- Текущие активные точки
        if currentWaypointIndex <= #animatedCheckpoints then
            for _, checkpoint in ipairs(animatedCheckpoints[currentWaypointIndex]) do
                local screenPos, onScreen = Render.WorldToScreen(checkpoint)
                if onScreen then
                    Renderer.SetDrawColor(255, 165, 0, currentAlpha)
                    Renderer.DrawFilledCircle(screenPos.x, screenPos.y, 5)
                end
            end
        end
        
        -- Будущие точки маршрута (полупрозрачные)
        for i = currentWaypointIndex + 1, #animatedCheckpoints do
            for _, checkpoint in ipairs(animatedCheckpoints[i]) do
                local screenPos, onScreen = Render.WorldToScreen(checkpoint)
                if onScreen then
                    Renderer.SetDrawColor(255, 165, 0, math.floor(currentAlpha * 0.5))
                    Renderer.DrawFilledCircle(screenPos.x, screenPos.y, 3)
                end
            end
        end
    end
    
    -- Отрисовка основных точек маршрута
    local visualColor = settings.visualColor:Get()
    local colorR, colorG, colorB = math.floor(visualColor.r), math.floor(visualColor.g), math.floor(visualColor.b)
    local previousScreenPos, previousOnScreen
    
    for i = 1, maxPoints do
        local farmSpot = calculatedRoute[i]
        local screenPos, onScreen = Render.WorldToScreen(farmSpot.pos)
        local pointColorR, pointColorG, pointColorB = colorR, colorG, colorB
        local showStackWarning, stackCountdown = false, nil
        
        -- Предупреждение о стаке (для нейтральных лагерей)
        if i == 1 and farmSpot.isJungle and gameMinute >= 45 and gameMinute <= 56 then
            showStackWarning = true
            pointColorR = 255 - colorR
            pointColorG = 255 - colorG 
            pointColorB = 255 - colorB
            
            if gameMinute <= 53 then
                stackCountdown = tostring(53 - gameMinute)
            end
        end
        
        if onScreen then
            local circleSize = settings.circleSize:Get()
            
            -- Отрисовка круга точки
            Renderer.SetDrawColor(pointColorR, pointColorG, pointColorB, currentAlpha)
            Renderer.DrawFilledCircle(screenPos.x, screenPos.y, circleSize)
            
            -- Номер точки
            local pointNumber = tostring(i)
            local numberWidth, numberHeight = Renderer.GetTextSize(1, pointNumber)
            Renderer.SetDrawColor(255, 255, 255, currentAlpha)
            Renderer.DrawText(1, screenPos.x - (numberWidth * 0.5), screenPos.y - (numberHeight * 0.5), pointNumber)
            
            -- Предупреждение о стаке
            if showStackWarning then
                local stackText = "STACK!"
                if stackCountdown then
                    stackText = stackText .. " " .. stackCountdown
                end
                local stackWidth, stackHeight = Renderer.GetTextSize(1, stackText)
                Renderer.SetDrawColor(pointColorR, pointColorG, pointColorB, currentAlpha)
                Renderer.DrawText(1, screenPos.x - (stackWidth * 0.5), ((screenPos.y - circleSize) - stackHeight) - 2, stackText)
            end
            
            -- Количество золота
            local goldText = tostring(math.floor(farmSpot.gold))
            local goldWidth, goldHeight = Renderer.GetTextSize(1, goldText)
            Renderer.SetDrawColor(255, 215, 0, currentAlpha)
            Renderer.DrawText(1, screenPos.x - (goldWidth * 0.5), screenPos.y + circleSize + 2, goldText)
        end
        
        -- Отрисовка линий между точками
        local shouldDrawLine
        if i == 1 then
            shouldDrawLine = heroOnScreen or onScreen
            if shouldDrawLine then
                Renderer.SetDrawColor(pointColorR, pointColorG, pointColorB, currentAlpha)
                Renderer.DrawLine(heroScreenPos.x, heroScreenPos.y, screenPos.x, screenPos.y)
            end
        else
            shouldDrawLine = previousOnScreen or onScreen
            if shouldDrawLine then
                Renderer.SetDrawColor(pointColorR, pointColorG, pointColorB, currentAlpha)
                Renderer.DrawLine(previousScreenPos.x, previousScreenPos.y, screenPos.x, screenPos.y)
            end
        end
        
        previousScreenPos, previousOnScreen = screenPos, onScreen
    end
end

-- Возврат основных функций скрипта
return {
    OnUpdate = farmPattern.OnUpdate,
    OnDraw = farmPattern.OnDraw
}