---@diagnostic disable: undefined-global, param-type-mismatch, inject-field

local LastHitScript = {}

-- Создание меню 
local tab = Menu.Create("Scripts", "Main", "Last Hit Pro", "Last Hit Pro")
local mainGroup = tab:Create("Main Settings")

-- Основные настройки
local ui = {}
ui.enabled = mainGroup:Switch("Enable Last Hit", false)
ui.keyBind = mainGroup:Bind("Activation Key", Enum.ButtonCode.KEY_NONE)
ui.toggleMode = mainGroup:Switch("Toggle Mode (Hold if disabled)", true)
ui.attackRange = mainGroup:Slider("Attack Range", 100, 1200, 800)
ui.moveToTarget = mainGroup:Switch("Move to Target", true)
ui.maxMoveDistance = mainGroup:Slider("Max Move Distance", 50, 300, 150)
ui.damageMargin = mainGroup:Slider("Damage Margin %", 0.0, 10.0, 2.0)
ui.enableDeny = mainGroup:Switch("Enable Deny", true)
ui.denyThreshold = mainGroup:Slider("Deny Health Threshold %", 10, 50, 50)
ui.scanFrequency = mainGroup:Slider("Scan Frequency (Hz)", 10, 60, 30)
ui.attackMove = mainGroup:Switch("Attack Move", false)
ui.showPrediction = mainGroup:Combo("Show Prediction", {"Disabled", "Enemy", "Allies", "Both"}, 3)

-- Переменные состояния
local lastAttackTime = 0
local currentTarget = nil
local isActive = false
local lastKeyState = false
local creepHealthHistory = {}
local damageTracker = {}
local lastScanTime = 0
local gameTime = 0
local lastMoveTime = 0
local lastPlayerOrderTime = 0
local predictionIndicators = {}

-- Кэш для оптимизации
local heroStatsCache = {}
local cacheUpdateTime = 0
local spatialCache = {}
local lastSpatialUpdate = 0
local CACHE_DURATION = 0.05 -- 50мс кэш
local SPATIAL_UPDATE_INTERVAL = 0.033 -- 30 FPS для пространственного кэша

