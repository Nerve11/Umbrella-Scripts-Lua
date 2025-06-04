local AutoFortify = {}
local localHero = nil
local lastFortifyTime = 0
local fortifyCooldown = 5

-- Create menu
local menu = Menu.Create("Scripts", "User Scripts", "Auto Fortify")
menu:Icon("\u{f00c}")

local settings = menu:Create("Settings"):Create("Group")
local config = {}

-- Menu options
config.enabled = settings:Switch("Enable Auto Fortify", true, "\u{f00c}")
config.tickThreshold = settings:Slider("Tick Threshold", 1, 12, 10, function(value)
    if value == 0 then
        return "Disabled"
    end
    return tostring(value)
end)

-- Get local hero instance
local function getLocalHero()
    if not localHero then
        localHero = Heroes.GetLocal()
    end
    return localHero
end

-- Check if enemy is in lane with allied creeps (threat detection)
local function isEnemyThreatToCreeps(enemyHero, localHero)
    local enemyPosition = Entity.GetAbsOrigin(enemyHero)
    local localPosition = Entity.GetAbsOrigin(localHero)
    local direction = (localPosition - enemyPosition):Normalized()
    
    local maxDistance = 1250  -- Maximum check distance
    local laneWidth = 150     -- Lane width for creep detection
    
    -- Get all allied lane creeps
    local alliedCreeps = NPCs.GetAll(function(npc)
        return NPC.IsLaneCreep(npc) and 
               Entity.IsSameTeam(npc, localHero) and 
               Entity.IsAlive(npc)
    end)
    
    -- Check if any allied creeps are in the threat zone
    for _, creep in pairs(alliedCreeps) do
        local creepPosition = Entity.GetAbsOrigin(creep)
        local vectorToCreep = creepPosition - enemyPosition
        local projectionLength = vectorToCreep:Dot(direction)
        local perpendicularDistance = (vectorToCreep - (direction * projectionLength)):Length()
        
        -- Check if creep is within threat zone
        if projectionLength > 0 and 
           projectionLength < maxDistance and 
           perpendicularDistance < laneWidth then
            return true
        end
    end
    
    return false
end

-- Activate fortify with cooldown check
local function activateFortify()
    local currentTime = GameRules.GetGameTime()
    
    -- Check cooldown
    if (currentTime - lastFortifyTime) < fortifyCooldown then
        return false
    end
    
    -- Issue fortify command
    Player.PrepareUnitOrders(
        Players.GetLocal(),
        Enum.UnitOrder.DOTA_UNIT_ORDER_GLYPH,
        nil, nil, nil,
        Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY,
        localHero
    )
    
    lastFortifyTime = currentTime
    print("Fortify activated!")
    return true
end

-- Track Monkey King casting states
local monkeyKingTracker = {}

-- Main update function
AutoFortify.OnUpdate = function()
    -- Check if script is enabled
    if not config.enabled:Get() then
        return
    end
    
    local hero = getLocalHero()
    if not hero or not Entity.IsAlive(hero) then
        return
    end
    
    -- Check all enemy heroes
    for _, enemyHero in pairs(Heroes.GetAll()) do
        if not Entity.IsSameTeam(hero, enemyHero) and Entity.IsAlive(enemyHero) then
            
            -- Check if enemy has quad tap bonuses modifier
            if NPC.HasModifier(enemyHero, "modifier_monkey_king_quadruple_tap_bonuses") then
                
                -- Verify it's actually Monkey King
                if NPC.GetUnitName(enemyHero) == "npc_dota_hero_monkey_king" then
                    
                    -- Get Boundless Strike ability
                    local boundlessStrike = NPC.GetAbility(enemyHero, "monkey_king_boundless_strike")
                    
                    if boundlessStrike and Ability.IsInAbilityPhase(boundlessStrike) then
                        
                        -- Initialize tracker for this Monkey King if not exists
                        if not monkeyKingTracker[enemyHero] then
                            monkeyKingTracker[enemyHero] = {
                                tickCount = 0,
                                fortifyActivated = false
                            }
                        end
                        
                        monkeyKingTracker[enemyHero].tickCount = monkeyKingTracker[enemyHero].tickCount + 1
                        print("Monkey King casting tick: " .. monkeyKingTracker[enemyHero].tickCount)

                        if monkeyKingTracker[enemyHero].tickCount >= config.tickThreshold:Get() and
                           not monkeyKingTracker[enemyHero].fortifyActivated then
                            if isEnemyThreatToCreeps(enemyHero, hero) then
                                activateFortify()
                                monkeyKingTracker[enemyHero].fortifyActivated = true
                            end
                        end
                    else
                        monkeyKingTracker[enemyHero] = nil
                    end
                else
                    monkeyKingTracker[enemyHero] = nil
                end
            else
                monkeyKingTracker[enemyHero] = nil
            end
        end
    end
end

return AutoFortify