-- Константы для точных расчетов
local BASE_ATTACK_POINTS = {
    ["npc_dota_hero_antimage"] = 0.3,
    ["npc_dota_hero_axe"] = 0.4,
    ["npc_dota_hero_bane"] = 0.4,
    ["npc_dota_hero_bloodseeker"] = 0.43,
    ["npc_dota_hero_crystal_maiden"] = 0.4,
    ["npc_dota_hero_drow_ranger"] = 0.4,
    ["npc_dota_hero_earthshaker"] = 0.467,
    ["npc_dota_hero_juggernaut"] = 0.33,
    ["npc_dota_hero_mirana"] = 0.4,
    ["npc_dota_hero_nevermore"] = 0.5,
    ["npc_dota_hero_morphling"] = 0.4,
    ["npc_dota_hero_phantom_lancer"] = 0.4,
    ["npc_dota_hero_puck"] = 0.4,
    ["npc_dota_hero_pudge"] = 0.4,
    ["npc_dota_hero_razor"] = 0.4,
    ["npc_dota_hero_sand_king"] = 0.53,
    ["npc_dota_hero_storm_spirit"] = 0.5,
    ["npc_dota_hero_sven"] = 0.4,
    ["npc_dota_hero_tiny"] = 0.49,
    ["npc_dota_hero_vengefulspirit"] = 0.33,
    ["npc_dota_hero_windrunner"] = 0.4,
    ["npc_dota_hero_zuus"] = 0.35,
    ["npc_dota_hero_kunkka"] = 0.4,
    ["npc_dota_hero_lina"] = 0.4,
    ["npc_dota_hero_lion"] = 0.43,
    ["npc_dota_hero_shadow_shaman"] = 0.4,
    ["npc_dota_hero_slardar"] = 0.36,
    ["npc_dota_hero_tidehunter"] = 0.6,
    ["npc_dota_hero_witch_doctor"] = 0.4,
    ["npc_dota_hero_lich"] = 0.46,
    ["npc_dota_hero_riki"] = 0.4,
    ["npc_dota_hero_enigma"] = 0.4,
    ["npc_dota_hero_tinker"] = 0.35,
    ["npc_dota_hero_sniper"] = 0.17,
    ["npc_dota_hero_necrolyte"] = 0.4,
    ["npc_dota_hero_warlock"] = 0.4,
    ["npc_dota_hero_beastmaster"] = 0.3,
    ["npc_dota_hero_queenofpain"] = 0.4,
    ["npc_dota_hero_venomancer"] = 0.3,
    ["npc_dota_hero_faceless_void"] = 0.4,
    ["npc_dota_hero_skeleton_king"] = 0.4,
    ["npc_dota_hero_death_prophet"] = 0.4,
    ["npc_dota_hero_phantom_assassin"] = 0.3,
    ["npc_dota_hero_pugna"] = 0.4,
    ["npc_dota_hero_templar_assassin"] = 0.4,
    ["npc_dota_hero_viper"] = 0.4,
    ["npc_dota_hero_luna"] = 0.46,
    ["npc_dota_hero_dragon_knight"] = 0.4,
    ["npc_dota_hero_dazzle"] = 0.4,
    ["npc_dota_hero_rattletrap"] = 0.33,
    ["npc_dota_hero_leshrac"] = 0.4,
    ["npc_dota_hero_furion"] = 0.4,
    ["npc_dota_hero_life_stealer"] = 0.4,
    ["npc_dota_hero_dark_seer"] = 0.59,
    ["npc_dota_hero_clinkz"] = 0.4,
    ["npc_dota_hero_omniknight"] = 0.433,
    ["npc_dota_hero_enchantress"] = 0.3,
    ["npc_dota_hero_huskar"] = 0.4,
    ["npc_dota_hero_night_stalker"] = 0.55,
    ["npc_dota_hero_broodmother"] = 0.4,
    ["npc_dota_hero_bounty_hunter"] = 0.59,
    ["npc_dota_hero_weaver"] = 0.64,
    ["npc_dota_hero_jakiro"] = 0.4,
    ["npc_dota_hero_batrider"] = 0.3,
    ["npc_dota_hero_chen"] = 0.4,
    ["npc_dota_hero_spectre"] = 0.3,
    ["npc_dota_hero_doom_bringer"] = 0.5,
    ["npc_dota_hero_ancient_apparition"] = 0.45,
    ["npc_dota_hero_ursa"] = 0.3,
    ["npc_dota_hero_spirit_breaker"] = 0.6,
    ["npc_dota_hero_gyrocopter"] = 0.2,
    ["npc_dota_hero_alchemist"] = 0.35,
    ["npc_dota_hero_invoker"] = 0.4
}

-- Улучшенная система отслеживания урона
function LastHitScript.InitializeCreepTracking(creep)
    if not creep then return end
    
    local creepId = Entity.GetIndex(creep)
    local currentTime = GameRules.GetGameTime()
    
    if not creepHealthHistory[creepId] then
        creepHealthHistory[creepId] = {
            samples = {},
            maxSamples = 30, -- Оптимизировано для скорости
            lastUpdate = currentTime,
            creepType = NPC.GetUnitName(creep),
            maxHealth = Entity.GetMaxHealth(creep)
        }
        
        damageTracker[creepId] = {
            instantDPS = 0,
            averageDPS = 0,
            trendDPS = 0,
            lastDamage = 0,
            confidence = 0,
            lastUpdate = currentTime,
            predictedDeathTime = 0
        }
    end
end

-- Оптимизированное кэширование статистик героя с правильными расчетами
function LastHitScript.GetCachedHeroStats(hero)
    local heroId = Entity.GetIndex(hero)
    local currentTime = GameRules.GetGameTime()
    
    if not heroStatsCache[heroId] or (currentTime - cacheUpdateTime) > CACHE_DURATION then
        local heroName = NPC.GetUnitName(hero)
        local baseAttackPoint = BASE_ATTACK_POINTS[heroName] or 0.3
        
        -- Правильный расчет скорости атаки согласно Wiki
        local baseAttackTime = NPC.GetBaseAttackTime and NPC.GetBaseAttackTime(hero) or 1.7
        local attackSpeed = NPC.GetAttackSpeed and NPC.GetAttackSpeed(hero) or 100
        local attacksPerSecond = NPC.GetAttacksPerSecond(hero)
        
        -- Расчет эффективного времени атаки: BAT / (1 + IAS/100)
        -- где IAS = Attack Speed - 100
        local increasedAttackSpeed = (attackSpeed - 100) / 100
        local effectiveAttackTime = baseAttackTime / (1 + increasedAttackSpeed)
        
        -- Расчет эффективной точки атаки с учетом скорости атаки
        local effectiveAttackPoint = baseAttackPoint / (1 + increasedAttackSpeed)
        
        heroStatsCache[heroId] = {
            -- Базовые характеристики атаки
            baseAttackTime = baseAttackTime,
            attackSpeed = attackSpeed,
            increasedAttackSpeed = increasedAttackSpeed,
            attacksPerSecond = attacksPerSecond,
            effectiveAttackTime = effectiveAttackTime,
            
            -- Анимация атаки
            baseAttackPoint = baseAttackPoint,
            effectiveAttackPoint = effectiveAttackPoint,
            actualAttackPoint = effectiveAttackPoint, -- Используем эффективную точку атаки
            
            -- Backswing тоже зависит от скорости атаки
            baseBackswing = (baseAttackTime - baseAttackPoint),
            effectiveBackswing = (effectiveAttackTime - effectiveAttackPoint),
            
            -- Правильные методы урона
            trueDamage = NPC.GetTrueDamage(hero),
            trueMaxDamage = NPC.GetTrueMaximumDamage(hero),
            bonusDamage = NPC.GetBonusDamage and NPC.GetBonusDamage(hero) or 0,
            
            -- Остальные характеристики
            attackRange = NPC.GetAttackRange(hero),
            moveSpeed = NPC.GetMoveSpeed(hero),
            turnRate = NPC.GetTurnRate(hero),
            projectileSpeed = NPC.IsRanged(hero) and NPC.GetAttackProjectileSpeed(hero) or 0,
            hullRadius = NPC.GetHullRadius(hero),
            isRanged = NPC.IsRanged(hero)
        }
        cacheUpdateTime = currentTime
    end
    
    return heroStatsCache[heroId]
end

-- расчет времени атаки с учетом механик из Wiki
function LastHitScript.CalculatePreciseAttackTime(hero, target)
    if not hero or not target then return 0 end
    
    local stats = LastHitScript.GetCachedHeroStats(hero)
    local heroPos = Entity.GetAbsOrigin(hero)
    local targetPos = Entity.GetAbsOrigin(target)
    
    -- Быстрый расчет 2D расстояния
    local deltaVec = targetPos - heroPos
    local distance2D = deltaVec:Length2D()
    
    -- Точный расчет угла поворота
    local heroFacing = Entity.GetRotation(hero):GetForward()
    local directionToTarget = deltaVec:Normalized()
    local angleDiff = math.acos(math.max(-1, math.min(1, heroFacing:Dot(directionToTarget))))
    
    -- Время поворота с учетом мертвой зоны 11.5°
    local deadZone = math.rad(11.5)
    local faceTime = math.max(0, (angleDiff - deadZone) / stats.turnRate)
    
    -- Время движения
    local targetHullRadius = NPC.GetHullRadius(target)
    local attackRange = stats.attackRange + stats.hullRadius + targetHullRadius
    local moveDistance = math.max(0, distance2D - attackRange)
    local moveTime = moveDistance > 0 and (moveDistance / stats.moveSpeed) or 0
    
    -- Используем эффективную точку атаки 
    local attackPoint = stats.effectiveAttackPoint
    
    -- Время полета снаряда для дальних героев
    local projectileTime = 0
    if stats.isRanged and stats.projectileSpeed > 0 then
        -- Снаряд летит от героя до цели
        local effectiveDistance = math.max(0, distance2D - 24)
        projectileTime = effectiveDistance / stats.projectileSpeed
    end
    
    -- Сетевая задержка
    local networkLatency = NetChannel.GetAvgLatency(Enum.Flow.FLOW_OUTGOING)
    
    return faceTime + moveTime + attackPoint + projectileTime + networkLatency
end

-- Улучшенная функция расчета оптимального времени атаки
function LastHitScript.CalculatePerfectAttackTime(hero, creep)
    if not hero or not creep then return math.huge end
    
    local stats = LastHitScript.GetCachedHeroStats(hero)
    local heroDamage = LastHitScript.CalculateHeroDamageToCreep(hero, creep)
    local currentHealth = Entity.GetHealth(creep)
    local attackTime = LastHitScript.CalculatePreciseAttackTime(hero, creep)
    
    -- Предсказываем здоровье крипа в момент попадания
    local predictedHealth = LastHitScript.PredictCreepHealth(creep, attackTime)
    
    -- Проверяем, можем ли мы убить крипа
    if predictedHealth <= heroDamage then
        -- Рассчитываем идеальное время для атаки
        -- Учитываем, что нужно атаковать так, чтобы крип умер точно от нашего удара
        local timeToKill = currentHealth / (damageTracker[Entity.GetIndex(creep)] and damageTracker[Entity.GetIndex(creep)].trendDPS or 1)
        local idealAttackTime = timeToKill - attackTime
        
        -- Добавляем небольшой буфер для компенсации задержек
        local buffer = 0.03 -- 30ms буфер
        return math.max(0, idealAttackTime - buffer)
    end
    
    return math.huge
end

-- расчет урона с использованием API методов
function LastHitScript.CalculateHeroDamageToCreep(hero, creep)
    if not hero or not creep then return 0 end
    
    local stats = LastHitScript.GetCachedHeroStats(hero)
    
    -- Используем среднее значение между минимальным и максимальным уроном
    local avgDamage = (stats.trueDamage + stats.trueMaxDamage) / 2
    local totalDamage = avgDamage + stats.bonusDamage
    
    -- Используем API методы для расчета брони
    local armorValue = NPC.GetPhysicalArmorValue(creep)
    local armorMultiplier = NPC.GetArmorDamageMultiplier(creep)
    
    -- Дополнительные множители урона
    local damageMultiplier = 1.0
    if NPC.GetDamageMultiplierVersus then
        damageMultiplier = NPC.GetDamageMultiplierVersus(hero, creep)
    end
    
    -- Расчет финального урона
    local finalDamage = totalDamage * armorMultiplier * damageMultiplier
    
    -- Учитываем случайность урона (±5%)
    local randomFactor = 0.95 + (math.random() * 0.1)
    
    return math.floor(finalDamage * randomFactor)
end

-- Экспоненциальное сглаживание для предсказания DPS
function LastHitScript.UpdateCreepDamageData(creep)
    if not creep or not Entity.IsAlive(creep) then return end
    
    LastHitScript.InitializeCreepTracking(creep)
    
    local creepId = Entity.GetIndex(creep)
    local currentHealth = Entity.GetHealth(creep)
    local currentTime = gameTime
    
    local history = creepHealthHistory[creepId]
    local tracker = damageTracker[creepId]
    
    -- Добавляем новый образец
    table.insert(history.samples, {
        health = currentHealth,
        time = currentTime,
        regen = NPC.GetHealthRegen(creep) 
    })
    
    -- Ограничиваем количество образцов
    if #history.samples > history.maxSamples then
        table.remove(history.samples, 1)
    end
    
    -- Быстрый расчет DPS с экспоненциальным сглаживанием
    if #history.samples >= 2 then
        local lastSample = history.samples[#history.samples]
        local prevSample = history.samples[#history.samples - 1]
        local timeDiff = lastSample.time - prevSample.time
        
        if timeDiff > 0 then
            local healthDiff = prevSample.health - lastSample.health
            local instantDPS = math.max(0, healthDiff / timeDiff)
            
            -- Экспоненциальное сглаживание (α = 0.3 для стабильности)
            local alpha = 0.3
            if tracker.averageDPS == 0 then
                tracker.averageDPS = instantDPS
                tracker.trendDPS = instantDPS
            else
                tracker.averageDPS = alpha * instantDPS + (1 - alpha) * tracker.averageDPS
                tracker.trendDPS = tracker.averageDPS
            end
            
            tracker.instantDPS = instantDPS
            tracker.confidence = math.min(1.0, #history.samples / 10)
            
            -- Быстрое предсказание времени смерти
            if tracker.trendDPS > 0 then
                tracker.predictedDeathTime = currentTime + (currentHealth / tracker.trendDPS)
            end
        end
    end
    
    history.lastUpdate = currentTime
    tracker.lastUpdate = currentTime
end

-- Высокоскоростное предсказание здоровья крипа
function LastHitScript.PredictCreepHealth(creep, timeAhead)
    if not creep or not Entity.IsAlive(creep) then return 0 end
    
    local creepId = Entity.GetIndex(creep)
    local tracker = damageTracker[creepId]
    
    if not tracker or gameTime - tracker.lastUpdate > 1.5 then
        return Entity.GetHealth(creep)
    end
    
    local currentHealth = Entity.GetHealth(creep)
    
    -- Используем наиболее подходящий DPS
    local selectedDPS = tracker.trendDPS
    if tracker.confidence < 0.5 then
        selectedDPS = tracker.averageDPS * 0.7
    end
    
    -- Учитываем регенерацию здоровья
    local healthRegen = NPC.GetHealthRegen(creep)
    local netDPS = math.max(0, selectedDPS - healthRegen)
    
    local predictedDamage = netDPS * timeAhead
    local predictedHealth = currentHealth - predictedDamage
    
    return math.max(1, predictedHealth)
end

-- Оптимизированное сканирование крипов
function LastHitScript.HighFrequencyScan()
    local currentTime = GameRules.GetGameTime()
    local scanInterval = 1.0 / ui.scanFrequency:Get()
    
    if currentTime - lastScanTime < scanInterval then
        return
    end
    
    lastScanTime = currentTime
    gameTime = currentTime
    
    local myHero = Heroes.GetLocal()
    if not myHero then return end
    
    local heroPos = Entity.GetAbsOrigin(myHero)
    local heroTeam = Entity.GetTeamNum(myHero)
    
    -- Оптимизированный радиус сканирования
    local scanRadius = ui.attackRange:Get() + ui.maxMoveDistance:Get() + 300
    
    -- Получаем всех крипов одним вызовом
    local allNPCs = NPCs.InRadius(heroPos, scanRadius, heroTeam, Enum.TeamType.TEAM_BOTH)
    
    for _, npc in ipairs(allNPCs) do
        if NPC.IsLaneCreep(npc) and Entity.IsAlive(npc) then
            LastHitScript.UpdateCreepDamageData(npc)
        end
    end
end

-- быстрый поиск оптимальной цели
function LastHitScript.FindOptimalTarget()
    local myHero = Heroes.GetLocal()
    if not myHero or not Entity.IsAlive(myHero) then return nil end
    
    local heroPos = Entity.GetAbsOrigin(myHero)
    local heroTeam = Entity.GetTeamNum(myHero)
    local searchRadius = ui.attackRange:Get() + ui.maxMoveDistance:Get()
    
    local bestTarget = nil
    local bestPriority = -1
    local damageMargin = ui.damageMargin:Get() / 100
    
    -- Сканируем врагов для ласт-хита
    local enemies = NPCs.InRadius(heroPos, searchRadius, heroTeam, Enum.TeamType.TEAM_ENEMY)
    for _, creep in ipairs(enemies) do
        if NPC.IsLaneCreep(creep) and Entity.IsAlive(creep) then
            local heroDamage = LastHitScript.CalculateHeroDamageToCreep(myHero, creep)
            local attackTime = LastHitScript.CalculatePreciseAttackTime(myHero, creep)
            local predictedHealth = LastHitScript.PredictCreepHealth(creep, attackTime)
            
            -- Проверяем возможность ласт-хита
            if predictedHealth <= heroDamage * (1 + damageMargin) and 
               predictedHealth >= heroDamage * (1 - damageMargin) and
               attackTime < 3.0 then
                local priority = 1000 - predictedHealth + (3.0 - attackTime) * 100
                if priority > bestPriority then
                    bestPriority = priority
                    bestTarget = creep
                end
            end
        end
    end
    
    -- Сканируем союзников для денаев
    if ui.enableDeny:Get() and not bestTarget then
        local allies = NPCs.InRadius(heroPos, searchRadius, heroTeam, Enum.TeamType.TEAM_FRIEND)
        for _, creep in ipairs(allies) do
            if NPC.IsLaneCreep(creep) and Entity.IsAlive(creep) then
                local maxHealth = Entity.GetMaxHealth(creep)
                local denyThreshold = (ui.denyThreshold:Get() / 100) * maxHealth
                local currentHealth = Entity.GetHealth(creep)
                
                if currentHealth <= denyThreshold then
                    local heroDamage = LastHitScript.CalculateHeroDamageToCreep(myHero, creep)
                    local attackTime = LastHitScript.CalculatePreciseAttackTime(myHero, creep)
                    local predictedHealth = LastHitScript.PredictCreepHealth(creep, attackTime)
                    
                    if predictedHealth <= heroDamage * (1 + damageMargin) and
                       predictedHealth >= heroDamage * (1 - damageMargin) and
                       attackTime < 3.0 then
                        local priority = 500 - predictedHealth + (3.0 - attackTime) * 50
                        if priority > bestPriority then
                            bestPriority = priority
                            bestTarget = creep
                        end
                    end
                end
            end
        end
    end
    
    return bestTarget
end

-- Проверка активности игрока
function LastHitScript.IsPlayerActive()
    local myHero = Heroes.GetLocal()
    if not myHero then return false end
    
    -- Проверка недавних команд
    if (gameTime - lastPlayerOrderTime) < 0.2 then
        return true
    end
    
    -- Проверка каста способностей
    if NPC.IsChannellingAbility(myHero) then return true end
    if NPC.HasModifier(myHero, "modifier_teleporting") then return true end
    
    -- Проверка невидимости
    if NPC.HasState(myHero, Enum.ModifierState.MODIFIER_STATE_INVISIBLE) then
        return true
    end
    
    return false
end

-- Attack Move функция
function LastHitScript.HandleAttackMove()
    if not ui.attackMove:Get() then return end
    
    local myHero = Heroes.GetLocal()
    if not myHero or not Entity.IsAlive(myHero) then return end
    
    if NPC.IsTurning(myHero) or NPC.IsRunning(myHero) then
        lastMoveTime = gameTime + 1.5
        return
    end
    
    local timeSinceAttack = gameTime - lastAttackTime
    local timeSinceMove = gameTime - lastMoveTime
    local stats = LastHitScript.GetCachedHeroStats(myHero)
    
    if timeSinceAttack > (stats.actualAttackPoint + 0.03) and timeSinceMove > 0.3 then
        local currentPos = Entity.GetAbsOrigin(myHero)
        local randomOffset = Vector(
            math.random(-50, 50),
            math.random(-50, 50),
            0
        )
        local newPos = currentPos + randomOffset
        
        NPC.MoveTo(myHero, newPos, false)
        lastMoveTime = gameTime + 2
    end
end

-- Отрисовка предсказаний
function LastHitScript.DrawPredictionIndicators()
    local showMode = ui.showPrediction:Get()
    if showMode == 0 then return end
    
    local myHero = Heroes.GetLocal()
    if not myHero or not Entity.IsAlive(myHero) then return end
    
    local myTeam = Entity.GetTeamNum(myHero)
    
    for creepId, tracker in pairs(damageTracker) do
        local creep = Entity.Get(creepId)
        if creep and Entity.IsAlive(creep) and tracker.predictedDeathTime > 0 then
            local creepTeam = Entity.GetTeamNum(creep)
            local isEnemy = creepTeam ~= myTeam
            
            if (showMode == 3) or 
               (showMode == 1 and isEnemy) or 
               (showMode == 2 and not isEnemy) then
                
                local timeDiff = tracker.predictedDeathTime - gameTime
                if timeDiff > -2.0 then
                    local pos = Entity.GetAbsOrigin(creep)
                    local healthBarOffset = NPC.GetHealthBarOffset(creep)
                    pos.z = pos.z + healthBarOffset
                    local x, y, visible = Renderer.WorldToScreen(pos)
                    
                    if visible then
                        local attackTime = LastHitScript.CalculatePreciseAttackTime(myHero, creep)
                        
                        if timeDiff > (attackTime + 0.1) then
                            Renderer.SetDrawColor(50, 255, 50, 220) -- Зеленый - рано
                        elseif timeDiff > -0.05 then
                            Renderer.SetDrawColor(255, 255, 0, 220) -- Желтый - готов
                        else
                            Renderer.SetDrawColor(255, 50, 50, 220) -- Красный - поздно
                            tracker.predictedDeathTime = 0
                        end
                        
                        Renderer.DrawFilledRect(x-8, y-4, 16, 8)
                    end
                else
                    tracker.predictedDeathTime = 0
                end
            end
        end
    end
end

-- Обработка команд игрока
function LastHitScript.OnPrepareUnitOrders(orders)
    if orders and orders.order > 1 then
        lastPlayerOrderTime = gameTime
    end
    return true
end

-- Основной цикл с максимальной оптимизацией
local lastMainUpdate = 0
local adaptiveUpdateRate = 30

function LastHitScript.OnUpdate()
    local currentTime = GameRules.GetGameTime()
    local updateInterval = 1.0 / adaptiveUpdateRate
    
    if currentTime - lastMainUpdate < updateInterval then
        return
    end
    lastMainUpdate = currentTime
    
    -- Проверка активации
    local keyPressed = Input.IsKeyDown(ui.keyBind:Get())
    
    if ui.toggleMode:Get() then
        if keyPressed and not lastKeyState then
            isActive = not isActive
        end
    else
        isActive = keyPressed
    end
    
    lastKeyState = keyPressed
    
    if not ui.enabled:Get() or not isActive then
        adaptiveUpdateRate = 10
        return
    end
    
    adaptiveUpdateRate = ui.scanFrequency:Get()
    gameTime = currentTime
    
    if LastHitScript.IsPlayerActive() then
        return
    end
    
    local myHero = Heroes.GetLocal()
    if not myHero or not Entity.IsAlive(myHero) then return end
    
    -- Обновляем данные
    LastHitScript.HighFrequencyScan()
    
    -- Обрабатываем Attack Move
    LastHitScript.HandleAttackMove()
    
    -- Ищем цель
    local target = LastHitScript.FindOptimalTarget()
    
    if target and (currentTime - lastAttackTime) > 0.05 then
        -- Движение к цели
        if ui.moveToTarget:Get() then
            local heroPos = Entity.GetAbsOrigin(myHero)
            local targetPos = Entity.GetAbsOrigin(target)
            local distance2D = (targetPos - heroPos):Length2D()
            local stats = LastHitScript.GetCachedHeroStats(myHero)
            
            if distance2D > stats.attackRange and 
               distance2D < (stats.attackRange + ui.maxMoveDistance:Get()) then
                -- Используем правильный API для движения
                Player.PrepareUnitOrders(
                    Players.GetLocal(),
                    Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION,
                    nil,
                    targetPos,
                    nil,
                    Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_HERO_ONLY,
                    myHero,
                    false
                )
            end
        end
        
        -- Атакуем цель
        Player.PrepareUnitOrders(
            Players.GetLocal(),
            Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET,
            target,
            nil,
            nil,
            Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_HERO_ONLY,
            myHero,
            false
        )
        
        -- Обновляем время последней атаки
        local stats = LastHitScript.GetCachedHeroStats(myHero)
        lastAttackTime = currentTime + stats.actualAttackPoint
        currentTarget = target
    else
        currentTarget = nil
    end
end

-- Функция отрисовки
function LastHitScript.OnDraw()
    if ui.enabled:Get() and isActive then
        LastHitScript.DrawPredictionIndicators()
    end
end

-- Регистрация коллбэков
return {
    OnUpdate = LastHitScript.OnUpdate,
    OnDraw = LastHitScript.OnDraw,
    OnPrepareUnitOrders = LastHitScript.OnPrepareUnitOrders
}
