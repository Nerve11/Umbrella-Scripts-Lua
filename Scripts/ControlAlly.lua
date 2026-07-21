--[[
    Control Ally Remake — multi-hero ally control on the local Combo Key.
    Selected controllable allies cast abilities/items, chase the locked target,
    and run special AI (Invoker, Meepo, Alchemist, etc.) while the key is held.
--]]

local toggleOwnershipRegistry = {}

local ControlAlly = {
	UI = {},
	Runtime = {
		initialized = false,
		wasInGame = false,
		inSession = false,
		lastUpdateAt = -math.huge,
		lastRosterScanAt = -math.huge,
		lastControllerScanAt = -math.huge,
		lastEnemyScanAt = -math.huge,
		lastAllyScanAt = -math.huge,
		lastMenuSyncAt = -math.huge,
		lastBuiltinBindScanAt = -math.huge,
		invokerFastUntil = -math.huge,
		rosterInitialized = false,
		rosterSignature = "",
		controllerSignature = "",
		actionMenuSignature = "",
		itemMenuSignature = "",
		roster = {},
		rosterById = {},
		playerLabelToId = {},
		controllers = {},
		allies = {},
		controllerStates = {},
		selectedPlayerIds = {},
		abilityEnabled = {},
		itemEnabled = {},
		enemies = {},
		lockedTarget = nil,
		lastTargetSwitchAt = -math.huge,
		disableReservations = {},
		linkensReservations = {},
		effectReservations = {},
		supportReservations = {},
		positionReservations = {},
		meepoNetChains = {},
		meepoPlans = {},
		activityCache = {},
		toggleOwnershipRegistry = toggleOwnershipRegistry,
		cloneCountByPlayer = {},
		orderBudget = 0,
		orderSequence = 0,
		sessionGeneration = 0,
		roundRobinIndex = 1,
		localPlayer = nil,
		localPlayerId = nil,
		localHero = nil,
		builtinComboBind = nil,
		builtinComboHeroName = nil,
	},
	Constants = {
		UPDATE_INTERVAL = 0.03,
		ROSTER_SCAN_INTERVAL = 0.50,
		CONTROLLER_SCAN_INTERVAL = 0.15,
		ENEMY_SCAN_INTERVAL = 0.03,
		ALLY_SCAN_INTERVAL = 0.05,
		MENU_SYNC_INTERVAL = 0.50,
		BUILTIN_BIND_SCAN_INTERVAL = 1.00,
		CONTROLLER_THINK_INTERVAL = 0.05,
		ORDER_GAP = 0.06,
		ATTACK_RESEND_INTERVAL = 0.32,
		MOVE_RESEND_INTERVAL = 0.30,
		CAST_DEDUP_INTERVAL = 0.22,
		MAX_ORDERS_PER_UPDATE = 4,
		MAX_CASTS_BEFORE_ATTACK = 2,
		CAST_RANGE_BUFFER = 55,
		TARGET_SWITCH_CURSOR_RADIUS = 425,
		TARGET_LOCK_LEASH = 1.35,
		DEFAULT_CAST_RANGE = 650,
		DEFAULT_NO_TARGET_RADIUS = 450,
		DEFAULT_POINT_RADIUS = 250,
		INVOKER_ORB_GAP = 0.010,
		INVOKER_INTERNAL_ORDER_GAP = 0.012,
		INVOKER_POST_INVOKE_WAIT = 0.035,
		INVOKER_COMBO_CAST_TOLERANCE = 0.09,
		INVOKER_COMBO_LATE_TOLERANCE = 0.16,
		INVOKER_COMBO_FINISH_GRACE = 0.65,
		INVOKER_TORNADO_HIT_GRACE = 0.25,
		ICE_WALL_POSITION_TOLERANCE = 8,
		ICE_WALL_FACE_ANGLE = 0.09,
		FACE_RESEND_INTERVAL = 0.08,
		MEEPO_NET_CHAIN_OVERLAP = 0.08,
		MEEPO_NET_HIT_GRACE = 0.22,
		REFRESHER_MIN_TOTAL_COOLDOWN = 12,
		TINKER_REARM_GAP = 0.85,
		GHOST_WALK_EXIT_HEALTH = 42,
		MOTION_LOCK_MAX = 3.50,
		PENDING_CHANNEL_END_DEBOUNCE = 0.06,
		PENDING_PHASE_HARD_TIMEOUT = 2.50,
		ICE_WALL_POSITION_TIMEOUT = 1.25,
		ALCHEMIST_BREW_FALLBACK = 7.5,
	},
	Profiles = {
		Heroes = {},
		GlobalAbilities = {},
		InvokerSpells = {},
		Items = {},
		SupportItems = {},
		HiddenAbilities = {},
		AbilityRulesById = nil,
		AbilityAliases = {
			kez_falcon_rush_ad = "kez_falcon_rush",
			kez_talon_toss_ad = "kez_talon_toss",
			kez_shodo_sai_ad = "kez_shodo_sai",
			kez_ravens_veil_ad = "kez_ravens_veil",
		},
		InternalInvokerAbilities = {
			invoker_quas = true,
			invoker_wex = true,
			invoker_exort = true,
			invoker_invoke = true,
		},
		RefreshableTinkerActions = {},
	},
	Utils = {},
	Menu = {},
	Roster = {},
	Targeting = {},
	Orders = {},
	AbilityAI = {},
	ItemAI = {},
	SupportAI = {},
	InvokerAI = {},
	MeepoAI = {},
	AlchemistAI = {},
	TechiesAI = {},
	KezAI = {},
	SpecialAI = {},
	TinkerAI = {},
	Combat = {},
}

ControlAlly.Profiles.HiddenAbilities = {
	tinker_keen_teleport = true,
	tinker_eureka = true,
	arc_warden_tempest_recall = true,
	invoker_quas = true,
	invoker_wex = true,
	invoker_exort = true,
	invoker_invoke = true,
	invoker_empty1 = true,
	invoker_empty2 = true,
	furion_teleportation = true,
	furion_force_of_nature = true,
	wisp_relocate = true,
	wisp_tether_break = true,
	chen_holy_persuasion = true,
	chen_summon_convert = true,
	doom_bringer_devour = true,
	life_stealer_infest = true,
	pudge_eject = true,
	phoenix_icarus_dive_stop = true,
	hoodwink_sharpshooter_release = true,
	primal_beast_onslaught_release = true,
	techies_reactive_tazer_stop = true,
	techies_focused_detonate = true,
	techies_minefield_sign = true,
	faceless_void_time_walk_reverse = true,
	morphling_morph = true,
	morphling_replicate = true,
	morphling_morph_replicate = true,
}

ControlAlly.Profiles.GlobalAbilities = {
	ogre_magi_bloodlust = {
		policy = "self",
		priority = 52,
		combatBuff = true,
		selfModifiers = { "modifier_ogre_magi_bloodlust" },
	},
	magnataur_empower = {
		policy = "self",
		priority = 48,
		combatBuff = true,
		selfModifiers = { "modifier_magnataur_empower" },
	},
	lich_frost_shield = {
		policy = "self",
		priority = 62,
		defensiveHealthPct = 80,
		selfModifiers = { "modifier_lich_frost_shield" },
	},
	abaddon_aphotic_shield = {
		policy = "self",
		priority = 82,
		defensiveHealthPct = 72,
		selfModifiers = { "modifier_abaddon_aphotic_shield" },
		urgent = true,
	},
	dazzle_shallow_grave = {
		policy = "self",
		priority = 120,
		defensiveHealthPct = 24,
		selfModifiers = { "modifier_dazzle_shallow_grave" },
		urgent = true,
	},
	legion_commander_press_the_attack = {
		policy = "self",
		priority = 78,
		defensiveHealthPct = 68,
		selfModifiers = { "modifier_legion_commander_press_the_attack" },
		urgent = true,
	},
	windrunner_windrun = {
		policy = "noTarget",
		priority = 76,
		defensiveHealthPct = 52,
		radiusSpecial = "radius",
		selfModifiers = { "modifier_windrunner_windrun" },
		urgent = true,
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_arc_warden = {
	abilities = {
		arc_warden_tempest_double = {
			policy = "selfPosition",
			priority = 125,
			mainOnly = true,
			requiresNoClone = true,
			requiresTarget = true,
			urgent = true,
		},
		arc_warden_flux = {
			policy = "enemy",
			priority = 98,
			disable = false,
			requiresIsolated = true,
			isolationRadiusSpecial = "search_radius",
			allowStacking = true,
		},
		arc_warden_magnetic_field = {
			policy = "selfPosition",
			priority = 72,
			enemyRadiusSpecial = "radius",
			requiresCombatPressure = true,
			selfModifiers = {
				"modifier_arc_warden_magnetic_field_evasion",
				"modifier_arc_warden_magnetic_field_attack_speed",
			},
		},
		arc_warden_spark_wraith = {
			policy = "point",
			priority = 68,
			radiusSpecial = "radius",
			delaySpecial = "base_activation_delay",
		},
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_tinker = {
	abilities = {
		tinker_keen_teleport = { policy = "disabled" },
		tinker_rearm = { policy = "special" },
		tinker_laser = { policy = "enemy", priority = 105 },
		tinker_warp_grenade = { policy = "enemy", priority = 92, disable = true },
		tinker_march_of_the_machines = {
			policy = "point",
			priority = 66,
			radiusSpecial = "radius",
		},
		tinker_deploy_turrets = {
			policy = "point",
			priority = 78,
			radiusSpecial = "drop_aoe_radius",
			delaySpecial = "drop_delay",
		},
		tinker_defense_matrix = {
			policy = "self",
			priority = 74,
			defensiveHealthPct = 78,
			selfModifiers = { "modifier_tinker_defense_matrix" },
		},
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_techies = {
	abilities = {
		techies_sticky_bomb = {
			policy = "point",
			priority = 88,
			radiusSpecial = "radius",
			projectileSpeedSpecial = "speed",
		},
		techies_reactive_tazer = {
			policy = "self",
			priority = 76,
			combatBuff = true,
			selfModifiers = { "modifier_techies_reactive_tazer" },
		},
		techies_suicide = {
			policy = "point",
			priority = 96,
			radiusSpecial = "radius",
			minimumHealthPct = 38,
		},
		techies_land_mines = {
			policy = "special",
			priority = 68,
			radiusSpecial = "radius",
			positionReservationFamily = "techies_mine",
		},
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_enigma = {
	abilities = {
		enigma_demonic_conversion = {
			policy = "point",
			priority = 58,
		},
		enigma_black_hole = {
			policy = "point",
			priority = 132,
			radiusSpecial = "radius",
			disable = true,
			avoidAllies = true,
			ignoreCaster = true,
			allowMagicImmune = true,
			urgent = true,
		},
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_bristleback = {
	abilities = {
		bristleback_hairball = {
			policy = "point",
			priority = 92,
			radiusSpecial = "radius",
			projectileSpeedSpecial = "projectile_speed",
			allowHidden = true,
		},
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_alchemist = {
	abilities = {
		alchemist_acid_spray = {
			policy = "point",
			priority = 74,
			radiusSpecial = "radius",
			positionReservationFamily = "alchemist_acid_spray",
			durationSpecial = "duration",
		},
		alchemist_chemical_rage = {
			policy = "noTarget",
			priority = 94,
			combatBuff = true,
			selfModifiers = { "modifier_alchemist_chemical_rage" },
		},
		alchemist_berserk_potion = {
			policy = "ally",
			priority = 92,
			allyMode = "buff",
			allowHidden = true,
			menuVisible = true,
		},
		alchemist_unstable_concoction = { policy = "special" },
		alchemist_unstable_concoction_throw = { policy = "special", allowHidden = true },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_faceless_void = {
	abilities = {
		faceless_void_chronosphere = {
			policy = "point",
			priority = 118,
			radiusSpecial = "radius",
			disable = true,
			avoidAllies = true,
			ignoreCaster = true,
			allowMagicImmune = true,
		},
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_muerta = {
	abilities = {
		muerta_dead_shot = { policy = "vectorTarget", priority = 96, disable = true },
		muerta_the_calling = { policy = "point", priority = 82, radiusSpecial = "hit_radius" },
		muerta_pierce_the_veil = {
			policy = "noTarget",
			priority = 108,
			alwaysNoTarget = true,
			selfModifiers = { "modifier_muerta_pierce_the_veil" },
		},
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_nyx_assassin = {
	abilities = {
		nyx_assassin_impale = {
			policy = "point",
			priority = 106,
			disable = true,
			lineProjectile = true,
			radiusSpecial = "width",
			travelDistanceSpecial = "length",
			projectileSpeedSpecial = "speed",
		},
		nyx_assassin_jolt = { policy = "enemy", priority = 86 },
		nyx_assassin_mana_burn = { policy = "enemy", priority = 86 },
		nyx_assassin_spiked_carapace = {
			policy = "noTarget",
			priority = 118,
			requiresRecentDamage = true,
			alwaysNoTarget = true,
			urgent = true,
		},
		nyx_assassin_vendetta = { policy = "noTarget", priority = 92, alwaysNoTarget = true },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_dawnbreaker = {
	abilities = {
		dawnbreaker_fire_wreath = {
			policy = "point",
			priority = 94,
			radiusSpecial = "swipe_radius",
			durationSpecial = "duration",
			committedMotion = true,
		},
		dawnbreaker_celestial_hammer = { policy = "point", priority = 86, radiusSpecial = "projectile_radius" },
		dawnbreaker_converge = { policy = "special", allowHidden = true, menuVisible = true },
		dawnbreaker_solar_guardian = {
			policy = "allyPoint",
			priority = 126,
			allyMode = "save",
			allyHealthPct = 48,
			urgent = true,
		},
		dawnbreaker_land = { policy = "special", allowHidden = true, menuVisible = true },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_omniknight = {
	abilities = {
		omniknight_purification = { policy = "ally", priority = 104, allyMode = "heal", allyHealthPct = 76 },
		omniknight_repel = {
			policy = "ally",
			priority = 100,
			allyMode = "save",
			allyHealthPct = 64,
			allyModifiers = { "modifier_omniknight_repel" },
		},
		omniknight_martyr = { policy = "ally", priority = 112, allyMode = "save", urgent = true },
		omniknight_hammer_of_purity = { policy = "enemy", priority = 78, attackModifier = true },
		omniknight_guardian_angel = {
			policy = "noTarget",
			priority = 124,
			alwaysNoTarget = true,
			requiresRecentDamage = true,
			urgent = true,
		},
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_pangolier = {
	abilities = {
		pangolier_swashbuckle = {
			policy = "vector",
			priority = 98,
			radiusSpecial = "start_radius",
			projectileSpeedSpecial = "dash_speed",
			committedMotion = true,
		},
		pangolier_shield_crash = { policy = "noTarget", priority = 82, radiusSpecial = "radius" },
		pangolier_gyroshell = { policy = "special", priority = 112, durationSpecial = "duration" },
		pangolier_gyroshell_stop = { policy = "special", allowHidden = true },
		pangolier_rollup = { policy = "noTarget", priority = 106, allowHidden = true, alwaysNoTarget = true },
		pangolier_rollup_stop = { policy = "special", allowHidden = true },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_marci = {
	abilities = {
		marci_grapple = { policy = "enemy", priority = 106, disable = true },
		marci_companion_run = { policy = "special", priority = 92 },
		marci_bodyguard = { policy = "ally", priority = 82, allyMode = "buff" },
		marci_guardian = { policy = "ally", priority = 82, allyMode = "buff" },
		marci_unleash = { policy = "noTarget", priority = 112, alwaysNoTarget = true },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_razor = {
	abilities = {
		razor_plasma_field = { policy = "noTarget", priority = 82, radiusSpecial = "radius" },
		razor_static_link = { policy = "enemy", priority = 102 },
		razor_eye_of_the_storm = { policy = "noTarget", priority = 110, radiusSpecial = "radius" },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_beastmaster = {
	abilities = {
		beastmaster_wild_axes = { policy = "point", priority = 84, radiusSpecial = "radius" },
		beastmaster_call_of_the_wild = { policy = "noTarget", priority = 62, alwaysNoTarget = true },
		beastmaster_summon_raptor = { policy = "noTarget", priority = 68, alwaysNoTarget = true },
		beastmaster_summon_razorback = { policy = "noTarget", priority = 68, alwaysNoTarget = true },
		beastmaster_primal_roar = { policy = "enemy", priority = 124, disable = true, urgent = true },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_shadow_shaman = {
	abilities = {
		shadow_shaman_ether_shock = { policy = "enemy", priority = 76 },
		shadow_shaman_voodoo = { policy = "enemy", priority = 116, disable = true },
		shadow_shaman_shackles = { policy = "enemy", priority = 110, disable = true },
		shadow_shaman_mass_serpent_ward = { policy = "special", priority = 112, radiusSpecial = "spawn_radius" },
		shadow_shaman_urnaconda = {
			policy = "point",
			priority = 94,
			allowHidden = true,
			menuVisible = true,
		},
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_dark_seer = {
	abilities = {
		dark_seer_vacuum = { policy = "point", priority = 104, disable = true, radiusSpecial = "radius" },
		dark_seer_ion_shell = {
			policy = "ally",
			priority = 78,
			allyMode = "buff",
			allyModifiers = { "modifier_dark_seer_ion_shell" },
		},
		dark_seer_surge = {
			policy = "ally",
			priority = 88,
			allyMode = "buff",
			allyModifiers = { "modifier_dark_seer_surge" },
		},
		dark_seer_wall_of_replica = {
			policy = "vector",
			priority = 116,
			vectorPerpendicular = true,
			radiusSpecial = "width",
		},
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_dark_willow = {
	abilities = {
		dark_willow_bramble_maze = { policy = "point", priority = 96, disable = true },
		dark_willow_cursed_crown = { policy = "enemy", priority = 104, disable = true },
		dark_willow_shadow_realm = { policy = "noTarget", priority = 84, alwaysNoTarget = true },
		dark_willow_bedlam = { policy = "noTarget", priority = 102, radiusSpecial = "attack_radius" },
		dark_willow_terrorize = { policy = "point", priority = 118, disable = true },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_warlock = {
	abilities = {
		warlock_fatal_bonds = { policy = "enemy", priority = 82 },
		warlock_upheaval = { policy = "point", priority = 86, radiusSpecial = "aoe" },
		warlock_rain_of_chaos = { policy = "point", priority = 126, disable = true, radiusSpecial = "aoe" },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_oracle = {
	abilities = {
		oracle_fortunes_end = { policy = "special" },
		oracle_fates_edict = { policy = "special" },
		oracle_purifying_flames = { policy = "special" },
		oracle_false_promise = {
			policy = "ally",
			priority = 138,
			allyMode = "save",
			allyHealthPct = 34,
			urgent = true,
		},
		oracle_rain_of_destiny = { policy = "point", priority = 78, radiusSpecial = "radius" },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_spirit_breaker = {
	abilities = {
		spirit_breaker_charge_of_darkness = {
			policy = "enemy",
			priority = 98,
			global = true,
			disable = true,
			projectileSpeedSpecial = "movement_speed",
			committedMotion = true,
			motionModifiers = { "modifier_spirit_breaker_charge_of_darkness" },
		},
		spirit_breaker_bulldoze = { policy = "noTarget", priority = 94, alwaysNoTarget = true },
		spirit_breaker_nether_strike = { policy = "enemy", priority = 120, disable = true },
		spirit_breaker_planar_pocket = {
			policy = "self",
			priority = 92,
			requiresRecentDamage = true,
			allowHidden = true,
			menuVisible = true,
		},
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_zuus = {
	abilities = {
		zuus_arc_lightning = { policy = "enemy", priority = 70 },
		zuus_lightning_bolt = { policy = "enemy", priority = 86, disable = true },
		zuus_heavenly_jump = { policy = "noTarget", priority = 78, radiusSpecial = "range" },
		zuus_cloud = { policy = "point", priority = 90, allowHidden = true, menuVisible = true },
		zuus_thundergods_wrath = { policy = "special", priority = 110 },
		zuus_lightning_hands = { policy = "toggle", priority = 62, toggleMode = "enemy", allowHidden = true },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_winter_wyvern = {
	abilities = {
		winter_wyvern_arctic_burn = { policy = "noTarget", priority = 78, alwaysNoTarget = true },
		winter_wyvern_cold_embrace = {
			policy = "ally",
			priority = 118,
			allyMode = "save",
			allyHealthPct = 30,
			urgent = true,
		},
		winter_wyvern_splinter_blast = { policy = "special", priority = 84 },
		winter_wyvern_winters_curse = { policy = "special", priority = 126, disable = true },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_drow_ranger = {
	abilities = {
		drow_ranger_frost_arrows = { policy = "enemy", priority = 66, attackModifier = true, allowStacking = true },
		drow_ranger_wave_of_silence = { policy = "point", priority = 100, disable = true, lineProjectile = true },
		drow_ranger_glacier = { policy = "noTarget", priority = 78, alwaysNoTarget = true },
		drow_ranger_multishot = { policy = "point", priority = 88, lineProjectile = true },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_necrolyte = {
	abilities = {
		necrolyte_death_pulse = { policy = "noTarget", priority = 82, radiusSpecial = "area_of_effect" },
		necrolyte_ghost_shroud = {
			policy = "noTarget",
			priority = 116,
			defensiveHealthPct = 46,
			requiresRecentDamage = true,
			alwaysNoTarget = true,
			urgent = true,
		},
		necrolyte_reapers_scythe = { policy = "special", priority = 126, preferLowHealth = true },
		necrolyte_death_seeker = { policy = "enemy", priority = 96, allowHidden = true, menuVisible = true },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_doom_bringer = {
	abilities = {
		doom_bringer_scorched_earth = { policy = "noTarget", priority = 82, radiusSpecial = "radius" },
		doom_bringer_infernal_blade = { policy = "enemy", priority = 86, attackModifier = true, disable = true },
		doom_bringer_doom = { policy = "enemy", priority = 128, urgent = true },
		doom_bringer_devour = { policy = "disabled" },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_bounty_hunter = {
	abilities = {
		bounty_hunter_shuriken_toss = { policy = "enemy", priority = 84 },
		bounty_hunter_jinada = { policy = "enemy", priority = 74, attackModifier = true },
		bounty_hunter_wind_walk = { policy = "noTarget", priority = 88, alwaysNoTarget = true },
		bounty_hunter_track = { policy = "enemy", priority = 100, targetModifiers = { "modifier_bounty_hunter_track" } },
		bounty_hunter_wind_walk_ally = { policy = "ally", priority = 98, allyMode = "save", allowHidden = true },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_lich = {
	abilities = {
		lich_frost_nova = { policy = "enemy", priority = 84 },
		lich_frost_shield = {
			policy = "ally",
			priority = 104,
			allyMode = "save",
			allyModifiers = { "modifier_lich_frost_shield" },
		},
		lich_sinister_gaze = { policy = "enemy", priority = 108, disable = true },
		lich_chain_frost = { policy = "special", priority = 120 },
		lich_ice_spire = { policy = "point", priority = 96, allowHidden = true, menuVisible = true },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_earthshaker = {
	abilities = {
		earthshaker_fissure = { policy = "point", priority = 110, disable = true, lineProjectile = true },
		earthshaker_enchant_totem = {
			policy = "noTarget",
			priority = 84,
			radiusSpecial = "distance_scepter",
			selfModifiers = { "modifier_earthshaker_enchant_totem" },
		},
		earthshaker_echo_slam = { policy = "special", priority = 124, radiusSpecial = "echo_slam_echo_search_range" },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_riki = {
	abilities = {
		riki_smoke_screen = { policy = "point", priority = 98, radiusSpecial = "radius" },
		riki_blink_strike = { policy = "enemy", priority = 92 },
		riki_tricks_of_the_trade = { policy = "point", priority = 104, radiusSpecial = "radius" },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_viper = {
	abilities = {
		viper_nethertoxin = { policy = "point", priority = 86, radiusSpecial = "radius" },
		viper_poison_attack = { policy = "enemy", priority = 66, attackModifier = true, allowStacking = true },
		viper_viper_strike = { policy = "enemy", priority = 108 },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_rattletrap = {
	abilities = {
		rattletrap_battery_assault = { policy = "noTarget", priority = 84, radiusSpecial = "radius" },
		rattletrap_rocket_flare = { policy = "point", priority = 72, global = true, radiusSpecial = "radius" },
		rattletrap_hookshot = {
			policy = "point",
			priority = 116,
			disable = true,
			lineProjectile = true,
			projectileSpeedSpecial = "speed",
			committedMotion = true,
		},
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_pudge = {
	abilities = {
		pudge_meat_hook = { policy = "point", priority = 106, disable = true, lineProjectile = true },
		pudge_rot = {
			policy = "toggle",
			priority = 94,
			toggleMode = "enemy",
			radiusSpecial = "rot_radius",
			minimumHealthPct = 24,
		},
		pudge_flesh_heap = { policy = "noTarget", priority = 112, requiresRecentDamage = true, alwaysNoTarget = true },
		pudge_dismember = { policy = "enemy", priority = 120, disable = true },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_snapfire = {
	abilities = {
		snapfire_scatterblast = { policy = "point", priority = 84, lineProjectile = true },
		snapfire_lil_shredder = { policy = "noTarget", priority = 76, alwaysNoTarget = true },
		snapfire_firesnap_cookie = {
			policy = "self",
			priority = 90,
			requiresTarget = true,
			durationSpecial = "jump_duration",
			committedMotion = true,
		},
		snapfire_mortimer_kisses = { policy = "point", priority = 118, radiusSpecial = "impact_radius" },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_wisp = {
	abilities = {
		wisp_tether = { policy = "ally", priority = 96, allyMode = "buff" },
		wisp_overcharge = { policy = "noTarget", priority = 88, alwaysNoTarget = true },
		wisp_spirits = { policy = "noTarget", priority = 82, alwaysNoTarget = true },
		wisp_spirits_in = { policy = "special", allowHidden = true },
		wisp_spirits_out = { policy = "special", allowHidden = true },
		wisp_tether_break = { policy = "disabled", allowHidden = true },
		wisp_relocate = { policy = "disabled" },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_lone_druid = {
	abilities = {
		lone_druid_spirit_bear = { policy = "special", priority = 140 },
		lone_druid_rabid = { policy = "noTarget", priority = 78, alwaysNoTarget = true },
		lone_druid_savage_roar = { policy = "noTarget", priority = 104, radiusSpecial = "radius" },
		lone_druid_true_form = { policy = "noTarget", priority = 112, alwaysNoTarget = true },
		lone_druid_true_form_battle_cry = { policy = "noTarget", priority = 94, allowHidden = true },
	},
}

ControlAlly.Profiles.GlobalAbilities.lone_druid_savage_roar_bear = {
	policy = "noTarget",
	priority = 104,
	radiusSpecial = "radius",
}
ControlAlly.Profiles.GlobalAbilities.lone_druid_spirit_bear_fetch = {
	policy = "enemy",
	priority = 94,
	disable = true,
}
ControlAlly.Profiles.GlobalAbilities.lone_druid_spirit_bear_return = { policy = "disabled" }

ControlAlly.Profiles.Heroes.npc_dota_hero_kez = {
	abilities = {
		kez_switch_weapons = { policy = "special", priority = 24 },
		kez_echo_slash = { policy = "noTarget", priority = 88, radiusSpecial = "katana_radius" },
		kez_grappling_claw = {
			policy = "enemy",
			priority = 104,
			disable = true,
			projectileSpeedSpecial = "grapple_speed",
			committedMotion = true,
		},
		kez_kazurai_katana = { policy = "enemy", priority = 72, attackModifier = true, allowStacking = true },
		kez_raptor_dance = { policy = "noTarget", priority = 116, radiusSpecial = "radius" },
		kez_falcon_rush = { policy = "noTarget", priority = 92, alwaysNoTarget = true },
		kez_falcon_rush_ad = { policy = "noTarget", priority = 92, allowHidden = true, menuVisible = true },
		kez_talon_toss = { policy = "enemy", priority = 94, disable = true },
		kez_talon_toss_ad = { policy = "enemy", priority = 94, allowHidden = true, menuVisible = true, disable = true },
		kez_shodo_sai = { policy = "point", priority = 108, requiresRecentDamage = true },
		kez_shodo_sai_ad = {
			policy = "point",
			priority = 108,
			allowHidden = true,
			menuVisible = true,
			requiresRecentDamage = true,
		},
		kez_ravens_veil = { policy = "noTarget", priority = 104, alwaysNoTarget = true },
		kez_ravens_veil_ad = { policy = "noTarget", priority = 104, allowHidden = true, menuVisible = true },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_monkey_king = {
	abilities = {
		monkey_king_boundless_strike = { policy = "point", priority = 106, disable = true, lineProjectile = true },
		monkey_king_tree_dance = { policy = "special", priority = 92 },
		monkey_king_primal_spring = { policy = "special", allowHidden = true, menuVisible = true, priority = 110 },
		monkey_king_primal_spring_early = { policy = "special", allowHidden = true },
		monkey_king_wukongs_command = { policy = "point", priority = 120, radiusSpecial = "second_radius" },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_spectre = {
	abilities = {
		spectre_spectral_dagger = { policy = "enemy", priority = 84 },
		spectre_haunt = { policy = "special", priority = 116 },
		spectre_shadow_step = { policy = "special", priority = 116 },
		spectre_reality = { policy = "special", allowHidden = true, menuVisible = true, priority = 140 },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_ember_spirit = {
	abilities = {
		ember_spirit_searing_chains = { policy = "noTarget", priority = 102, radiusSpecial = "radius", disable = true },
		ember_spirit_sleight_of_fist = { policy = "point", priority = 92, radiusSpecial = "radius" },
		ember_spirit_flame_guard = { policy = "noTarget", priority = 84, radiusSpecial = "radius" },
		ember_spirit_fire_remnant = { policy = "special", priority = 90 },
		ember_spirit_activate_fire_remnant = {
			policy = "special",
			allowHidden = true,
			menuVisible = true,
			priority = 118,
		},
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_earth_spirit = {
	abilities = {
		earth_spirit_stone_caller = { policy = "special", priority = 74 },
		earth_spirit_boulder_smash = { policy = "special", priority = 96, disable = true, lineProjectile = true },
		earth_spirit_rolling_boulder = { policy = "special", priority = 100, disable = true, lineProjectile = true },
		earth_spirit_geomagnetic_grip = { policy = "special", priority = 90, disable = true, lineProjectile = true },
		earth_spirit_petrify = { policy = "enemy", priority = 104, disable = true, allowHidden = true },
		earth_spirit_magnetize = { policy = "noTarget", priority = 116, radiusSpecial = "cast_radius" },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_pugna = {
	abilities = {
		pugna_nether_blast = { policy = "point", priority = 82, radiusSpecial = "radius" },
		pugna_decrepify = { policy = "special", priority = 88 },
		pugna_nether_ward = { policy = "point", priority = 78, radiusSpecial = "radius" },
		pugna_life_drain = { policy = "special", priority = 112 },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_ringmaster = {
	abilities = {
		ringmaster_tame_the_beasts = {
			policy = "point",
			priority = 98,
			radiusSpecial = "end_width",
			specialStage = "ringmaster_tame",
		},
		ringmaster_tame_the_beasts_crack = { policy = "special", allowHidden = true },
		ringmaster_wheel = { policy = "point", priority = 120, radiusSpecial = "mesmerize_radius" },
		ringmaster_spotlight = { policy = "point", priority = 88, radiusSpecial = "radius" },
		ringmaster_the_box = { policy = "ally", priority = 112, allyMode = "save", allyHealthPct = 42 },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_storm_spirit = {
	abilities = {
		storm_spirit_static_remnant = { policy = "noTarget", priority = 84, radiusSpecial = "static_remnant_radius" },
		storm_spirit_electric_vortex = { policy = "enemy", priority = 106, disable = true },
		storm_spirit_ball_lightning = { policy = "special", priority = 30 },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_hoodwink = {
	abilities = {
		hoodwink_acorn_shot = { policy = "enemy", priority = 82 },
		hoodwink_bushwhack = { policy = "special", priority = 104, disable = true, radiusSpecial = "trap_radius" },
		hoodwink_scurry = { policy = "noTarget", priority = 74, alwaysNoTarget = true },
		hoodwink_sharpshooter = {
			policy = "point",
			priority = 116,
			lineProjectile = true,
			specialStage = "hood_sharpshooter",
		},
		hoodwink_sharpshooter_release = { policy = "special", allowHidden = true },
		hoodwink_hunters_boomerang = {
			policy = "enemy",
			priority = 94,
			allowHidden = true,
			menuVisible = true,
		},
		hoodwink_decoy = {
			policy = "noTarget",
			priority = 96,
			alwaysNoTarget = true,
			allowHidden = true,
			menuVisible = true,
		},
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_ancient_apparition = {
	abilities = {
		ancient_apparition_cold_feet = { policy = "enemy", priority = 94, disable = true },
		ancient_apparition_ice_vortex = { policy = "point", priority = 74, radiusSpecial = "radius" },
		ancient_apparition_chilling_touch = { policy = "enemy", priority = 68, attackModifier = true },
		ancient_apparition_ice_blast = { policy = "special", priority = 122 },
		ancient_apparition_ice_blast_release = {
			policy = "special",
			priority = 200,
			allowHidden = true,
			menuVisible = false,
		},
		ancient_apparition_ice_age = {
			policy = "point",
			priority = 88,
			radiusSpecial = "radius",
			allowHidden = true,
			menuVisible = true,
		},
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_nevermore = {
	abilities = {
		nevermore_shadowraze1 = { policy = "special", priority = 94, radiusSpecial = "shadowraze_radius" },
		nevermore_shadowraze2 = { policy = "special", priority = 96, radiusSpecial = "shadowraze_radius" },
		nevermore_shadowraze3 = { policy = "special", priority = 98, radiusSpecial = "shadowraze_radius" },
		nevermore_frenzy = { policy = "noTarget", priority = 78, alwaysNoTarget = true },
		nevermore_requiem = { policy = "noTarget", priority = 124, radiusSpecial = "requiem_radius" },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_dazzle = {
	abilities = {
		dazzle_poison_touch = { policy = "enemy", priority = 86 },
		dazzle_shallow_grave = {
			policy = "ally",
			priority = 142,
			allyMode = "save",
			allyHealthPct = 26,
			allyModifiers = { "modifier_dazzle_shallow_grave" },
			urgent = true,
		},
		dazzle_shadow_wave = { policy = "ally", priority = 98, allyMode = "heal", allyHealthPct = 78 },
		dazzle_nothl_projection = { policy = "special", priority = 110 },
		dazzle_nothl_projection_end = { policy = "special", allowHidden = true },
		dazzle_rain_of_vermin = {
			policy = "point",
			priority = 102,
			radiusSpecial = "radius",
			allowHidden = true,
			menuVisible = true,
		},
		dazzle_weave = { policy = "point", priority = 114, radiusSpecial = "radius" },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_jakiro = {
	abilities = {
		jakiro_dual_breath = { policy = "point", priority = 84, lineProjectile = true },
		jakiro_ice_path = { policy = "point", priority = 108, disable = true, lineProjectile = true },
		jakiro_liquid_fire = { policy = "enemy", priority = 68, attackModifier = true },
		jakiro_liquid_ice = { policy = "enemy", priority = 72, attackModifier = true, allowHidden = true },
		jakiro_macropyre = { policy = "point", priority = 116, lineProjectile = true },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_skywrath_mage = {
	abilities = {
		skywrath_mage_arcane_bolt = { policy = "enemy", priority = 82 },
		skywrath_mage_concussive_shot = { policy = "noTarget", priority = 86, radiusSpecial = "launch_radius" },
		skywrath_mage_ancient_seal = { policy = "enemy", priority = 108, disable = true },
		skywrath_mage_mystic_flare = {
			policy = "point",
			priority = 118,
			radiusSpecial = "radius",
			requiresImmobile = true,
			requirePrimary = true,
		},
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_morphling = {
	abilities = {
		morphling_waveform = {
			policy = "point",
			priority = 94,
			lineProjectile = true,
			projectileSpeedSpecial = "speed",
			committedMotion = true,
		},
		morphling_adaptive_strike_agi = { policy = "enemy", priority = 88 },
		morphling_morph_agi = { policy = "special" },
		morphling_morph_str = { policy = "special" },
		morphling_replicate = { policy = "special", priority = 112 },
		morphling_morph_replicate = { policy = "special", allowHidden = true, menuVisible = true, priority = 160 },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_meepo = {
	abilities = {
		meepo_earthbind = {
			policy = "special",
			priority = 112,
			radiusSpecial = "radius",
			projectileSpeedSpecial = "speed",
			durationSpecial = "duration",
		},
		meepo_poof = { policy = "special", priority = 82, radiusSpecial = "radius" },
		meepo_petrify = {
			policy = "noTarget",
			priority = 132,
			defensiveHealthPct = 24,
			alwaysNoTarget = true,
			allowHidden = true,
			urgent = true,
		},
		meepo_megameepo = { policy = "noTarget", priority = 126, alwaysNoTarget = true, allowHidden = true },
		meepo_megameepo_fling = { policy = "enemy", priority = 112, allowHidden = true },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_gyrocopter = {
	abilities = {
		gyrocopter_rocket_barrage = { policy = "noTarget", priority = 86, radiusSpecial = "radius" },
		gyrocopter_homing_missile = { policy = "enemy", priority = 102, disable = true },
		gyrocopter_flak_cannon = { policy = "noTarget", priority = 78, alwaysNoTarget = true },
		gyrocopter_call_down = { policy = "point", priority = 116, radiusSpecial = "radius" },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_windrunner = {
	abilities = {
		windrunner_shackleshot = { policy = "enemy", priority = 108, disable = true },
		windrunner_powershot = { policy = "point", priority = 88, lineProjectile = true },
		windrunner_windrun = { policy = "noTarget", priority = 78 },
		windrunner_focusfire = { policy = "enemy", priority = 116 },
		windrunner_gale_force = {
			policy = "vector",
			priority = 106,
			vectorPerpendicular = true,
			allowHidden = true,
			menuVisible = true,
		},
		windrunner_focusfire_cancel = { policy = "disabled", allowHidden = true },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_crystal_maiden = {
	abilities = {
		crystal_maiden_crystal_nova = { policy = "point", priority = 84, radiusSpecial = "radius" },
		crystal_maiden_frostbite = { policy = "enemy", priority = 102, disable = true },
		crystal_maiden_freezing_field = { policy = "noTarget", priority = 122, radiusSpecial = "radius" },
		crystal_maiden_freezing_field_stop = { policy = "disabled", allowHidden = true },
		crystal_maiden_let_it_go = {
			policy = "point",
			priority = 74,
			allowHidden = true,
			menuVisible = true,
		},
		crystal_maiden_crystal_clone = {
			policy = "selfPosition",
			priority = 104,
			allowHidden = true,
			menuVisible = true,
		},
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_disruptor = {
	abilities = {
		disruptor_thunder_strike = { policy = "enemy", priority = 82 },
		disruptor_glimpse = { policy = "enemy", priority = 98, disable = true },
		disruptor_kinetic_field = { policy = "point", priority = 106, disable = true, radiusSpecial = "radius" },
		disruptor_static_storm = { policy = "point", priority = 120, disable = true, radiusSpecial = "radius" },
		disruptor_kinetic_fence = {
			policy = "vector",
			priority = 106,
			vectorPerpendicular = true,
			disable = true,
			allowHidden = true,
			menuVisible = true,
		},
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_bloodseeker = {
	abilities = {
		bloodseeker_bloodrage = { policy = "noTarget", priority = 78, alwaysNoTarget = true },
		bloodseeker_blood_bath = { policy = "point", priority = 96, disable = true, radiusSpecial = "radius" },
		bloodseeker_blood_mist = {
			policy = "toggle",
			priority = 84,
			toggleMode = "enemy",
			radiusSpecial = "radius",
			minimumHealthPct = 42,
		},
		bloodseeker_rupture = { policy = "enemy", priority = 118 },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_ogre_magi = {
	abilities = {
		ogre_magi_fireblast = { policy = "enemy", priority = 108, disable = true },
		ogre_magi_unrefined_fireblast = {
			policy = "enemy",
			priority = 116,
			disable = true,
			allowHidden = true,
			menuVisible = true,
		},
		ogre_magi_ignite = { policy = "enemy", priority = 88 },
		ogre_magi_bloodlust = {
			policy = "ally",
			priority = 78,
			allyMode = "buff",
			allyModifiers = { "modifier_ogre_magi_bloodlust" },
		},
		ogre_magi_frost_armor = { policy = "ally", priority = 84, allyMode = "save", allowHidden = true },
		ogre_magi_smash = {
			policy = "ally",
			priority = 96,
			allyMode = "save",
			allowHidden = true,
			menuVisible = true,
		},
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_queenofpain = {
	abilities = {
		queenofpain_shadow_strike = { policy = "enemy", priority = 82 },
		queenofpain_blink = { policy = "gapclose", priority = 92, minDistance = 500 },
		queenofpain_scream_of_pain = { policy = "noTarget", priority = 88, radiusSpecial = "area_of_effect" },
		queenofpain_sonic_wave = { policy = "point", priority = 120, lineProjectile = true },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_grimstroke = {
	abilities = {
		grimstroke_dark_artistry = { policy = "point", priority = 84, lineProjectile = true },
		grimstroke_ink_creature = { policy = "enemy", priority = 94, disable = true },
		grimstroke_spirit_walk = { policy = "ally", priority = 92, allyMode = "buff" },
		grimstroke_soul_chain = { policy = "enemy", priority = 118, disable = true },
		grimstroke_dark_portrait = { policy = "enemy", priority = 108, allowHidden = true, menuVisible = true },
		grimstroke_ink_over = {
			policy = "enemy",
			priority = 92,
			allowHidden = true,
			menuVisible = true,
		},
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_axe = {
	abilities = {
		axe_berserkers_call = { policy = "noTarget", priority = 112, radiusSpecial = "radius", disable = true },
		axe_battle_hunger = { policy = "enemy", priority = 82 },
		axe_culling_blade = { policy = "special", priority = 124, preferLowHealth = true },
	},
}

ControlAlly.Profiles.Heroes.npc_dota_hero_witch_doctor = {
	abilities = {
		witch_doctor_paralyzing_cask = { policy = "enemy", priority = 102, disable = true },
		witch_doctor_voodoo_restoration = {
			policy = "toggle",
			priority = 96,
			toggleMode = "heal",
			radiusSpecial = "radius",
		},
		witch_doctor_maledict = { policy = "point", priority = 94, radiusSpecial = "radius" },
		witch_doctor_death_ward = { policy = "point", priority = 122, radiusSpecial = "attack_range_tooltip" },
		witch_doctor_voodoo_switcheroo = {
			policy = "noTarget",
			priority = 132,
			allowHidden = true,
			menuVisible = true,
			urgent = true,
		},
	},
}

ControlAlly.Profiles.RefreshableTinkerActions = {
	tinker_laser = true,
	tinker_warp_grenade = true,
	tinker_march_of_the_machines = true,
	tinker_defense_matrix = true,
	tinker_deploy_turrets = true,
}

ControlAlly.Profiles.InvokerSpells = {
	invoker_cold_snap = {
		orbs = { "invoker_quas", "invoker_quas", "invoker_quas" },
		policy = "enemy",
		priority = 98,
		disable = true,
		targetModifiers = { "modifier_invoker_cold_snap" },
	},
	invoker_tornado = {
		orbs = { "invoker_wex", "invoker_wex", "invoker_quas" },
		policy = "point",
		priority = 87,
		disable = true,
		radiusSpecial = "area_of_effect",
		projectileSpeedSpecial = "travel_speed",
		travelDistanceSpecial = "travel_distance",
		lineProjectile = true,
		durationSpecial = "lift_duration",
		requirePrimary = true,
		targetModifiers = { "modifier_invoker_tornado" },
	},
	invoker_chaos_meteor = {
		orbs = { "invoker_exort", "invoker_exort", "invoker_wex" },
		policy = "point",
		priority = 86,
		radiusSpecial = "area_of_effect",
		delaySpecial = "land_time",
		travelDistanceSpecial = "travel_distance",
		comboFollowup = true,
		preferDisabledTarget = true,
	},
	invoker_deafening_blast = {
		orbs = { "invoker_quas", "invoker_wex", "invoker_exort" },
		policy = "point",
		priority = 80,
		disable = true,
		radiusSpecial = "radius_end",
		projectileSpeedSpecial = "travel_speed",
		travelDistanceSpecial = "travel_distance",
		lineProjectile = true,
		comboFollowup = true,
		targetModifiers = { "modifier_invoker_deafening_blast_disarm" },
	},
	invoker_emp = {
		orbs = { "invoker_wex", "invoker_wex", "invoker_wex" },
		policy = "point",
		priority = 70,
		radiusSpecial = "area_of_effect",
		delaySpecial = "delay",
		comboFollowup = true,
		targetManaMinPct = 18,
		preferDisabledTarget = true,
	},
	invoker_sun_strike = {
		orbs = { "invoker_exort", "invoker_exort", "invoker_exort" },
		policy = "point",
		priority = 58,
		global = true,
		radiusSpecial = "area_of_effect",
		delaySpecial = "delay",
		comboFollowup = true,
		preferDisabledTarget = true,
		preferLowHealth = true,
		allowMagicImmune = true,
	},
	invoker_ice_wall = {
		orbs = { "invoker_quas", "invoker_quas", "invoker_exort" },
		policy = "iceWall",
		priority = 54,
		maxDistanceSpecial = "wall_total_length",
		disable = true,
	},
	invoker_forge_spirit = {
		orbs = { "invoker_quas", "invoker_exort", "invoker_exort" },
		policy = "noTarget",
		priority = 47,
		alwaysNoTarget = true,
	},
	invoker_alacrity = {
		orbs = { "invoker_wex", "invoker_wex", "invoker_exort" },
		policy = "self",
		priority = 50,
		combatBuff = true,
		selfModifiers = { "modifier_invoker_alacrity" },
	},
	invoker_ghost_walk = {
		orbs = { "invoker_quas", "invoker_quas", "invoker_wex" },
		policy = "noTarget",
		priority = 130,
		defensiveHealthPct = 28,
		radiusSpecial = "area_of_effect",
		alwaysNoTarget = true,
		selfModifiers = { "modifier_invoker_ghost_walk_self" },
		urgent = true,
	},
}

ControlAlly.Profiles.SupportItems = {
	item_solar_crest = {
		policy = "ally",
		priority = 108,
		family = "pavise_barrier",
		durationSpecial = "duration",
		defensiveHealthPct = 76,
	},
	item_pavise = {
		policy = "ally",
		priority = 104,
		family = "pavise_barrier",
		durationSpecial = "duration",
		defensiveHealthPct = 70,
	},
	item_glimmer_cape = {
		policy = "ally",
		priority = 122,
		family = "glimmer_save",
		durationSpecial = "duration",
		defensiveHealthPct = 48,
		urgent = true,
	},
	item_pipe = {
		policy = "allyNoTarget",
		priority = 116,
		family = "pipe_barrier",
		radiusSpecial = "barrier_radius",
		durationSpecial = "barrier_duration",
		defensiveHealthPct = 72,
		urgent = true,
	},
	item_arcane_boots = {
		policy = "manaBoots",
		priority = 82,
		family = "mana_restore",
		radiusSpecial = "replenish_radius",
		amountSpecial = "replenish_amount",
	},
	item_guardian_greaves = {
		policy = "greaves",
		priority = 126,
		family = "mana_restore",
		radiusSpecial = "replenish_radius",
		healSpecial = "replenish_health",
		amountSpecial = "replenish_mana",
		urgent = true,
	},
	item_phase_boots = {
		policy = "chaseBoots",
		priority = 46,
		family = "phase_movement",
		durationSpecial = "phase_duration",
	},
	item_boots_of_bearing = {
		policy = "combatBoots",
		priority = 88,
		family = "bearing_haste",
		radiusSpecial = "radius",
		durationSpecial = "duration",
	},
	item_power_treads = {
		policy = "powerTreads",
		priority = 38,
		family = "treads_attribute",
	},
	item_refresher = { policy = "refresher", priority = 140 },
	item_refresher_shard = { policy = "refresher", priority = 142 },
}

ControlAlly.Profiles.Items = {
	item_blink = {
		policy = "gapclose",
		priority = 96,
		minDistance = 500,
		castRangeSpecial = "blink_range",
		ignoreCastRangeBonus = true,
	},
	item_overwhelming_blink = {
		policy = "gapclose",
		priority = 102,
		minDistance = 450,
		castRangeSpecial = "blink_range",
		ignoreCastRangeBonus = true,
	},
	item_swift_blink = {
		policy = "gapclose",
		priority = 100,
		minDistance = 500,
		castRangeSpecial = "blink_range",
		ignoreCastRangeBonus = true,
	},
	item_arcane_blink = {
		policy = "gapclose",
		priority = 100,
		minDistance = 500,
		castRangeSpecial = "blink_range",
		ignoreCastRangeBonus = true,
	},
	item_sheepstick = { policy = "enemy", priority = 116, disable = true, linkPriority = 45 },
	item_abyssal_blade = {
		policy = "enemy",
		priority = 114,
		disable = true,
		allowMagicImmune = true,
		linkPriority = 55,
	},
	item_orchid = { policy = "enemy", priority = 101, disable = true, linkPriority = 72 },
	item_bloodthorn = { policy = "enemy", priority = 106, disable = true, linkPriority = 66 },
	item_rod_of_atos = { policy = "enemy", priority = 89, disable = true, linkPriority = 88 },
	item_gungir = { policy = "point", priority = 94, disable = true, radiusSpecial = "radius" },
	item_nullifier = { policy = "enemy", priority = 93, linkPriority = 62 },
	item_heavens_halberd = { policy = "enemy", priority = 88, disable = true, linkPriority = 80 },
	item_ethereal_blade = { policy = "enemy", priority = 84, linkPriority = 78 },
	item_diffusal_blade = { policy = "enemy", priority = 78, linkPriority = 112 },
	item_disperser = { policy = "enemy", priority = 80, linkPriority = 108 },
	item_spirit_vessel = { policy = "enemy", priority = 73, linkPriority = 118 },
	item_urn_of_shadows = { policy = "enemy", priority = 67, linkPriority = 122 },
	item_dagon = { policy = "enemy", priority = 83, linkPriority = 76 },
	item_dagon_2 = { policy = "enemy", priority = 85, linkPriority = 74 },
	item_dagon_3 = { policy = "enemy", priority = 87, linkPriority = 72 },
	item_dagon_4 = { policy = "enemy", priority = 89, linkPriority = 70 },
	item_dagon_5 = { policy = "enemy", priority = 91, linkPriority = 68 },
	item_shivas_guard = { policy = "noTarget", priority = 82, radiusSpecial = "blast_radius" },
	item_veil_of_discord = { policy = "noTarget", priority = 69, radiusSpecial = "debuff_radius" },
	item_black_king_bar = {
		policy = "noTarget",
		priority = 124,
		radius = 725,
		defensiveHealthPct = 72,
		requiresRecentDamage = true,
		urgent = true,
	},
	item_blade_mail = {
		policy = "noTarget",
		priority = 112,
		radius = 650,
		defensiveHealthPct = 68,
		requiresRecentDamage = true,
		urgent = true,
	},
	item_satanic = {
		policy = "noTarget",
		priority = 128,
		radius = 500,
		defensiveHealthPct = 44,
		urgent = true,
	},
	item_manta = {
		policy = "noTarget",
		priority = 121,
		radius = 700,
		requiresBadState = true,
		urgent = true,
	},
	item_lotus_orb = {
		policy = "self",
		priority = 109,
		defensiveHealthPct = 52,
		requiresRecentDamage = true,
		urgent = true,
	},
	item_glimmer_cape = {
		policy = "self",
		priority = 118,
		defensiveHealthPct = 34,
		urgent = true,
	},
	item_ghost = {
		policy = "noTarget",
		priority = 126,
		radius = 450,
		defensiveHealthPct = 30,
		urgent = true,
	},
}

function ControlAlly.Utils.call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c = pcall(fn, ...)
	if not ok then
		return nil
	end
	return a, b, c
end

function ControlAlly.Utils.try(fn, ...)
	if type(fn) ~= "function" then
		return false
	end
	return pcall(fn, ...)
end

function ControlAlly.Utils.hasFlag(value, flag)
	value = tonumber(value) or 0
	flag = tonumber(flag) or 0
	return flag > 0 and value % (flag * 2) >= flag
end

function ControlAlly.Utils.clamp(value, minimum, maximum)
	if value < minimum then
		return minimum
	end
	if value > maximum then
		return maximum
	end
	return value
end

function ControlAlly.Utils.distance2D(a, b)
	if not a or not b then
		return math.huge
	end
	local dx = (a.x or 0) - (b.x or 0)
	local dy = (a.y or 0) - (b.y or 0)
	return math.sqrt(dx * dx + dy * dy)
end

function ControlAlly.Utils.positionToward(from, to, distance)
	if not from or not to then
		return nil
	end
	local dx = (to.x or 0) - (from.x or 0)
	local dy = (to.y or 0) - (from.y or 0)
	local length = math.sqrt(dx * dx + dy * dy)
	if length <= 0.001 then
		return Vector(from.x, from.y, from.z or to.z or 0)
	end
	local scale = distance / length
	return Vector(from.x + dx * scale, from.y + dy * scale, to.z or from.z or 0)
end

function ControlAlly.Utils.rotate2D(vector, angle)
	local cosine = math.cos(angle)
	local sine = math.sin(angle)
	return Vector(
		(vector.x or 0) * cosine - (vector.y or 0) * sine,
		(vector.x or 0) * sine + (vector.y or 0) * cosine,
		vector.z or 0
	)
end

function ControlAlly.Utils.normalized2D(from, to)
	local dx = (to.x or 0) - (from.x or 0)
	local dy = (to.y or 0) - (from.y or 0)
	local length = math.sqrt(dx * dx + dy * dy)
	if length <= 0.001 then
		return nil
	end
	return Vector(dx / length, dy / length, 0)
end

function ControlAlly.Utils.entityIndex(entity)
	return ControlAlly.Utils.call(Entity.GetIndex, entity)
end

function ControlAlly.Utils.gameTime()
	return ControlAlly.Utils.call(GameRules.GetGameTime) or 0
end

function ControlAlly.Utils.unitName(unit)
	return ControlAlly.Utils.call(NPC.GetUnitName, unit) or ControlAlly.Utils.call(Entity.GetUnitName, unit)
end

function ControlAlly.Utils.abilityName(ability)
	return ControlAlly.Utils.call(Ability.GetName, ability) or ControlAlly.Utils.call(Ability.GetBaseName, ability)
end

function ControlAlly.Utils.protectedActivity(unit, activeAbility)
	if not unit then
		return nil
	end
	if XHelpers and XHelpers.XNPC and XHelpers.XNPC.GetChannellingAbilityOrItem then
		local channel = ControlAlly.Utils.call(XHelpers.XNPC.GetChannellingAbilityOrItem, XHelpers.XNPC, unit)
		if channel then
			return channel
		end
	end
	local channel = ControlAlly.Utils.call(NPC.GetChannellingAbility, unit)
	if channel then
		return channel
	end
	if
		activeAbility
		and (
			ControlAlly.Utils.call(Ability.IsChannelling, activeAbility) == true
			or ControlAlly.Utils.call(Ability.IsInAbilityPhase, activeAbility) == true
		)
	then
		return activeAbility
	end
	local index = ControlAlly.Utils.entityIndex(unit)
	local now = ControlAlly.Utils.gameTime()
	local cached = index and ControlAlly.Runtime.activityCache[index]
	if cached and now - cached.at <= 0.01 then
		return cached.ability
	end
	local found
	for slot = 0, 23 do
		local ability = ControlAlly.Utils.call(NPC.GetAbilityByIndex, unit, slot)
		if
			ability
			and (
				ControlAlly.Utils.call(Ability.IsInAbilityPhase, ability) == true
				or ControlAlly.Utils.call(Ability.IsChannelling, ability) == true
			)
		then
			found = ability
			break
		end
	end
	if not found then
		for _, slot in ipairs({ 0, 1, 2, 3, 4, 5, 16 }) do
			local item = ControlAlly.Utils.call(NPC.GetItemByIndex, unit, slot)
			if
				item
				and (
					ControlAlly.Utils.call(Ability.IsInAbilityPhase, item) == true
					or ControlAlly.Utils.call(Ability.IsChannelling, item) == true
				)
			then
				found = item
				break
			end
		end
	end
	if index then
		ControlAlly.Runtime.activityCache[index] = found and { at = now, ability = found } or nil
	end
	return found
end

function ControlAlly.Utils.heroDisplayName(unitName)
	if not unitName then
		return "Unknown"
	end
	local localized = GameLocalizer and ControlAlly.Utils.call(GameLocalizer.FindNPC, unitName)
	if type(localized) == "string" and localized ~= "" then
		return localized
	end
	local shortName = unitName:gsub("^npc_dota_hero_", ""):gsub("_", " ")
	return shortName:sub(1, 1):upper() .. shortName:sub(2)
end

function ControlAlly.Utils.heroIcon(unitName)
	if not unitName or unitName == "" then
		return ""
	end
	return "panorama/images/heroes/icons/" .. unitName .. "_png.vtex_c"
end

function ControlAlly.Utils.abilityIcon(id)
	if not id or id == "" or id == "none" then
		return ""
	end
	id = ControlAlly.Profiles.normalizedAbilityId(id) or id
	if id:sub(1, 5) == "item_" then
		return "panorama/images/items/" .. id:sub(6) .. "_png.vtex_c"
	end
	return "panorama/images/spellicons/" .. id .. "_png.vtex_c"
end

function ControlAlly.Utils.menuIcon(widget, icon)
	if widget and icon and widget.Icon then
		ControlAlly.Utils.call(widget.Icon, widget, icon)
	end
end

function ControlAlly.Utils.healthPct(unit)
	local health = ControlAlly.Utils.call(Entity.GetHealth, unit) or 0
	local maximum = ControlAlly.Utils.call(Entity.GetMaxHealth, unit) or 1
	return maximum > 0 and health * 100 / maximum or 0
end

function ControlAlly.Utils.manaPct(unit)
	local mana = ControlAlly.Utils.call(NPC.GetMana, unit) or 0
	local maximum = ControlAlly.Utils.call(NPC.GetMaxMana, unit) or 1
	return maximum > 0 and mana * 100 / maximum or 0
end

function ControlAlly.Utils.hasAnyModifier(unit, modifiers)
	if not unit or type(modifiers) ~= "table" then
		return false
	end
	for _, modifier in ipairs(modifiers) do
		if ControlAlly.Utils.call(NPC.HasModifier, unit, modifier) == true then
			return true
		end
	end
	return false
end

function ControlAlly.Utils.clearMotionLock(controller)
	controller.motionLockUntil = -math.huge
	controller.motionLockStartedAt = -math.huge
	controller.motionModifiers = nil
	controller.motionTarget = nil
end

function ControlAlly.Utils.isMotionLocked(controller, now)
	if not controller or now >= (controller.motionLockUntil or -math.huge) then
		if controller then
			ControlAlly.Utils.clearMotionLock(controller)
		end
		return false
	end
	if controller.motionTarget and ControlAlly.Utils.call(Entity.IsAlive, controller.motionTarget) == false then
		ControlAlly.Utils.clearMotionLock(controller)
		return false
	end
	if
		type(controller.motionModifiers) == "table"
		and now - (controller.motionLockStartedAt or -math.huge) > 0.40
		and not ControlAlly.Utils.hasAnyModifier(controller.unit, controller.motionModifiers)
	then
		ControlAlly.Utils.clearMotionLock(controller)
		return false
	end
	if
		controller.motionModifiers == nil
		and now - (controller.motionLockStartedAt or -math.huge) > 0.55
		and ControlAlly.Utils.call(NPC.IsRunning, controller.unit) ~= true
		and ControlAlly.Utils.call(NPC.IsTurning, controller.unit) ~= true
	then
		ControlAlly.Utils.clearMotionLock(controller)
		return false
	end
	return true
end

function ControlAlly.Utils.hasState(unit, state)
	return state ~= nil and ControlAlly.Utils.call(NPC.HasState, unit, state) == true
end

function ControlAlly.Utils.isMagicImmune(unit)
	local states = Enum.ModifierState
	return states and ControlAlly.Utils.hasState(unit, states.MODIFIER_STATE_MAGIC_IMMUNE)
end

function ControlAlly.Utils.hasBadState(unit)
	local states = Enum.ModifierState
	if not states then
		return false
	end
	return ControlAlly.Utils.hasState(unit, states.MODIFIER_STATE_ROOTED)
		or ControlAlly.Utils.hasState(unit, states.MODIFIER_STATE_SILENCED)
		or ControlAlly.Utils.hasState(unit, states.MODIFIER_STATE_DISARMED)
end

function ControlAlly.Utils.isCommandRestricted(unit)
	local states = Enum.ModifierState
	if not states then
		return ControlAlly.Utils.call(NPC.IsStunned, unit) == true
	end
	return ControlAlly.Utils.call(NPC.IsStunned, unit) == true
		or ControlAlly.Utils.hasState(unit, states.MODIFIER_STATE_HEXED)
		or ControlAlly.Utils.hasState(unit, states.MODIFIER_STATE_NIGHTMARED)
		or ControlAlly.Utils.hasState(unit, states.MODIFIER_STATE_OUT_OF_GAME)
		or ControlAlly.Utils.hasState(unit, states.MODIFIER_STATE_COMMAND_RESTRICTED)
end

function ControlAlly.Utils.canAttack(unit, target)
	if not unit or not target then
		return false
	end
	local states = Enum.ModifierState
	if states then
		if ControlAlly.Utils.hasState(unit, states.MODIFIER_STATE_DISARMED) then
			return false
		end
		for _, stateName in ipairs({
			"MODIFIER_STATE_INVULNERABLE",
			"MODIFIER_STATE_OUT_OF_GAME",
			"MODIFIER_STATE_UNTARGETABLE",
			"MODIFIER_STATE_UNTARGETABLE_ENEMY",
			"MODIFIER_STATE_ATTACK_IMMUNE",
		}) do
			local state = states[stateName]
			if state ~= nil and ControlAlly.Utils.hasState(target, state) then
				return false
			end
		end
	end
	return not ControlAlly.Utils.hasAnyModifier(target, {
		"modifier_ghost_state",
		"modifier_item_ethereal_blade_ethereal",
		"modifier_pugna_decrepify",
	})
end

function ControlAlly.Utils.isValidHero(unit, requireAlive)
	if not unit or ControlAlly.Utils.call(Entity.IsEntity, unit) ~= true then
		return false
	end
	if ControlAlly.Utils.call(NPC.IsHero, unit) ~= true and ControlAlly.Utils.call(Entity.IsHero, unit) ~= true then
		return false
	end
	if requireAlive and ControlAlly.Utils.call(Entity.IsAlive, unit) ~= true then
		return false
	end
	return true
end

function ControlAlly.Utils.isSpiritBear(unit)
	return XHelpers
			and XHelpers.XNPC
			and XHelpers.XNPC.IsSpiritBear
			and ControlAlly.Utils.call(XHelpers.XNPC.IsSpiritBear, XHelpers.XNPC, unit) == true
		or false
end

function ControlAlly.Utils.isNothlProjection(unit)
	return XHelpers
			and XHelpers.XNPC
			and XHelpers.XNPC.IsNothlProjection
			and ControlAlly.Utils.call(XHelpers.XNPC.IsNothlProjection, XHelpers.XNPC, unit) == true
		or false
end

function ControlAlly.Utils.isValidControllerUnit(unit, requireAlive)
	if ControlAlly.Utils.isValidHero(unit, requireAlive) then
		return true
	end
	return (ControlAlly.Utils.isSpiritBear(unit) or ControlAlly.Utils.isNothlProjection(unit))
		and ControlAlly.Utils.call(Entity.IsEntity, unit) == true
		and (not requireAlive or ControlAlly.Utils.call(Entity.IsAlive, unit) == true)
end

function ControlAlly.Utils.isTempestDouble(unit)
	if NPC.IsTempestDouble and ControlAlly.Utils.call(NPC.IsTempestDouble, unit) == true then
		return true
	end
	return ControlAlly.Utils.call(NPC.HasModifier, unit, "modifier_arc_warden_tempest_double") == true
end

function ControlAlly.Utils.isHeroClone(unit, assignedHero)
	if ControlAlly.Utils.isTempestDouble(unit) then
		return true
	end
	if NPC.IsMeepoClone and ControlAlly.Utils.call(NPC.IsMeepoClone, unit) == true then
		return true
	end
	if ControlAlly.Utils.isNothlProjection(unit) then
		return true
	end
	local name = ControlAlly.Utils.unitName(unit)
	local assignedName = ControlAlly.Utils.unitName(assignedHero)
	return unit ~= assignedHero
		and ControlAlly.Utils.call(NPC.IsIllusion, unit) ~= true
		and name == assignedName
		and (name == "npc_dota_hero_arc_warden" or name == "npc_dota_hero_meepo")
end

function ControlAlly.Utils.wasRecentlyHurt(unit, now)
	local lastHurt = ControlAlly.Utils.call(Hero.GetLastHurtTime, unit)
	if type(lastHurt) == "number" and lastHurt > 0 and now - lastHurt <= 2.2 then
		return true
	end
	local recent = ControlAlly.Utils.call(Hero.GetRecentDamage, unit) or 0
	local maximum = ControlAlly.Utils.call(Entity.GetMaxHealth, unit) or 1
	return recent >= maximum * 0.05
end

function ControlAlly.Utils.cooldownRemaining(ability)
	if not ability then
		return math.huge
	end
	if Ability.GetCooldownTimeRemaining then
		local remaining = ControlAlly.Utils.call(Ability.GetCooldownTimeRemaining, ability)
		if type(remaining) == "number" then
			return math.max(0, remaining)
		end
	end
	local remaining = ControlAlly.Utils.call(Ability.GetCooldown, ability)
	return type(remaining) == "number" and math.max(0, remaining) or 0
end

function ControlAlly.Utils.specialValueExact(ability, name, fallback)
	local liveValue
	if Ability.GetSpecialValueFor then
		liveValue = ControlAlly.Utils.call(Ability.GetSpecialValueFor, ability, name)
	end
	if type(liveValue) == "number" then
		return liveValue
	end
	local levelValue
	if Ability.GetLevelSpecialValueFor then
		levelValue = ControlAlly.Utils.call(Ability.GetLevelSpecialValueFor, ability, name, -1)
	end
	return type(levelValue) == "number" and levelValue or fallback
end

function ControlAlly.Utils.specialValue(ability, names, fallback)
	for _, name in ipairs(names) do
		local value = ControlAlly.Utils.specialValueExact(ability, name, nil)
		if type(value) == "number" and value > 0 then
			return value
		end
	end
	return fallback
end

function ControlAlly.Utils.ruleValue(ability, rule, literalKey, specialKey, fallback)
	if rule[literalKey] ~= nil then
		return rule[literalKey]
	end
	local key = rule[specialKey]
	if key then
		return ControlAlly.Utils.specialValueExact(ability, key, fallback)
	end
	return fallback
end

function ControlAlly.Utils.copyTable(source)
	local result = {}
	for key, value in pairs(source or {}) do
		result[key] = value
	end
	return result
end

function ControlAlly.Utils.modifierRemaining(unit, modifierName, now)
	if not unit or not modifierName or not NPC.GetModifier then
		return 0
	end
	local modifier = ControlAlly.Utils.call(NPC.GetModifier, unit, modifierName)
	if not modifier then
		return 0
	end
	local dieTime = ControlAlly.Utils.call(Modifier.GetDieTime, modifier)
	if type(dieTime) == "number" and dieTime > 0 then
		return math.max(0, dieTime - (now or ControlAlly.Utils.gameTime()))
	end
	local duration = ControlAlly.Utils.call(Modifier.GetDuration, modifier)
	local created = ControlAlly.Utils.call(Modifier.GetCreationTime, modifier)
	if type(duration) == "number" and duration > 0 and type(created) == "number" then
		return math.max(0, created + duration - (now or ControlAlly.Utils.gameTime()))
	end
	return 0
end

function ControlAlly.Utils.debug(message, ...)
	if not ControlAlly.UI.Debug or ControlAlly.UI.Debug:Get() ~= true then
		return
	end
	local text = select("#", ...) > 0 and string.format(message, ...) or message
	ControlAlly.Utils.call(Log.Write, "[ControlAlly] " .. tostring(text))
end

function ControlAlly.Profiles.getAbilityRule(heroName, abilityId)
	local heroProfile = ControlAlly.Profiles.Heroes[heroName]
	if heroProfile and heroProfile.abilities and heroProfile.abilities[abilityId] then
		return heroProfile.abilities[abilityId]
	end
	local globalRule = ControlAlly.Profiles.GlobalAbilities[abilityId]
	if globalRule then
		return globalRule
	end
	if not ControlAlly.Profiles.AbilityRulesById then
		local rules = {}
		for _, profile in pairs(ControlAlly.Profiles.Heroes) do
			for id, rule in pairs(profile.abilities or {}) do
				rules[id] = rules[id] or rule
			end
		end
		ControlAlly.Profiles.AbilityRulesById = rules
	end
	return ControlAlly.Profiles.AbilityRulesById[abilityId]
end

function ControlAlly.Profiles.normalizedAbilityId(abilityId)
	return ControlAlly.Profiles.AbilityAliases[abilityId] or abilityId
end

function ControlAlly.Profiles.normalizedItemId(itemId)
	if type(itemId) ~= "string" then
		return itemId
	end
	if itemId:match("^item_dagon_[2-5]$") then
		return itemId
	end
	return itemId
end

function ControlAlly.Profiles.getItemRule(itemId)
	local normalized = ControlAlly.Profiles.normalizedItemId(itemId)
	return ControlAlly.Profiles.Items[normalized] or ControlAlly.Profiles.SupportItems[normalized]
end

function ControlAlly.Menu.initialize()
	if ControlAlly.Runtime.initialized then
		return
	end

	local icons = {
		enable = "\u{f00c}",
		players = "\u{f0c0}",
		abilities = "\u{f890}",
		items = "\u{e196}",
		gear = "\u{f013}",
		target = "\u{f05b}",
		search = "\u{f002}",
		mana = "\u{f043}",
		clones = "\u{f24d}",
		attack = "\u{f71c}",
		follow = "\u{f245}",
		debug = "\u{f188}",
		bind = "\u{e1c1}",
	}

	local group = ControlAlly.Utils.call(Menu.Find, "Heroes", "", "Settings", "General", "Control Ally")
	if not group then
		group = Menu.Create("Heroes", "", "Settings", "General", "Control Ally")
	end
	if not group then
		return
	end

	local ui = ControlAlly.UI
	ui.Enabled = group:Switch("Enable", false, icons.enable)
	ui.Enabled:ToolTip(
		"Control every selected disconnected/shared-control ally with an independent smart combat controller."
	)
	ControlAlly.Utils.menuIcon(ui.Enabled, icons.enable)

	ui.ActivationHint = group:Label("Uses your local hero Combo Key", icons.bind)
	ui.ActivationHint:ToolTip(
		"Hold the Combo Key from your current hero's Main Settings. No separate Control Key is created."
	)
	ControlAlly.Utils.menuIcon(ui.ActivationHint, icons.bind)

	ui.Players = group:MultiSelect("Controlled Players", {}, true)
	ui.Players:OneItemSelection(false)
	ui.Players:DragAllowed(false)
	ui.Players:ToolTip("Select any number of allied player slots. Tempest Doubles and Meepo clones are included.")
	ControlAlly.Utils.menuIcon(ui.Players, icons.players)

	ui.Abilities = group:MultiSelect("Abilities", {}, true)
	ui.Abilities:DragAllowed(false)
	ui.Abilities:ToolTip(
		"Enabled combat abilities across all selected heroes. Unsafe travel/return skills are omitted."
	)
	ControlAlly.Utils.menuIcon(ui.Abilities, icons.abilities)
	if ui.Abilities.Visible then
		ui.Abilities:Visible(false)
	end

	ui.Items = group:MultiSelect("Items", {}, true)
	ui.Items:DragAllowed(false)
	ui.Items:ToolTip("Enabled combat items across all selected heroes and clones.")
	ControlAlly.Utils.menuIcon(ui.Items, icons.items)
	if ui.Items.Visible then
		ui.Items:Visible(false)
	end

	local settings = ui.Enabled:Gear("Settings", icons.gear, true)
	ui.TargetMode = settings:Combo("Target Mode", { "Cursor", "Smart Score" }, 0)
	ui.TargetMode:ToolTip(
		"Cursor follows your intended enemy; Smart Score favors close, low-health, clustered targets."
	)
	ControlAlly.Utils.menuIcon(ui.TargetMode, icons.target)

	ui.SearchRadius = settings:Slider("Search Radius", 600, 5000, 2400, "%d")
	ControlAlly.Utils.menuIcon(ui.SearchRadius, icons.search)

	ui.MinMana = settings:Slider("Minimum Mana", 0, 80, 5, "%d%%")
	ControlAlly.Utils.menuIcon(ui.MinMana, icons.mana)

	ui.UseAbilities = settings:Switch("Use Abilities", true, icons.abilities)
	ControlAlly.Utils.menuIcon(ui.UseAbilities, icons.abilities)

	ui.UseItems = settings:Switch("Use Items", true, icons.items)
	ControlAlly.Utils.menuIcon(ui.UseItems, icons.items)

	ui.ControlClones = settings:Switch("Control Hero Clones", true, icons.clones)
	ControlAlly.Utils.menuIcon(ui.ControlClones, icons.clones)

	ui.AttackBetweenCasts = settings:Switch("Attack Between Casts", true, icons.attack)
	ui.AttackBetweenCasts:ToolTip(
		"Force a real attack after two non-urgent casts and attack whenever no cast is ready."
	)
	ControlAlly.Utils.menuIcon(ui.AttackBetweenCasts, icons.attack)

	ui.FollowCursor = settings:Switch("Follow Cursor Without Target", true, icons.follow)
	ControlAlly.Utils.menuIcon(ui.FollowCursor, icons.follow)

	ui.Debug = settings:Switch("Debug Log", false, icons.debug)
	ControlAlly.Utils.menuIcon(ui.Debug, icons.debug)

	ControlAlly.Runtime.initialized = true
end

function ControlAlly.Menu.captureSelections(widget, cache)
	if not widget or not widget.List or not widget.Get then
		return
	end
	local list = ControlAlly.Utils.call(widget.List, widget) or {}
	for _, id in ipairs(list) do
		if id ~= "none" then
			local enabled = ControlAlly.Utils.call(widget.Get, widget, id)
			if enabled ~= nil then
				cache[id] = enabled == true
			end
		end
	end
end

function ControlAlly.Menu.isAbilityEnabled(abilityId)
	abilityId = ControlAlly.Profiles.normalizedAbilityId(abilityId)
	local widget = ControlAlly.UI.Abilities
	if widget then
		local enabled = ControlAlly.Utils.call(widget.Get, widget, abilityId)
		if enabled ~= nil then
			return enabled == true
		end
	end
	local cached = ControlAlly.Runtime.abilityEnabled[abilityId]
	return cached == nil or cached == true
end

function ControlAlly.Menu.isItemEnabled(itemId)
	local widget = ControlAlly.UI.Items
	if widget then
		local enabled = ControlAlly.Utils.call(widget.Get, widget, itemId)
		if enabled ~= nil then
			return enabled == true
		end
	end
	local cached = ControlAlly.Runtime.itemEnabled[itemId]
	return cached == nil or cached == true
end

function ControlAlly.Menu.syncActionOptions(now, force)
	if not force and now - ControlAlly.Runtime.lastMenuSyncAt < ControlAlly.Constants.MENU_SYNC_INTERVAL then
		return
	end
	ControlAlly.Runtime.lastMenuSyncAt = now

	ControlAlly.Menu.captureSelections(ControlAlly.UI.Abilities, ControlAlly.Runtime.abilityEnabled)
	ControlAlly.Menu.captureSelections(ControlAlly.UI.Items, ControlAlly.Runtime.itemEnabled)

	local abilityIds = {}
	local itemIds = {}
	local seenUnits = {}
	for _, entry in ipairs(ControlAlly.Runtime.roster) do
		if ControlAlly.Runtime.selectedPlayerIds[entry.playerId] then
			local hero = ControlAlly.Utils.call(Player.GetAssignedHero, entry.player) or entry.hero
			local index = ControlAlly.Utils.entityIndex(hero)
			if hero and index and not seenUnits[index] then
				seenUnits[index] = true
				ControlAlly.AbilityAI.collectMenuIds(hero, abilityIds, itemIds)
			end
		end
	end
	for _, controller in ipairs(ControlAlly.Runtime.controllers) do
		local index = ControlAlly.Utils.entityIndex(controller.unit)
		if index and not seenUnits[index] then
			seenUnits[index] = true
			ControlAlly.AbilityAI.collectMenuIds(controller.unit, abilityIds, itemIds, controller.profileName)
		end
	end

	local abilityList = {}
	for id in pairs(abilityIds) do
		abilityList[#abilityList + 1] = id
	end
	table.sort(abilityList)
	local abilitySignature = table.concat(abilityList, "|")
	local hasAbilities = #abilityList > 0
	if ControlAlly.UI.Abilities and ControlAlly.UI.Abilities.Visible then
		ControlAlly.Utils.call(ControlAlly.UI.Abilities.Visible, ControlAlly.UI.Abilities, hasAbilities)
	end
	if force or abilitySignature ~= ControlAlly.Runtime.actionMenuSignature then
		ControlAlly.Runtime.actionMenuSignature = abilitySignature
		if hasAbilities then
			local rows = {}
			for _, id in ipairs(abilityList) do
				local enabled = ControlAlly.Runtime.abilityEnabled[id]
				if enabled == nil then
					enabled = true
					ControlAlly.Runtime.abilityEnabled[id] = true
				end
				rows[#rows + 1] = { id, ControlAlly.Utils.abilityIcon(id), enabled }
			end
			ControlAlly.Utils.call(ControlAlly.UI.Abilities.Update, ControlAlly.UI.Abilities, rows, true, true)
		end
	end

	local itemList = {}
	for id in pairs(itemIds) do
		itemList[#itemList + 1] = id
	end
	table.sort(itemList)
	local itemSignature = table.concat(itemList, "|")
	local hasItems = #itemList > 0
	if ControlAlly.UI.Items and ControlAlly.UI.Items.Visible then
		ControlAlly.Utils.call(ControlAlly.UI.Items.Visible, ControlAlly.UI.Items, hasItems)
	end
	if force or itemSignature ~= ControlAlly.Runtime.itemMenuSignature then
		ControlAlly.Runtime.itemMenuSignature = itemSignature
		if hasItems then
			local rows = {}
			for _, id in ipairs(itemList) do
				local enabled = ControlAlly.Runtime.itemEnabled[id]
				if enabled == nil then
					enabled = true
					ControlAlly.Runtime.itemEnabled[id] = true
				end
				rows[#rows + 1] = { id, ControlAlly.Utils.abilityIcon(id), enabled }
			end
			ControlAlly.Utils.call(ControlAlly.UI.Items.Update, ControlAlly.UI.Items, rows, true, true)
		end
	end
end

function ControlAlly.Roster.isControllable(unit, playerId)
	if not unit or playerId == nil then
		return false
	end
	local controllable = ControlAlly.Utils.call(Entity.IsControllableByPlayer, unit, playerId)
	if controllable == nil and NPC.IsControllableByPlayer then
		controllable = ControlAlly.Utils.call(NPC.IsControllableByPlayer, unit, playerId)
	end
	return controllable == true
end

function ControlAlly.Roster.connectionLabel(player)
	local data = ControlAlly.Utils.call(Player.GetPlayerData, player)
	local state = type(data) == "table" and data.connectionState or nil
	local labels = {
		[0] = "Unknown",
		[1] = "Not connected",
		[2] = "Connected",
		[3] = "Disconnected",
		[4] = "Abandoned",
		[5] = "Loading",
		[6] = "Failed",
	}
	return labels[state] or (state and ("State " .. tostring(state)) or "Shared control"), state
end

function ControlAlly.Roster.scanPlayers(now, force)
	if not force and now - ControlAlly.Runtime.lastRosterScanAt < ControlAlly.Constants.ROSTER_SCAN_INTERVAL then
		return
	end
	ControlAlly.Runtime.lastRosterScanAt = now

	local localPlayer = ControlAlly.Utils.call(Players.GetLocal)
	local localHero = ControlAlly.Utils.call(Heroes.GetLocal)
	local localPlayerId = localPlayer and ControlAlly.Utils.call(Player.GetPlayerID, localPlayer)
	ControlAlly.Runtime.localPlayer = localPlayer
	ControlAlly.Runtime.localPlayerId = localPlayerId
	ControlAlly.Runtime.localHero = localHero
	if not localPlayer or not localHero or localPlayerId == nil then
		return
	end

	local previouslySelected = {}
	if ControlAlly.UI.Players and ControlAlly.UI.Players.ListEnabled then
		for _, label in ipairs(ControlAlly.Utils.call(ControlAlly.UI.Players.ListEnabled, ControlAlly.UI.Players) or {}) do
			local oldPlayerId = ControlAlly.Runtime.playerLabelToId[label]
			if oldPlayerId ~= nil then
				previouslySelected[oldPlayerId] = true
			end
		end
	end

	local roster = {}
	for _, player in ipairs(ControlAlly.Utils.call(Players.GetAll) or {}) do
		local playerId = ControlAlly.Utils.call(Player.GetPlayerID, player)
		local hero = ControlAlly.Utils.call(Player.GetAssignedHero, player)
		if
			playerId ~= nil
			and playerId ~= localPlayerId
			and ControlAlly.Utils.isValidHero(hero, false)
			and ControlAlly.Utils.call(Entity.IsSameTeam, hero, localHero) == true
			and ControlAlly.Roster.isControllable(hero, localPlayerId)
		then
			local unitName = ControlAlly.Utils.unitName(hero) or "unknown"
			local displayName = ControlAlly.Utils.heroDisplayName(unitName)
			local label = string.format("%s (P%d)", displayName, playerId + 1)
			local widgetId = label
			local connection, connectionState = ControlAlly.Roster.connectionLabel(player)
			roster[#roster + 1] = {
				player = player,
				playerId = playerId,
				hero = hero,
				unitName = unitName,
				label = label,
				widgetId = widgetId,
				connection = connection,
				connectionState = connectionState,
			}
		end
	end
	table.sort(roster, function(a, b)
		return a.playerId < b.playerId
	end)

	local signatureParts = {}
	local rosterById = {}
	local labelToId = {}
	for _, entry in ipairs(roster) do
		rosterById[entry.playerId] = entry
		labelToId[entry.widgetId] = entry.playerId
		signatureParts[#signatureParts + 1] =
			string.format("%d:%s:%s", entry.playerId, entry.unitName, tostring(entry.connectionState))
	end
	local signature = table.concat(signatureParts, "|")

	ControlAlly.Runtime.roster = roster
	ControlAlly.Runtime.rosterById = rosterById
	ControlAlly.Runtime.playerLabelToId = labelToId
	if force or signature ~= ControlAlly.Runtime.rosterSignature then
		ControlAlly.Runtime.rosterSignature = signature
		local rows = {}
		local tooltips = {}
		for _, entry in ipairs(roster) do
			local enabled = not ControlAlly.Runtime.rosterInitialized or previouslySelected[entry.playerId] == true
			rows[#rows + 1] = {
				entry.widgetId,
				ControlAlly.Utils.heroIcon(entry.unitName),
				enabled,
			}
			tooltips[entry.widgetId] = string.format(
				"%s - %s; player slot %d; controllable through disconnected/shared control.",
				entry.label,
				entry.connection,
				entry.playerId + 1
			)
		end
		if #rows == 0 then
			rows[1] = { "No controllable allies", "", false }
		end
		ControlAlly.Utils.call(ControlAlly.UI.Players.Update, ControlAlly.UI.Players, rows, false, true)
		if ControlAlly.UI.Players.UpdateToolTips then
			ControlAlly.Utils.call(ControlAlly.UI.Players.UpdateToolTips, ControlAlly.UI.Players, tooltips)
		end
		ControlAlly.Runtime.rosterInitialized = true
	end
end

function ControlAlly.Roster.readSelectedPlayers()
	local selected = {}
	if ControlAlly.UI.Players and ControlAlly.UI.Players.ListEnabled then
		for _, label in ipairs(ControlAlly.Utils.call(ControlAlly.UI.Players.ListEnabled, ControlAlly.UI.Players) or {}) do
			local playerId = ControlAlly.Runtime.playerLabelToId[label]
			if playerId ~= nil then
				selected[playerId] = true
			end
		end
	end
	ControlAlly.Runtime.selectedPlayerIds = selected
	return selected
end

function ControlAlly.Roster.toggleRegistryRecord(unit, playerId, create)
	local index = ControlAlly.Utils.entityIndex(unit)
	if not index then
		return nil, nil
	end
	local heroName = ControlAlly.Utils.unitName(unit)
	local record = ControlAlly.Runtime.toggleOwnershipRegistry[index]
	if
		type(record) ~= "table"
		or type(record.abilities) ~= "table"
		or record.unit ~= unit
		or record.playerId ~= playerId
		or record.heroName ~= heroName
	then
		ControlAlly.Runtime.toggleOwnershipRegistry[index] = nil
		record = nil
	end
	if not record and create then
		record = {
			unit = unit,
			playerId = playerId,
			heroName = heroName,
			abilities = {},
		}
		ControlAlly.Runtime.toggleOwnershipRegistry[index] = record
	end
	return record, index
end

function ControlAlly.Roster.newControllerState(unit, playerId, isClone, isSummon, profileName)
	local ownedToggles = {}
	local toggleRecord = ControlAlly.Roster.toggleRegistryRecord(unit, playerId, false)
	for id, owned in pairs(toggleRecord and toggleRecord.abilities or {}) do
		if owned then
			ownedToggles[id] = true
		end
	end
	return {
		unit = unit,
		playerId = playerId,
		isClone = isClone,
		isSummon = isSummon == true,
		detached = false,
		heroName = ControlAlly.Utils.unitName(unit),
		profileName = profileName or ControlAlly.Utils.unitName(unit),
		nextThinkAt = -math.huge,
		nextOrderAt = -math.huge,
		busyUntil = -math.huge,
		lastAttackAt = -math.huge,
		lastAttackTarget = nil,
		interleaveTarget = nil,
		interleaveDeadline = -math.huge,
		lastMoveAt = -math.huge,
		lastMovePosition = nil,
		lastFaceAt = -math.huge,
		motionLockUntil = -math.huge,
		motionLockStartedAt = -math.huge,
		motionModifiers = nil,
		motionTarget = nil,
		stopRequested = false,
		lastIssued = {},
		pendingCast = nil,
		castsSinceAttack = 0,
		activeAbility = nil,
		catalog = nil,
		catalogRefreshAt = -math.huge,
		lastRefreshableCastAt = -math.huge,
		lastRearmAt = -math.huge,
		lastRefresherAt = -math.huge,
		usedAbilitiesSinceRefresh = {},
		ownedToggles = ownedToggles,
		invoker = {
			spellId = nil,
			orbIndex = 1,
			nextStepAt = -math.huge,
			waitUntil = -math.huge,
			combo = nil,
			iceWallStand = nil,
		},
		meepo = {
			lastNetAt = -math.huge,
		},
		alchemist = {
			brewing = false,
			startedAt = -math.huge,
			target = nil,
		},
		techies = {
			minePlan = nil,
		},
		kez = {
			formCasts = {},
			lastSwitchAt = -math.huge,
			castsAfterSwitch = 0,
		},
		special = {
			stage = nil,
			target = nil,
			followup = nil,
			startedAt = -math.huge,
			lastBallAt = -math.huge,
		},
	}
end

function ControlAlly.Roster.addController(desired, seen, unit, playerId, assignedHero, forceClone, forceSummon)
	if
		not ControlAlly.Utils.isValidControllerUnit(unit, true)
		or ControlAlly.Utils.call(Entity.IsDormant, unit) == true
		or ControlAlly.Roster.isControllable(unit, ControlAlly.Runtime.localPlayerId) ~= true
	then
		return
	end
	if
		unit ~= assignedHero
		and not forceClone
		and not forceSummon
		and ControlAlly.Utils.call(NPC.IsIllusion, unit) == true
	then
		return
	end
	local index = ControlAlly.Utils.entityIndex(unit)
	if not index or seen[index] then
		return
	end
	seen[index] = true
	local isClone = forceClone == true or (unit ~= assignedHero and ControlAlly.Utils.isHeroClone(unit, assignedHero))
	local isSummon = forceSummon == true
	local state = ControlAlly.Runtime.controllerStates[index]
	local heroName = ControlAlly.Utils.unitName(unit)
	local profileName = forceClone and ControlAlly.Utils.unitName(assignedHero) or heroName
	if not state or state.unit ~= unit or state.playerId ~= playerId or state.heroName ~= heroName then
		state = ControlAlly.Roster.newControllerState(unit, playerId, isClone, isSummon, profileName)
		ControlAlly.Runtime.controllerStates[index] = state
	else
		state.unit = unit
		state.playerId = playerId
		state.isClone = isClone
		state.isSummon = isSummon
		state.heroName = ControlAlly.Utils.unitName(unit)
		state.profileName = profileName
		state.detached = false
	end
	if ControlAlly.SpecialAI.reconcileController then
		ControlAlly.SpecialAI.reconcileController(state, ControlAlly.Utils.gameTime())
	end
	desired[#desired + 1] = state
	if isClone then
		ControlAlly.Runtime.cloneCountByPlayer[playerId] = (ControlAlly.Runtime.cloneCountByPlayer[playerId] or 0) + 1
	end
end

function ControlAlly.Roster.refreshControllers(now, force)
	if
		not force
		and now - ControlAlly.Runtime.lastControllerScanAt < ControlAlly.Constants.CONTROLLER_SCAN_INTERVAL
	then
		return
	end
	ControlAlly.Runtime.lastControllerScanAt = now
	local selected = ControlAlly.Roster.readSelectedPlayers()
	local desired = {}
	local seen = {}
	ControlAlly.Runtime.cloneCountByPlayer = {}
	local allHeroes = ControlAlly.Utils.call(Heroes.GetAll) or {}

	for playerId in pairs(selected) do
		local entry = ControlAlly.Runtime.rosterById[playerId]
		if entry then
			local assignedHero = ControlAlly.Utils.call(Player.GetAssignedHero, entry.player) or entry.hero
			local assignedName = ControlAlly.Utils.unitName(assignedHero)
			entry.hero = assignedHero
			ControlAlly.Roster.addController(desired, seen, assignedHero, playerId, assignedHero)

			if ControlAlly.UI.ControlClones and ControlAlly.UI.ControlClones:Get() == true then
				if
					assignedName == "npc_dota_hero_dazzle"
					and XHelpers
					and XHelpers.XNPC
					and XHelpers.XNPC.GetNothlProjection
				then
					local projection =
						ControlAlly.Utils.call(XHelpers.XNPC.GetNothlProjection, XHelpers.XNPC, assignedHero)
					ControlAlly.Roster.addController(desired, seen, projection, playerId, assignedHero, true, false)
				end

				if assignedName == "npc_dota_hero_lone_druid" and CustomEntities and CustomEntities.GetSpiritBear then
					local summon = ControlAlly.Utils.call(NPC.GetAbility, assignedHero, "lone_druid_spirit_bear")
					local bear = summon and ControlAlly.Utils.call(CustomEntities.GetSpiritBear, summon)
					if bear and ControlAlly.Utils.call(NPC.GetOwnerNPC, bear) == assignedHero then
						ControlAlly.Roster.addController(desired, seen, bear, playerId, assignedHero, false, true)
					end
				end

				if
					assignedName == "npc_dota_hero_arc_warden"
					and CustomEntities
					and CustomEntities.GetTempestDouble
				then
					local tempestAbility =
						ControlAlly.Utils.call(NPC.GetAbility, assignedHero, "arc_warden_tempest_double")
					local linkedDouble = tempestAbility
						and ControlAlly.Utils.call(CustomEntities.GetTempestDouble, tempestAbility)
					ControlAlly.Roster.addController(desired, seen, linkedDouble, playerId, assignedHero)
				end

				for _, candidate in ipairs(allHeroes) do
					if candidate ~= assignedHero then
						local candidatePlayerId = ControlAlly.Utils.call(Hero.GetPlayerID, candidate)
						if candidatePlayerId == playerId and ControlAlly.Utils.isHeroClone(candidate, assignedHero) then
							ControlAlly.Roster.addController(desired, seen, candidate, playerId, assignedHero)
						end
					end
				end
			end
		end
	end

	table.sort(desired, function(a, b)
		if a.playerId ~= b.playerId then
			return a.playerId < b.playerId
		end
		return (ControlAlly.Utils.entityIndex(a.unit) or 0) < (ControlAlly.Utils.entityIndex(b.unit) or 0)
	end)
	for index, controller in pairs(ControlAlly.Runtime.controllerStates) do
		if not seen[index] then
			local retainForSafety = (controller.alchemist and controller.alchemist.brewing)
				or next(controller.ownedToggles or {}) ~= nil
				or controller.pendingCast ~= nil
				or ControlAlly.Utils.protectedActivity(controller.unit, controller.activeAbility) ~= nil
				or (ControlAlly.SpecialAI.requiresRetention and ControlAlly.SpecialAI.requiresRetention(controller))
			if ControlAlly.Runtime.inSession then
				ControlAlly.Combat.rollbackPendingReservations(controller)
				controller.stopRequested = true
				ControlAlly.Orders.stop(controller)
			end
			if not retainForSafety and not controller.stopRequested then
				ControlAlly.Runtime.controllerStates[index] = nil
			else
				controller.detached = true
			end
		end
	end
	ControlAlly.Runtime.controllers = desired

	local signatureParts = {}
	for _, controller in ipairs(desired) do
		signatureParts[#signatureParts + 1] = string.format(
			"%d:%d:%s",
			controller.playerId,
			ControlAlly.Utils.entityIndex(controller.unit) or -1,
			controller.heroName or ""
		)
	end
	local signature = table.concat(signatureParts, "|")
	if signature ~= ControlAlly.Runtime.controllerSignature then
		ControlAlly.Runtime.controllerSignature = signature
		ControlAlly.Runtime.actionMenuSignature = ""
		ControlAlly.Runtime.itemMenuSignature = ""
		ControlAlly.Utils.debug("controllers refreshed: %d unit(s)", #desired)
	end
end

function ControlAlly.Targeting.refreshBuiltinComboBind(now, force)
	if
		not force
		and now - ControlAlly.Runtime.lastBuiltinBindScanAt < ControlAlly.Constants.BUILTIN_BIND_SCAN_INTERVAL
	then
		return
	end
	ControlAlly.Runtime.lastBuiltinBindScanAt = now
	local hero = ControlAlly.Runtime.localHero or ControlAlly.Utils.call(Heroes.GetLocal)
	local unitName = hero and ControlAlly.Utils.unitName(hero)
	local heroName = unitName and ControlAlly.Utils.heroDisplayName(unitName)
	if heroName == ControlAlly.Runtime.builtinComboHeroName and ControlAlly.Runtime.builtinComboBind then
		return
	end
	ControlAlly.Runtime.builtinComboHeroName = heroName
	ControlAlly.Runtime.builtinComboBind = nil
	if not heroName then
		return
	end

	ControlAlly.Runtime.builtinComboBind = ControlAlly.Utils.call(
		Menu.Find,
		"Heroes",
		"Hero List",
		heroName,
		"Main Settings",
		"Hero Settings",
		"Combo Key"
	) or ControlAlly.Utils.call(Menu.Find, "Heroes", "Hero List", heroName, "Main Settings", "General", "Combo Key") or ControlAlly.Utils.call(
		Menu.Find,
		"Heroes",
		"Hero List",
		heroName,
		"Main Settings",
		"Combo Key"
	)
end

function ControlAlly.Targeting.isActivationHeld(now)
	if ControlAlly.Utils.call(Input.IsInputCaptured) == true then
		return false
	end
	ControlAlly.Targeting.refreshBuiltinComboBind(now, false)
	local builtin = ControlAlly.Runtime.builtinComboBind
	return builtin ~= nil and ControlAlly.Utils.call(builtin.IsDown, builtin) == true
end

function ControlAlly.Targeting.isValidEnemy(enemy)
	local localHero = ControlAlly.Runtime.localHero
	return ControlAlly.Utils.isValidHero(enemy, true)
		and localHero ~= nil
		and ControlAlly.Utils.call(Entity.IsSameTeam, enemy, localHero) == false
		and ControlAlly.Utils.call(Entity.IsDormant, enemy) ~= true
		and ControlAlly.Utils.call(NPC.IsVisible, enemy) == true
		and ControlAlly.Utils.call(NPC.IsIllusion, enemy) ~= true
end

function ControlAlly.Targeting.refreshEnemies(now, force)
	now = now or ControlAlly.Utils.gameTime()
	if
		not force
		and now - (ControlAlly.Runtime.lastEnemyScanAt or -math.huge) < ControlAlly.Constants.ENEMY_SCAN_INTERVAL
	then
		return ControlAlly.Runtime.enemies
	end
	ControlAlly.Runtime.lastEnemyScanAt = now
	local enemies = {}
	for _, hero in ipairs(ControlAlly.Utils.call(Heroes.GetAll) or {}) do
		if ControlAlly.Targeting.isValidEnemy(hero) then
			enemies[#enemies + 1] = hero
		end
	end
	ControlAlly.Runtime.enemies = enemies
	return enemies
end

function ControlAlly.Targeting.minimumControllerDistance(enemy)
	local enemyPosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, enemy)
	local best = math.huge
	for _, controller in ipairs(ControlAlly.Runtime.controllers) do
		local position = ControlAlly.Utils.call(Entity.GetAbsOrigin, controller.unit)
		best = math.min(best, ControlAlly.Utils.distance2D(position, enemyPosition))
	end
	if ControlAlly.Runtime.localHero then
		local localPosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, ControlAlly.Runtime.localHero)
		best = math.min(best, ControlAlly.Utils.distance2D(localPosition, enemyPosition))
	end
	return best
end

function ControlAlly.Targeting.isWithinSearch(enemy, leashMultiplier)
	local searchRadius = ControlAlly.UI.SearchRadius and ControlAlly.UI.SearchRadius:Get() or 2400
	return ControlAlly.Targeting.minimumControllerDistance(enemy) <= searchRadius * (leashMultiplier or 1)
end

function ControlAlly.Targeting.cursorCandidate()
	local localHero = ControlAlly.Runtime.localHero
	local team = localHero and ControlAlly.Utils.call(Entity.GetTeamNum, localHero)
	if not team then
		return nil
	end
	local candidate = ControlAlly.Utils.call(Input.GetNearestHeroToCursor, team, Enum.TeamType.TEAM_ENEMY)
	if not ControlAlly.Targeting.isValidEnemy(candidate) or not ControlAlly.Targeting.isWithinSearch(candidate, 1) then
		return nil
	end
	local cursor = ControlAlly.Utils.call(Input.GetWorldCursorPos)
	local position = ControlAlly.Utils.call(Entity.GetAbsOrigin, candidate)
	if
		cursor
		and position
		and ControlAlly.Utils.distance2D(cursor, position) > ControlAlly.Constants.TARGET_SWITCH_CURSOR_RADIUS
	then
		return nil
	end
	return candidate
end

function ControlAlly.Targeting.clusterCount(enemy, radius)
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, enemy)
	local count = 0
	for _, candidate in ipairs(ControlAlly.Runtime.enemies) do
		local position = ControlAlly.Utils.call(Entity.GetAbsOrigin, candidate)
		if ControlAlly.Utils.distance2D(origin, position) <= radius then
			count = count + 1
		end
	end
	return count
end

function ControlAlly.Targeting.smartScore(enemy)
	local healthScore = 100 - ControlAlly.Utils.healthPct(enemy)
	local distance = ControlAlly.Targeting.minimumControllerDistance(enemy)
	local cluster = ControlAlly.Targeting.clusterCount(enemy, 500)
	local score = healthScore * 3 - distance * 0.08 + cluster * 90
	local cursor = ControlAlly.Utils.call(Input.GetWorldCursorPos)
	local position = ControlAlly.Utils.call(Entity.GetAbsOrigin, enemy)
	if cursor and position then
		score = score - math.min(ControlAlly.Utils.distance2D(cursor, position), 1500) * 0.04
	end
	if ControlAlly.Utils.isMagicImmune(enemy) then
		score = score - 130
	end
	return score
end

function ControlAlly.Targeting.resolve(now, force)
	local locked = ControlAlly.Runtime.lockedTarget
	if
		locked
		and (
			not ControlAlly.Targeting.isValidEnemy(locked)
			or not ControlAlly.Targeting.isWithinSearch(locked, ControlAlly.Constants.TARGET_LOCK_LEASH)
		)
	then
		locked = nil
		ControlAlly.Runtime.lockedTarget = nil
	end

	local cursorCandidate = ControlAlly.Targeting.cursorCandidate()
	if cursorCandidate and cursorCandidate ~= locked then
		local cursor = ControlAlly.Utils.call(Input.GetWorldCursorPos)
		local candidatePosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, cursorCandidate)
		local deliberateSwitch = cursor
			and ControlAlly.Utils.distance2D(cursor, candidatePosition)
				<= ControlAlly.Constants.TARGET_SWITCH_CURSOR_RADIUS
		if force or not locked or (deliberateSwitch and now - ControlAlly.Runtime.lastTargetSwitchAt >= 0.12) then
			locked = cursorCandidate
			ControlAlly.Runtime.lockedTarget = cursorCandidate
			ControlAlly.Runtime.lastTargetSwitchAt = now
		end
	end

	if locked then
		return locked
	end
	if ControlAlly.UI.TargetMode and ControlAlly.UI.TargetMode:Get() == 0 then
		return nil
	end

	local bestTarget
	local bestScore = -math.huge
	for _, enemy in ipairs(ControlAlly.Runtime.enemies) do
		if ControlAlly.Targeting.isWithinSearch(enemy, 1) then
			local score = ControlAlly.Targeting.smartScore(enemy)
			if score > bestScore then
				bestTarget = enemy
				bestScore = score
			end
		end
	end
	ControlAlly.Runtime.lockedTarget = bestTarget
	return bestTarget
end

function ControlAlly.Targeting.predictPosition(target, ability, rule)
	local position = ControlAlly.Utils.call(Entity.GetAbsOrigin, target)
	if not position then
		return nil
	end
	local castPoint = ControlAlly.Utils.call(Ability.GetCastPoint, ability, true)
		or ControlAlly.Utils.call(Ability.GetCastPoint, ability)
		or 0
	local owner = ControlAlly.Utils.call(Ability.GetOwner, ability)
	local ownerPosition = owner and ControlAlly.Utils.call(Entity.GetAbsOrigin, owner)
	local faceTime = owner and ControlAlly.Utils.call(NPC.GetTimeToFacePosition, owner, position) or 0
	faceTime = type(faceTime) == "number" and math.max(0, faceTime) or 0
	local delay = ControlAlly.Utils.ruleValue(ability, rule, "lead", "delaySpecial", 0) or 0
	local projectileSpeed = ControlAlly.Utils.ruleValue(ability, rule, "projectileSpeed", "projectileSpeedSpecial", 0)
		or 0
	local travelTime = 0
	if projectileSpeed > 0 then
		local distance = ControlAlly.Utils.distance2D(ownerPosition, position)
		travelTime = distance < math.huge and distance / projectileSpeed or 0
	end
	local lead = math.max(0, faceTime + castPoint + delay + travelTime)
	local states = Enum.ModifierState
	local immobile = ControlAlly.Utils.call(NPC.IsStunned, target) == true
		or (states and ControlAlly.Utils.hasState(target, states.MODIFIER_STATE_ROOTED))
		or ControlAlly.Utils.modifierRemaining(target, "modifier_invoker_tornado", ControlAlly.Utils.gameTime()) > 0
	if lead > 0 and ControlAlly.Utils.call(NPC.IsRunning, target) == true then
		local speed = immobile and 0 or (ControlAlly.Utils.call(NPC.GetMoveSpeed, target) or 0)
		for _ = 1, 8 do
			local previousLead = lead
			local forward = ControlAlly.Utils.call(Entity.GetForwardPosition, target, speed * lead)
			if not forward then
				break
			end
			position = forward
			local refinedFace = owner and ControlAlly.Utils.call(NPC.GetTimeToFacePosition, owner, position) or 0
			refinedFace = type(refinedFace) == "number" and math.max(0, refinedFace) or 0
			local refinedDistance = ControlAlly.Utils.distance2D(ownerPosition, position)
			local refinedTravel = projectileSpeed > 0
					and refinedDistance < math.huge
					and refinedDistance / projectileSpeed
				or 0
			lead = math.max(0, refinedFace + castPoint + delay + refinedTravel)
			if math.abs(lead - previousLead) <= 0.015 then
				break
			end
		end
	end
	return position
end

function ControlAlly.Targeting.bestAoePosition(context, ability, rule, radius, castRange)
	local target = context.target
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
	local primary = ControlAlly.Targeting.predictPosition(target, ability, rule)
	if not origin or not primary then
		return nil, 0
	end

	local candidates = { primary }
	local nearby = {}
	for _, enemy in ipairs(ControlAlly.Runtime.enemies) do
		local predicted = ControlAlly.Targeting.predictPosition(enemy, ability, rule)
		if predicted and ControlAlly.Utils.distance2D(predicted, primary) <= radius * 2.2 then
			nearby[#nearby + 1] = predicted
			candidates[#candidates + 1] = predicted
		end
	end
	if #nearby >= 2 then
		local x, y, z = 0, 0, 0
		for _, position in ipairs(nearby) do
			x = x + position.x
			y = y + position.y
			z = z + (position.z or 0)
		end
		candidates[#candidates + 1] = Vector(x / #nearby, y / #nearby, z / #nearby)
	end

	local bestPosition
	local bestHits = -1
	local bestScore = -math.huge
	for _, candidate in ipairs(candidates) do
		local distance = ControlAlly.Utils.distance2D(origin, candidate)
		if rule.global or distance <= castRange + radius then
			local castPosition = candidate
			if not rule.global and distance > castRange then
				castPosition = ControlAlly.Utils.positionToward(origin, candidate, castRange)
			end
			local allyHits = 0
			if rule.avoidAllies then
				for _, hero in ipairs(ControlAlly.Utils.call(Heroes.GetAll) or {}) do
					if
						ControlAlly.Utils.isValidHero(hero, true)
						and ControlAlly.Utils.call(Entity.IsSameTeam, hero, context.unit) == true
						and (hero ~= context.unit or not rule.ignoreCaster)
						and ControlAlly.Utils.distance2D(
								castPosition,
								ControlAlly.Utils.call(Entity.GetAbsOrigin, hero)
							)
							<= radius
					then
						allyHits = allyHits + 1
					end
				end
			end
			if not rule.avoidAllies or allyHits <= (rule.maxAlliesHit or 0) then
				local hits = 0
				local includesPrimary = false
				for _, enemy in ipairs(ControlAlly.Runtime.enemies) do
					local predicted = ControlAlly.Targeting.predictPosition(enemy, ability, rule)
					if predicted and ControlAlly.Utils.distance2D(castPosition, predicted) <= radius then
						hits = hits + 1
						if enemy == target then
							includesPrimary = true
						end
					end
				end
				local score = hits * 100 + (includesPrimary and 75 or 0) - allyHits * 250
				if
					(not rule.requirePrimary or includesPrimary)
					and (hits > bestHits or (hits == bestHits and score > bestScore))
				then
					bestPosition = castPosition
					bestHits = hits
					bestScore = score
				end
			end
		end
	end
	return bestPosition, math.max(0, bestHits)
end

function ControlAlly.Targeting.hardDisableRemaining(target)
	local modifierStates = Enum.ModifierState
	if not target or not modifierStates or not NPC.GetStatesDuration then
		return 0
	end
	local requested = {}
	for _, stateName in ipairs({
		"MODIFIER_STATE_STUNNED",
		"MODIFIER_STATE_HEXED",
		"MODIFIER_STATE_NIGHTMARED",
		"MODIFIER_STATE_FROZEN",
		"MODIFIER_STATE_ROOTED",
	}) do
		local state = modifierStates[stateName]
		if state ~= nil then
			requested[state] = true
		end
	end
	local durations = ControlAlly.Utils.call(NPC.GetStatesDuration, target, requested, true)
	local remaining = 0
	if type(durations) == "table" then
		for _, duration in pairs(durations) do
			if type(duration) == "number" then
				remaining = math.max(remaining, duration)
			end
		end
	end
	return remaining
end

function ControlAlly.Orders.nextIdentifier(controller, tag)
	ControlAlly.Runtime.orderSequence = ControlAlly.Runtime.orderSequence + 1
	return string.format(
		"control_ally:%d:%d:%d:%s",
		ControlAlly.Runtime.sessionGeneration or 0,
		ControlAlly.Utils.entityIndex(controller.unit) or -1,
		ControlAlly.Runtime.orderSequence,
		tag or "order"
	)
end

function ControlAlly.Orders.canOrder(controller)
	return controller ~= nil
		and ControlAlly.Runtime.localPlayer ~= nil
		and ControlAlly.Runtime.localPlayerId ~= nil
		and ControlAlly.Utils.isValidControllerUnit(controller.unit, true)
		and ControlAlly.Utils.call(Entity.IsDormant, controller.unit) ~= true
		and not ControlAlly.Utils.isCommandRestricted(controller.unit)
		and ControlAlly.Roster.isControllable(controller.unit, ControlAlly.Runtime.localPlayerId)
end

function ControlAlly.Orders.issue(controller, orderType, target, position, ability, tag, executeFast, orderGap)
	local now = ControlAlly.Utils.gameTime()
	if
		ControlAlly.Runtime.orderBudget <= 0
		or now < (controller.nextOrderAt or -math.huge)
		or not ControlAlly.Orders.canOrder(controller)
	then
		return false
	end
	position = position or ControlAlly.Utils.call(Entity.GetAbsOrigin, controller.unit) or Vector(0, 0, 0)
	local identifier = ControlAlly.Orders.nextIdentifier(controller, tag)
	local ok = ControlAlly.Utils.try(
		Player.PrepareUnitOrders,
		ControlAlly.Runtime.localPlayer,
		orderType,
		target,
		position,
		ability,
		Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY,
		controller.unit,
		false,
		false,
		false,
		executeFast == true,
		identifier,
		true
	)
	if not ok then
		return false
	end
	controller.nextOrderAt = now + (orderGap or ControlAlly.Constants.ORDER_GAP)
	ControlAlly.Runtime.orderBudget = ControlAlly.Runtime.orderBudget - 1
	return true
end

function ControlAlly.Orders.stop(controller)
	local now = ControlAlly.Utils.gameTime()
	if
		not controller
		or ControlAlly.Runtime.orderBudget <= 0
		or not ControlAlly.Orders.canOrder(controller)
		or ControlAlly.Utils.isMotionLocked(controller, now)
		or ControlAlly.Utils.protectedActivity(controller.unit, controller.activeAbility) ~= nil
	then
		return false
	end
	local position = ControlAlly.Utils.call(Entity.GetAbsOrigin, controller.unit) or Vector(0, 0, 0)
	local ok = ControlAlly.Utils.try(
		Player.PrepareUnitOrders,
		ControlAlly.Runtime.localPlayer,
		Enum.UnitOrder.DOTA_UNIT_ORDER_STOP,
		nil,
		position,
		nil,
		Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY,
		controller.unit,
		false,
		false,
		false,
		false,
		ControlAlly.Orders.nextIdentifier(controller, "stop"),
		true
	)
	if ok then
		controller.nextOrderAt = now + ControlAlly.Constants.ORDER_GAP
		controller.stopRequested = false
		ControlAlly.Runtime.orderBudget = ControlAlly.Runtime.orderBudget - 1
	end
	return ok
end

function ControlAlly.Orders.issueVectorCast(
	controller,
	ability,
	startPosition,
	endPosition,
	tag,
	finalOrderType,
	target,
	orderGap
)
	local now = ControlAlly.Utils.gameTime()
	if
		ControlAlly.Runtime.orderBudget < 2
		or now < (controller.nextOrderAt or -math.huge)
		or not ControlAlly.Orders.canOrder(controller)
	then
		return false
	end
	local player = ControlAlly.Runtime.localPlayer
	local issuer = Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY
	local vectorOk = ControlAlly.Utils.try(
		Player.PrepareUnitOrders,
		player,
		Enum.UnitOrder.DOTA_UNIT_ORDER_VECTOR_TARGET_POSITION,
		target,
		endPosition,
		ability,
		issuer,
		controller.unit,
		false,
		true,
		false,
		true,
		ControlAlly.Orders.nextIdentifier(controller, tag .. "_vector"),
		true
	)
	if not vectorOk then
		return false
	end
	ControlAlly.Runtime.orderBudget = ControlAlly.Runtime.orderBudget - 1
	local castOk = ControlAlly.Utils.try(
		Player.PrepareUnitOrders,
		player,
		finalOrderType or Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_POSITION,
		target,
		startPosition,
		ability,
		issuer,
		controller.unit,
		false,
		true,
		false,
		true,
		ControlAlly.Orders.nextIdentifier(controller, tag .. "_cast"),
		true
	)
	if not castOk then
		controller.nextOrderAt = now + (orderGap or ControlAlly.Constants.ORDER_GAP)
		return false
	end
	controller.nextOrderAt = now + (orderGap or ControlAlly.Constants.ORDER_GAP)
	ControlAlly.Runtime.orderBudget = ControlAlly.Runtime.orderBudget - 1
	return true
end

function ControlAlly.Orders.cast(controller, action, now)
	if
		ControlAlly.Utils.protectedActivity(controller.unit, controller.activeAbility) ~= nil
		and action.allowDuringProtected ~= true
	then
		return false
	end
	local orderType
	local target
	local position
	if action.policy == "enemy" or action.policy == "self" or action.policy == "ally" then
		orderType = Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TARGET
		target = action.target
	elseif
		action.policy == "point"
		or action.policy == "allyPoint"
		or action.policy == "selfPosition"
		or action.policy == "gapclose"
	then
		orderType = Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_POSITION
		position = action.position
	elseif action.policy == "noTarget" then
		orderType = Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_NO_TARGET
	elseif action.policy == "vector" then
		position = action.position
	elseif action.policy == "vectorTarget" then
		target = action.target
		position = action.position
	elseif action.policy == "tree" then
		orderType = Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TARGET_TREE
		target = action.target
	elseif action.policy == "toggle" then
		orderType = Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TOGGLE
	elseif action.policy == "toggleAlt" then
		orderType = Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TOGGLE_ALT
	else
		return false
	end

	local dedupeKey = action.dedupeKey or action.id
	local dedupeInterval = action.allowRapid and 0.035 or ControlAlly.Constants.CAST_DEDUP_INTERVAL
	if now - (controller.lastIssued[dedupeKey] or -math.huge) < dedupeInterval then
		return false
	end
	local cooldownBefore = ControlAlly.Utils.cooldownRemaining(action.ability)
	local chargesBefore = ControlAlly.Utils.call(Ability.GetCurrentCharges, action.ability)
	local secondsBefore = ControlAlly.Utils.call(Ability.SecondsSinceLastUse, action.ability)
	local castStartBefore = ControlAlly.Utils.call(Ability.GetCastStartTime, action.ability)
	local hiddenBefore = ControlAlly.Utils.call(Ability.IsHidden, action.ability)
	local toggleBefore = ControlAlly.Utils.call(Ability.GetToggleState, action.ability)
	local altBefore = Ability.GetAltCastState and ControlAlly.Utils.call(Ability.GetAltCastState, action.ability)
	local behavior = ControlAlly.Utils.call(Ability.GetBehavior, action.ability) or 0
	local channelled = ControlAlly.Utils.hasFlag(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_CHANNELLED)
	local channelTime = 0
	if channelled then
		channelTime = ControlAlly.Utils.specialValue(
			action.ability,
			{ "AbilityChannelTime", "channel_time", "channel_duration" },
			0
		)
	end
	local refreshCooldownsBefore
	if action.isRearm then
		channelTime = ControlAlly.TinkerAI.rearmChannelTime(action.ability)
		refreshCooldownsBefore = {}
		for _, entry in ipairs(ControlAlly.AbilityAI.catalog(controller, now).abilities) do
			if ControlAlly.Profiles.RefreshableTinkerActions[entry.id] then
				refreshCooldownsBefore[entry.id] = ControlAlly.Utils.cooldownRemaining(entry.ability)
			end
		end
	elseif action.isRefresher then
		refreshCooldownsBefore = {}
		for id in pairs(controller.usedAbilitiesSinceRefresh) do
			local refreshed = ControlAlly.AbilityAI.findAbility(controller, id, now)
			refreshCooldownsBefore[id] = ControlAlly.Utils.cooldownRemaining(refreshed)
		end
	end
	local issued
	if action.policy == "vector" or action.policy == "vectorTarget" then
		issued = ControlAlly.Orders.issueVectorCast(
			controller,
			action.ability,
			action.position,
			action.vectorEnd,
			"cast_" .. tostring(action.id),
			action.policy == "vectorTarget" and Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_TARGET
				or Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_POSITION,
			action.target,
			action.orderGap
		)
	else
		issued = ControlAlly.Orders.issue(
			controller,
			orderType,
			target,
			position,
			action.ability,
			"cast_" .. tostring(action.id),
			action.executeFast == true,
			action.orderGap
		)
	end
	if not issued then
		return false
	end

	controller.lastIssued[dedupeKey] = now
	controller.activeAbility = action.ability
	local castPoint = ControlAlly.Utils.call(Ability.GetCastPoint, action.ability) or 0
	controller.busyUntil = (action.internal or action.fastCombo) and (now + math.max(0.008, castPoint + 0.008))
		or (now + math.max(0.08, castPoint + 0.14))
	if action.attackModifier then
		controller.busyUntil = math.max(
			controller.busyUntil,
			now + (ControlAlly.Utils.call(NPC.GetAttackAnimPoint, controller.unit) or 0) + 0.12
		)
	end
	controller.pendingCast = {
		ability = action.ability,
		id = action.id,
		issuedAt = now,
		sessionGeneration = ControlAlly.Runtime.sessionGeneration,
		dedupeKey = dedupeKey,
		cooldownBefore = cooldownBefore,
		chargesBefore = chargesBefore,
		secondsBefore = secondsBefore,
		castStartBefore = castStartBefore,
		hiddenBefore = hiddenBefore,
		channelled = channelled,
		channelTime = channelTime,
		started = false,
		wasChanneling = false,
		refreshCooldownsBefore = refreshCooldownsBefore,
		refreshable = ControlAlly.Profiles.RefreshableTinkerActions[action.id] == true,
		isRearm = action.isRearm == true,
		internal = action.internal == true,
		invokerStage = action.invokerStage,
		invokerSpellId = action.invokerSpellId,
		invokerCountTracking = action.invokerCountTracking,
		orbSignatureBefore = action.orbSignatureBefore,
		source = action.source,
		isRefresher = action.isRefresher == true,
		isMeepoNet = action.isMeepoNet == true,
		meepoTargetIndex = action.meepoTargetIndex,
		meepoImpactAt = action.meepoImpactAt,
		meepoRootDuration = action.meepoRootDuration,
		invokerComboSpell = action.invokerComboSpell,
		invokerComboSetup = action.invokerComboSetup == true,
		castTarget = action.reservationTarget or action.target,
		castPosition = action.position,
		supportFamily = action.supportFamily,
		positionReservationFamily = action.positionReservationFamily,
		disable = action.disable == true,
		breaksLinkens = action.breaksLinkens == true,
		attackModifier = action.attackModifier == true,
		treadsBefore = action.treadsBefore,
		impactPosition = action.impactPosition,
		groupPoof = action.groupPoof == true,
		alchemistStage = action.alchemistStage,
		toggleBefore = toggleBefore,
		altBefore = altBefore,
		desiredToggle = action.desiredToggle,
		desiredAlt = action.desiredAlt,
		specialStage = action.specialStage,
		specialTravelTime = action.specialTravelTime,
		earthFollowup = action.earthFollowup,
		techiesMine = action.techiesMine == true,
		techiesMineIndex = action.techiesMineIndex,
		techiesMineTargetIndex = action.techiesMineTargetIndex,
		committedMotion = action.committedMotion == true or (action.rule and action.rule.committedMotion == true),
	}
	if action.committedMotion or (action.rule and action.rule.committedMotion) then
		local motionRule = action.rule or {}
		local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, controller.unit)
		local destination = action.vectorEnd
			or action.position
			or (action.target and ControlAlly.Utils.call(Entity.GetAbsOrigin, action.target))
		local distance = ControlAlly.Utils.distance2D(origin, destination)
		local speed = ControlAlly.Utils.ruleValue(
			action.ability,
			motionRule,
			"motionSpeed",
			"projectileSpeedSpecial",
			0
		) or 0
		if speed <= 0 then
			speed = ControlAlly.Utils.specialValue(action.ability, {
				"speed",
				"movement_speed",
				"charge_speed",
				"ball_lightning_move_speed",
				"projectile_speed",
			}, 0)
		end
		if speed <= 0 then
			speed = ControlAlly.Utils.call(NPC.GetMoveSpeed, controller.unit) or 0
		end
		local duration = ControlAlly.Utils.ruleValue(action.ability, motionRule, "motionDuration", "durationSpecial", 0)
			or 0
		if duration <= 0 then
			duration = ControlAlly.Utils.specialValue(action.ability, {
				"total_duration",
				"movement_duration",
				"charge_duration",
				"duration",
			}, 0)
		end
		local travelTime = destination and speed > 0 and distance < math.huge and distance / speed or 0
		local extraDuration = ControlAlly.Utils.ruleValue(
			action.ability,
			motionRule,
			"motionExtraDuration",
			"motionExtraDurationSpecial",
			0
		) or 0
		local motionTime = (duration > 0 and duration or travelTime) + math.max(0, extraDuration)
		motionTime = math.min(motionTime, ControlAlly.Constants.MOTION_LOCK_MAX)
		controller.motionLockUntil = now + math.max(motionTime, castPoint + 0.20)
		controller.motionLockStartedAt = now
		controller.motionModifiers = motionRule.motionModifiers
		controller.motionTarget = action.reservationTarget or action.target
	end
	if action.internal or action.fastCombo then
		ControlAlly.Runtime.invokerFastUntil = now + math.max(0.35, castPoint + 0.35)
		controller.nextThinkAt =
			math.min(controller.nextThinkAt or math.huge, now + ControlAlly.Constants.INVOKER_INTERNAL_ORDER_GAP)
	end
	local reservationTarget = action.reservationTarget or action.target
	if action.disable and reservationTarget then
		local targetIndex = ControlAlly.Utils.entityIndex(reservationTarget)
		if targetIndex then
			ControlAlly.Runtime.disableReservations[targetIndex] = now + (action.reservationDuration or 0.40)
		end
	end
	if action.breaksLinkens and reservationTarget then
		local targetIndex = ControlAlly.Utils.entityIndex(reservationTarget)
		if targetIndex then
			ControlAlly.Runtime.linkensReservations[targetIndex] = now + 0.45
		end
	end
	if action.effectReservationKey then
		ControlAlly.Runtime.effectReservations[action.effectReservationKey] = now
			+ math.max(action.reservationDuration or 0, castPoint + 0.30, 0.45)
	end
	if action.supportFamily then
		ControlAlly.SupportAI.reserve(action, now)
	end
	if action.isMeepoNet and action.meepoTargetIndex then
		ControlAlly.Runtime.meepoNetChains[action.meepoTargetIndex] = {
			target = action.reservationTarget,
			casterIndex = ControlAlly.Utils.entityIndex(controller.unit),
			impactAt = action.meepoImpactAt,
			inFlightUntil = (action.meepoImpactAt or now) + ControlAlly.Constants.MEEPO_NET_HIT_GRACE,
		}
	end
	if action.groupPoof then
		local poofTime = ControlAlly.Utils.call(Ability.GetCastPoint, action.ability) or 0
		for _, other in ipairs(ControlAlly.Runtime.controllers) do
			if other.playerId == controller.playerId and other.heroName == "npc_dota_hero_meepo" then
				other.busyUntil = math.max(other.busyUntil, now + poofTime + 0.20)
			end
		end
	end
	if action.positionReservationFamily and action.position then
		local reservations = ControlAlly.Runtime.positionReservations[action.positionReservationFamily] or {}
		reservations[#reservations + 1] = {
			position = action.position,
			expiresAt = now + math.max(0.5, action.positionReservationDuration or 0.5),
		}
		ControlAlly.Runtime.positionReservations[action.positionReservationFamily] = reservations
	end
	ControlAlly.Utils.debug(
		"%s%s cast %s",
		ControlAlly.Utils.heroDisplayName(controller.heroName),
		controller.isClone and " clone" or "",
		action.id
	)
	return true
end

function ControlAlly.Orders.attack(controller, target, now, forceInterleave)
	if not target or not ControlAlly.Utils.canAttack(controller.unit, target) then
		return false
	end
	local targetIndex = ControlAlly.Utils.entityIndex(target)
	local attackPoint = ControlAlly.Utils.call(NPC.GetAttackAnimPoint, controller.unit) or 0.25
	local unitPosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, controller.unit)
	local targetPosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, target)
	local distance = ControlAlly.Utils.distance2D(unitPosition, targetPosition)
	local attackRange = ControlAlly.Utils.call(NPC.GetAttackRange, controller.unit) or 150
	local moveSpeed = math.max(ControlAlly.Utils.call(NPC.GetMoveSpeed, controller.unit) or 300, 1)
	local approachTime = math.max(0, distance - attackRange - 40) / moveSpeed
	local inAttackRange = distance <= attackRange + 85
	if forceInterleave and controller.interleaveTarget ~= target then
		controller.interleaveTarget = target
		controller.interleaveDeadline = now + ControlAlly.Utils.clamp(approachTime + attackPoint + 0.75, 0.80, 3.50)
	end
	if
		controller.lastAttackTarget == targetIndex
		and ControlAlly.Utils.call(NPC.IsAttacking, controller.unit) == true
		and inAttackRange
	then
		if forceInterleave then
			controller.busyUntil =
				math.max(controller.busyUntil, now + ControlAlly.Utils.clamp(attackPoint + 0.10, 0.20, 0.78))
			controller.interleaveTarget = nil
			controller.interleaveDeadline = -math.huge
		end
		controller.castsSinceAttack = 0
		return true
	end
	if now - controller.lastAttackAt < ControlAlly.Constants.ATTACK_RESEND_INTERVAL then
		return forceInterleave and controller.interleaveTarget ~= nil
	end
	if
		not ControlAlly.Orders.issue(
			controller,
			Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET,
			target,
			nil,
			nil,
			forceInterleave and "attack_interleave" or "attack",
			false
		)
	then
		return forceInterleave and controller.interleaveTarget ~= nil
	end
	controller.lastAttackAt = now
	controller.lastAttackTarget = targetIndex
	if forceInterleave then
		controller.busyUntil = now + ControlAlly.Utils.clamp(approachTime + attackPoint + 0.10, 0.20, 1.60)
	else
		controller.castsSinceAttack = 0
	end
	return true
end

function ControlAlly.Orders.move(controller, position, now)
	if not position or now - controller.lastMoveAt < ControlAlly.Constants.MOVE_RESEND_INTERVAL then
		return false
	end
	local states = Enum.ModifierState
	if states and ControlAlly.Utils.hasState(controller.unit, states.MODIFIER_STATE_ROOTED) then
		return false
	end
	if controller.lastMovePosition and ControlAlly.Utils.distance2D(controller.lastMovePosition, position) < 80 then
		local current = ControlAlly.Utils.call(Entity.GetAbsOrigin, controller.unit)
		if
			ControlAlly.Utils.call(NPC.IsRunning, controller.unit) == true
			or ControlAlly.Utils.distance2D(current, position) < 100
		then
			return false
		end
	end
	if
		not ControlAlly.Orders.issue(
			controller,
			Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION,
			nil,
			position,
			nil,
			"follow_cursor",
			false
		)
	then
		return false
	end
	controller.lastMoveAt = now
	controller.lastMovePosition = position
	return true
end

function ControlAlly.Orders.face(controller, direction, now)
	if not direction or now - (controller.lastFaceAt or -math.huge) < ControlAlly.Constants.FACE_RESEND_INTERVAL then
		return false
	end
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, controller.unit)
	if not origin then
		return false
	end
	local point = Vector(origin.x + direction.x * 100, origin.y + direction.y * 100, origin.z or 0)
	if
		not ControlAlly.Orders.issue(
			controller,
			Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_DIRECTION,
			nil,
			point,
			nil,
			"face_ability",
			true
		)
	then
		return false
	end
	controller.lastFaceAt = now
	return true
end

function ControlAlly.AbilityAI.collectAbilities(unit)
	local abilities = {}
	local seen = {}
	for slot = 0, 23 do
		local ability = ControlAlly.Utils.call(NPC.GetAbilityByIndex, unit, slot)
		local id = ability and ControlAlly.Utils.abilityName(ability)
		if id and id:sub(1, 5) ~= "item_" and not seen[id] then
			seen[id] = true
			abilities[#abilities + 1] = { ability = ability, id = id, slot = slot }
		end
	end
	return abilities
end

function ControlAlly.AbilityAI.collectItems(unit)
	local items = {}
	local seen = {}
	for _, slot in ipairs({ 0, 1, 2, 3, 4, 5, 16 }) do
		local item = ControlAlly.Utils.call(NPC.GetItemByIndex, unit, slot)
		local id = item and ControlAlly.Utils.abilityName(item)
		if id and id:sub(1, 5) == "item_" and not seen[id] then
			seen[id] = true
			items[#items + 1] = { ability = item, id = id, slot = slot }
		end
	end
	return items
end

function ControlAlly.AbilityAI.collectMenuIds(unit, abilityIds, itemIds, profileName)
	local heroName = profileName or ControlAlly.Utils.unitName(unit)
	for _, entry in ipairs(ControlAlly.AbilityAI.collectAbilities(unit)) do
		local ability = entry.ability
		local id = entry.id
		local explicitRule = ControlAlly.Profiles.getAbilityRule(heroName, id)
		local rule = explicitRule or ControlAlly.AbilityAI.genericRule(ability, id)
		local hidden = ControlAlly.Utils.call(Ability.IsHidden, ability) == true
		local passive = ControlAlly.Utils.call(Ability.IsPassive, ability) == true
		local attributes = ControlAlly.Utils.call(Ability.IsAttributes, ability) == true
		if
			(not ControlAlly.Profiles.HiddenAbilities[id] or explicitRule ~= nil)
			and rule ~= nil
			and rule.policy ~= "disabled"
			and not passive
			and not attributes
			and not id:find("special_bonus", 1, true)
			and (not hidden or (explicitRule and rule.menuVisible == true))
		then
			abilityIds[ControlAlly.Profiles.normalizedAbilityId(id)] = true
		end
	end
	if heroName == "npc_dota_hero_invoker" then
		for id in pairs(ControlAlly.Profiles.InvokerSpells) do
			abilityIds[id] = true
		end
	end
	for _, entry in ipairs(ControlAlly.AbilityAI.collectItems(unit)) do
		if
			ControlAlly.Profiles.getItemRule(entry.id)
			and ControlAlly.Utils.call(Ability.IsHidden, entry.ability) ~= true
		then
			itemIds[entry.id] = true
		end
	end
end

function ControlAlly.AbilityAI.catalog(controller, now)
	if controller.catalog and now < controller.catalogRefreshAt then
		return controller.catalog
	end
	local abilities = ControlAlly.AbilityAI.collectAbilities(controller.unit)
	local items = ControlAlly.AbilityAI.collectItems(controller.unit)
	local abilitiesById = {}
	for _, entry in ipairs(abilities) do
		abilitiesById[entry.id] = entry.ability
	end
	controller.catalog = {
		abilities = abilities,
		items = items,
		abilitiesById = abilitiesById,
	}
	for _, entry in ipairs(abilities) do
		entry.rule = ControlAlly.Profiles.getAbilityRule(controller.profileName or controller.heroName, entry.id)
			or ControlAlly.AbilityAI.genericRule(entry.ability, entry.id)
	end
	controller.catalogRefreshAt = now + 0.45
	return controller.catalog
end

function ControlAlly.AbilityAI.findAbility(controller, abilityId, now)
	local catalog = ControlAlly.AbilityAI.catalog(controller, now)
	return catalog.abilitiesById[abilityId] or ControlAlly.Utils.call(NPC.GetAbility, controller.unit, abilityId)
end

function ControlAlly.AbilityAI.isReady(controller, ability, id, allowHidden, isItem, ignoreManaFloor, allowUnlearned)
	if not ability then
		return false
	end
	if not isItem then
		local level = ControlAlly.Utils.call(Ability.GetLevel, ability) or 0
		if (level <= 0 and not allowUnlearned) or ControlAlly.Utils.call(Ability.IsAttributes, ability) == true then
			return false
		end
		if
			not ignoreManaFloor
			and ControlAlly.UI.MinMana
			and ControlAlly.Utils.manaPct(controller.unit) < ControlAlly.UI.MinMana:Get()
		then
			return false
		end
		if ControlAlly.Utils.call(NPC.IsSilenced, controller.unit) == true then
			local behavior = ControlAlly.Utils.call(Ability.GetBehavior, ability) or 0
			local ignoreSilence = Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_IGNORE_SILENCE
			if not ControlAlly.Utils.hasFlag(behavior, ignoreSilence) then
				return false
			end
		end
	elseif Item and Item.IsItemEnabled and ControlAlly.Utils.call(Item.IsItemEnabled, ability) == false then
		return false
	end
	if isItem and Enum.ModifierState then
		local muted = Enum.ModifierState.MODIFIER_STATE_MUTED
		if muted and ControlAlly.Utils.hasState(controller.unit, muted) then
			local behavior = ControlAlly.Utils.call(Ability.GetBehavior, ability) or 0
			local ignoreMuted = Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_IGNORE_MUTED
			if not ControlAlly.Utils.hasFlag(behavior, ignoreMuted) then
				return false
			end
		end
	end
	if not allowHidden and ControlAlly.Utils.call(Ability.IsHidden, ability) == true then
		return false
	end
	if ControlAlly.Utils.call(Ability.IsPassive, ability) == true then
		return false
	end
	local activated = ControlAlly.Utils.call(Ability.IsActivated, ability)
	if activated == false then
		return false
	end
	if ControlAlly.Utils.cooldownRemaining(ability) > 0.03 then
		return false
	end
	local isReady = ControlAlly.Utils.call(Ability.IsReady, ability)
	if isReady == false then
		return false
	end
	local castResult = ControlAlly.Utils.call(Ability.CanBeExecuted, ability)
	local readyResult = Enum.AbilityCastResult and Enum.AbilityCastResult.READY or -1
	if castResult ~= nil and castResult ~= readyResult and castResult ~= -1 then
		return false
	end
	local mana = ControlAlly.Utils.call(NPC.GetMana, controller.unit) or 0
	return ControlAlly.Utils.call(Ability.IsCastable, ability, mana) == true
end

function ControlAlly.AbilityAI.isCombatName(id)
	local patterns = {
		"stun",
		"strike",
		"blast",
		"bolt",
		"nuke",
		"impale",
		"fissure",
		"ravage",
		"roar",
		"hex",
		"shackle",
		"silence",
		"root",
		"nova",
		"wave",
		"meteor",
		"spear",
		"hook",
		"arena",
		"chronosphere",
		"black_hole",
		"burrowstrike",
		"dismember",
		"duel",
		"finger",
		"laguna",
	}
	for _, pattern in ipairs(patterns) do
		if id:find(pattern, 1, true) then
			return true
		end
	end
	return false
end

function ControlAlly.AbilityAI.isDisable(id, rule)
	if rule and rule.disable ~= nil then
		return rule.disable == true
	end
	local patterns = {
		"stun",
		"hex",
		"shackle",
		"impale",
		"fissure",
		"ravage",
		"roar",
		"chronosphere",
		"black_hole",
		"burrowstrike",
		"dismember",
		"duel",
		"cold_snap",
		"tornado",
		"deafening_blast",
		"hookshot",
	}
	for _, pattern in ipairs(patterns) do
		if id:find(pattern, 1, true) then
			return true
		end
	end
	return false
end

function ControlAlly.AbilityAI.genericRule(ability, id)
	local behavior = ControlAlly.Utils.call(Ability.GetBehavior, ability) or 0
	local flags = Enum.AbilityBehavior
	if
		ControlAlly.Utils.hasFlag(behavior, flags.DOTA_ABILITY_BEHAVIOR_PASSIVE)
		or ControlAlly.Utils.hasFlag(behavior, flags.DOTA_ABILITY_BEHAVIOR_TOGGLE)
		or ControlAlly.Utils.hasFlag(behavior, flags.DOTA_ABILITY_BEHAVIOR_VECTOR_TARGETING)
		or ControlAlly.Utils.hasFlag(behavior, flags.DOTA_ABILITY_BEHAVIOR_FREE_DRAW_TARGETING)
		or ControlAlly.Utils.hasFlag(behavior, flags.DOTA_ABILITY_BEHAVIOR_ROOT_DISABLES)
	then
		return nil
	end

	local targetTeam = ControlAlly.Utils.call(Ability.GetTargetTeam, ability) or 0
	local targetTeams = Enum.TargetTeam
	local targetType = ControlAlly.Utils.call(Ability.GetTargetType, ability) or 0
	local damage = ControlAlly.Utils.call(Ability.GetDamage, ability) or 0
	if damage <= 0 then
		damage = ControlAlly.Utils.specialValue(ability, {
			"damage",
			"base_damage",
			"main_damage",
			"poof_damage",
			"quill_base_damage",
			"damage_per_second",
			"damage_percent",
			"drop_damage",
			"fling_damage",
			"max_damage",
		}, 0)
	end
	local isUltimate = ControlAlly.Utils.call(Ability.IsUltimate, ability) == true
	local combatLike = damage > 0 or ControlAlly.AbilityAI.isCombatName(id)
	if ControlAlly.Utils.hasFlag(behavior, flags.DOTA_ABILITY_BEHAVIOR_UNIT_TARGET) then
		if
			(
				ControlAlly.Utils.hasFlag(targetTeam, targetTeams.DOTA_UNIT_TARGET_TEAM_ENEMY)
				or targetTeam == targetTeams.DOTA_UNIT_TARGET_TEAM_BOTH
			)
			and ControlAlly.Utils.hasFlag(targetType, Enum.TargetType.DOTA_UNIT_TARGET_HERO)
			and combatLike
		then
			return {
				policy = "enemy",
				priority = isUltimate and 104
					or (ControlAlly.Utils.hasFlag(behavior, flags.DOTA_ABILITY_BEHAVIOR_ATTACK) and 70 or 64),
				attackModifier = ControlAlly.Utils.hasFlag(behavior, flags.DOTA_ABILITY_BEHAVIOR_ATTACK),
				estimatedDamage = damage,
			}
		end
		return nil
	end
	if isUltimate then
		return nil
	end
	if ControlAlly.Utils.hasFlag(behavior, flags.DOTA_ABILITY_BEHAVIOR_POINT) and combatLike then
		return { policy = "point", priority = 62, estimatedDamage = damage }
	end
	if ControlAlly.Utils.hasFlag(behavior, flags.DOTA_ABILITY_BEHAVIOR_NO_TARGET) and combatLike then
		return { policy = "noTarget", priority = 58, estimatedDamage = damage }
	end
	return nil
end

function ControlAlly.AbilityAI.castRange(unit, ability, rule)
	if rule.global then
		return math.huge
	end
	local range = ControlAlly.Utils.ruleValue(ability, rule, "castRange", "castRangeSpecial", nil)
		or ControlAlly.Utils.call(Ability.GetCastRange, ability)
		or 0
	if range <= 0 then
		range = ControlAlly.Utils.specialValue(
			ability,
			{ "cast_range", "range", "distance", "max_distance", "travel_distance" },
			0
		)
	end
	if range <= 0 then
		range = ControlAlly.Constants.DEFAULT_CAST_RANGE
	end
	return range + (rule.ignoreCastRangeBonus and 0 or (ControlAlly.Utils.call(NPC.GetCastRangeBonus, unit) or 0))
end

function ControlAlly.AbilityAI.radius(ability, rule)
	local configured = ControlAlly.Utils.ruleValue(ability, rule, "radius", "radiusSpecial", nil)
	if configured and configured > 0 then
		return configured
	end
	return ControlAlly.Utils.specialValue(ability, {
		"radius",
		"aoe",
		"area_of_effect",
		"effect_radius",
		"damage_radius",
		"impact_radius",
		"search_radius",
		"launch_radius",
		"drop_aoe_radius",
		"barrier_radius",
		"explosion_radius",
		"width",
	}, ControlAlly.Constants.DEFAULT_POINT_RADIUS)
end

function ControlAlly.AbilityAI.targetIsIsolated(context, ability, rule)
	local targetPosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.target)
	local team = ControlAlly.Utils.call(Entity.GetTeamNum, context.target)
	if not targetPosition or team == nil then
		return false
	end
	local units = ControlAlly.Utils.call(
		NPCs.InRadius,
		targetPosition,
		ControlAlly.Utils.ruleValue(ability, rule, "isolationRadius", "isolationRadiusSpecial", 300),
		team,
		Enum.TeamType.TEAM_FRIEND,
		false,
		true
	) or {}
	for _, unit in ipairs(units) do
		if
			unit ~= context.target
			and ControlAlly.Utils.call(Entity.IsAlive, unit) == true
			and (ControlAlly.Utils.call(NPC.IsHero, unit) == true or ControlAlly.Utils.call(NPC.IsCreep, unit) == true)
		then
			return false
		end
	end
	return true
end

function ControlAlly.AbilityAI.rulePasses(context, ability, rule)
	local unit = context.unit
	local target = context.target
	local distance = target
			and ControlAlly.Utils.distance2D(
				ControlAlly.Utils.call(Entity.GetAbsOrigin, unit),
				ControlAlly.Utils.call(Entity.GetAbsOrigin, target)
			)
		or math.huge
	if rule.requiresTarget and not target then
		return false
	end
	if rule.mainOnly and context.controller.isClone then
		return false
	end
	if rule.requiresNoClone and (ControlAlly.Runtime.cloneCountByPlayer[context.controller.playerId] or 0) > 0 then
		return false
	end
	if
		ControlAlly.Utils.hasAnyModifier(unit, rule.selfModifiers)
		or (not rule.allowStacking and ControlAlly.Utils.hasAnyModifier(target, rule.targetModifiers))
	then
		return false
	end
	if rule.defensiveHealthPct and ControlAlly.Utils.healthPct(unit) > rule.defensiveHealthPct then
		return false
	end
	if rule.minimumHealthPct and ControlAlly.Utils.healthPct(unit) < rule.minimumHealthPct then
		return false
	end
	if rule.attackModifier then
		local healthCostPct = ControlAlly.Utils.specialValue(ability, { "max_health_cost", "health_cost_pct" }, 0)
		if healthCostPct > 0 and ControlAlly.Utils.healthPct(unit) <= healthCostPct + 28 then
			return false
		end
	end
	if rule.requiresRecentDamage and not ControlAlly.Utils.wasRecentlyHurt(unit, context.now) then
		return false
	end
	if
		rule.requiresCombatPressure
		and distance > 550
		and not ControlAlly.Utils.wasRecentlyHurt(unit, context.now)
		and ControlAlly.Utils.call(NPC.IsAttacking, unit) ~= true
	then
		return false
	end
	if rule.requiresFacing and target then
		local targetPosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, target)
		local faceTime = targetPosition and ControlAlly.Utils.call(NPC.GetTimeToFacePosition, unit, targetPosition)
		if type(faceTime) == "number" and faceTime > 0.10 then
			return false
		end
	end
	if rule.requiresBadState and not ControlAlly.Utils.hasBadState(unit) then
		return false
	end
	if
		rule.requiresImmobile
		and target
		and ControlAlly.Targeting.hardDisableRemaining(target) <= 0
		and not (Enum.ModifierState and ControlAlly.Utils.hasState(target, Enum.ModifierState.MODIFIER_STATE_ROOTED))
	then
		return false
	end
	local enemyRadius = ControlAlly.Utils.ruleValue(ability, rule, "enemyRadius", "enemyRadiusSpecial", nil)
	local maxDistance = ControlAlly.Utils.ruleValue(ability, rule, "maxDistance", "maxDistanceSpecial", nil)
	if enemyRadius and distance > enemyRadius then
		return false
	end
	if maxDistance and distance > maxDistance then
		return false
	end
	if rule.minDistance and distance < rule.minDistance then
		return false
	end
	if rule.combatBuff and distance > 1100 then
		return false
	end
	if rule.targetManaMinPct and ControlAlly.Utils.manaPct(target) < rule.targetManaMinPct then
		return false
	end
	if rule.requiresIsolated and not ControlAlly.AbilityAI.targetIsIsolated(context, ability, rule) then
		return false
	end
	return true
end

function ControlAlly.AbilityAI.gapclosePosition(context, ability, rule)
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
	local targetPosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.target)
	if not origin or not targetPosition then
		return nil
	end
	local range = ControlAlly.AbilityAI.castRange(context.unit, ability, rule)
	local distance = ControlAlly.Utils.distance2D(origin, targetPosition)
	if distance > range + 80 or distance < (rule.minDistance or 450) then
		return nil
	end
	local landingDistance = math.max(0, distance - 135)
	return ControlAlly.Utils.positionToward(origin, targetPosition, math.min(range, landingDistance))
end

function ControlAlly.AbilityAI.unitTargetIsSafe(target, allowLinkensBreaker)
	if not target then
		return false
	end
	local states = Enum.ModifierState
	if states then
		for _, stateName in ipairs({
			"MODIFIER_STATE_INVULNERABLE",
			"MODIFIER_STATE_OUT_OF_GAME",
			"MODIFIER_STATE_UNTARGETABLE",
			"MODIFIER_STATE_UNTARGETABLE_ENEMY",
		}) do
			local state = states[stateName]
			if state and ControlAlly.Utils.hasState(target, state) then
				return false
			end
		end
	end
	if NPC.IsMirrorProtected and ControlAlly.Utils.call(NPC.IsMirrorProtected, target) == true then
		return false
	end
	local linkensProtected = ControlAlly.Utils.call(NPC.IsLinkensProtected, target) == true
	if Humanizer and Humanizer.IsSafeTarget then
		local safe = ControlAlly.Utils.call(Humanizer.IsSafeTarget, target)
		if safe == false and not (allowLinkensBreaker and linkensProtected) then
			return false
		end
	end
	return true
end

function ControlAlly.AbilityAI.bestAllyTarget(context, ability, rule)
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
	local enemyPosition = context.target and ControlAlly.Utils.call(Entity.GetAbsOrigin, context.target)
	local range = ControlAlly.AbilityAI.castRange(context.unit, ability, rule)
	local best
	local bestScore = -math.huge
	for _, ally in ipairs(ControlAlly.Runtime.allies) do
		local position = ControlAlly.Utils.call(Entity.GetAbsOrigin, ally)
		if origin and position and ControlAlly.Utils.distance2D(origin, position) <= range + 35 then
			local healthPct = ControlAlly.Utils.healthPct(ally)
			local hurt = ControlAlly.Utils.wasRecentlyHurt(ally, context.now)
			local modifierBlocked = ControlAlly.Utils.hasAnyModifier(ally, rule.allyModifiers or rule.targetModifiers)
			local nearEnemy = enemyPosition
				and ControlAlly.Utils.distance2D(position, enemyPosition)
					<= (ControlAlly.Utils.call(NPC.GetAttackRange, ally) or 150) + 450
			local attacking = ControlAlly.Utils.call(NPC.IsAttacking, ally) == true and nearEnemy
			local threshold = rule.allyHealthPct or 72
			local eligible = false
			if rule.allyMode == "save" then
				eligible = healthPct <= threshold and (hurt or healthPct <= threshold * 0.65)
			elseif rule.allyMode == "heal" then
				eligible = healthPct <= threshold or nearEnemy == true
			elseif rule.allyMode == "buff" then
				eligible = attacking or (ally == context.unit and nearEnemy == true)
			else
				eligible = ally == context.unit or attacking or healthPct <= threshold
			end
			if eligible and not modifierBlocked then
				local score = (100 - healthPct) * (rule.allyMode == "save" and 1.5 or 0.45)
					+ (hurt and 18 or 0)
					+ (attacking and 14 or 0)
				if score > bestScore then
					best = ally
					bestScore = score
				end
			end
		end
	end
	return best, bestScore
end

function ControlAlly.AbilityAI.toggleDesired(context, ability, rule, radius)
	if rule.toggleMode == "heal" then
		local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
		for _, ally in ipairs(ControlAlly.Runtime.allies) do
			if
				ControlAlly.Utils.healthPct(ally) <= (rule.allyHealthPct or 78)
				and ControlAlly.Utils.distance2D(origin, ControlAlly.Utils.call(Entity.GetAbsOrigin, ally))
					<= radius
			then
				return true
			end
		end
		return false
	end
	if rule.minimumHealthPct and ControlAlly.Utils.healthPct(context.unit) < rule.minimumHealthPct then
		return false
	end
	return context.target ~= nil
		and ControlAlly.Utils.distance2D(
				ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit),
				ControlAlly.Utils.call(Entity.GetAbsOrigin, context.target)
			)
			<= radius
end

function ControlAlly.AbilityAI.wouldBeUsableIfReady(context, ability, rule)
	if not rule or not ControlAlly.AbilityAI.rulePasses(context, ability, rule) then
		return false
	end
	local policy = rule.policy
	if
		policy == "self"
		or policy == "selfPosition"
		or policy == "ally"
		or policy == "allyPoint"
		or policy == "toggle"
	then
		return true
	end
	if policy == "noTarget" and rule.alwaysNoTarget then
		return true
	end
	if not context.target then
		return false
	end
	if
		ControlAlly.Utils.isMagicImmune(context.target)
		and not rule.allowMagicImmune
		and (policy == "enemy" or policy == "point")
	then
		return false
	end
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
	local targetPosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.target)
	local distance = ControlAlly.Utils.distance2D(origin, targetPosition)
	local range = ControlAlly.AbilityAI.castRange(context.unit, ability, rule)
	if policy == "enemy" then
		return distance <= range + ControlAlly.Constants.CAST_RANGE_BUFFER
			and ControlAlly.Utils.call(NPC.IsLinkensProtected, context.target) ~= true
			and ControlAlly.AbilityAI.unitTargetIsSafe(context.target, false)
	end
	if policy == "point" then
		if rule.lineProjectile then
			local travelDistance = ControlAlly.Utils.ruleValue(
				ability,
				rule,
				"travelDistance",
				"travelDistanceSpecial",
				range
			) or range
			return distance <= travelDistance + ControlAlly.AbilityAI.radius(ability, rule)
		end
		return distance <= range + ControlAlly.AbilityAI.radius(ability, rule)
	end
	if policy == "noTarget" then
		local radius = rule.radius
			or math.max(ControlAlly.AbilityAI.radius(ability, rule), ControlAlly.Constants.DEFAULT_NO_TARGET_RADIUS)
		return distance <= radius
	end
	if policy == "gapclose" then
		return ControlAlly.AbilityAI.gapclosePosition(context, ability, rule) ~= nil
	end
	return false
end

function ControlAlly.AbilityAI.buildAction(context, ability, id, rule, source)
	if not rule or rule.policy == "disabled" or rule.policy == "special" then
		return nil
	end
	local isItem = source == "item"
	if
		not ControlAlly.AbilityAI.isReady(context.controller, ability, id, rule.allowHidden == true, isItem)
		or not ControlAlly.AbilityAI.rulePasses(context, ability, rule)
	then
		return nil
	end
	if
		rule.policy ~= "self"
		and rule.policy ~= "selfPosition"
		and rule.policy ~= "noTarget"
		and rule.policy ~= "ally"
		and rule.policy ~= "allyPoint"
		and rule.policy ~= "toggle"
		and not context.target
	then
		return nil
	end
	if
		context.target
		and ControlAlly.Utils.isMagicImmune(context.target)
		and not rule.allowMagicImmune
		and (rule.policy == "enemy" or rule.policy == "point")
	then
		return nil
	end
	if
		rule.policy == "enemy"
		and not (
			rule.attackModifier and ControlAlly.Utils.canAttack(context.unit, context.target)
			or (
				not rule.attackModifier
				and ControlAlly.AbilityAI.unitTargetIsSafe(
					context.target,
					source == "item" and rule.linkPriority ~= nil
				)
			)
		)
	then
		return nil
	end
	local effectReservationKey
	if context.target and rule.targetModifiers and not rule.allowStacking then
		local targetIndex = ControlAlly.Utils.entityIndex(context.target)
		if targetIndex then
			effectReservationKey = tostring(targetIndex) .. ":" .. id
			if (ControlAlly.Runtime.effectReservations[effectReservationKey] or -math.huge) > context.now then
				return nil
			end
		end
	end

	local action = {
		ability = ability,
		id = id,
		policy = rule.policy,
		rule = rule,
		source = source,
		disable = ControlAlly.AbilityAI.isDisable(id, rule),
		urgent = rule.urgent == true,
		attackModifier = rule.attackModifier == true,
		reservationTarget = context.target,
		effectReservationKey = effectReservationKey,
		specialStage = rule.specialStage,
	}
	local range = ControlAlly.AbilityAI.castRange(context.unit, ability, rule)
	local radius = ControlAlly.AbilityAI.radius(ability, rule)
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
	local targetPosition = context.target and ControlAlly.Utils.call(Entity.GetAbsOrigin, context.target)
	local distance = ControlAlly.Utils.distance2D(origin, targetPosition)
	local aoeHits = 1

	if rule.policy == "enemy" then
		if distance > range + ControlAlly.Constants.CAST_RANGE_BUFFER then
			return nil
		end
		action.target = context.target
	elseif rule.policy == "self" then
		action.target = context.unit
	elseif rule.policy == "ally" then
		local ally, allyScore = ControlAlly.AbilityAI.bestAllyTarget(context, ability, rule)
		if not ally then
			return nil
		end
		action.target = ally
		action.reservationTarget = ally
		action.scoreBonus = allyScore
	elseif rule.policy == "allyPoint" then
		local ally, allyScore = ControlAlly.AbilityAI.bestAllyTarget(context, ability, rule)
		if not ally then
			return nil
		end
		action.position = ControlAlly.Utils.call(Entity.GetAbsOrigin, ally)
		action.reservationTarget = ally
		action.scoreBonus = allyScore
	elseif rule.policy == "selfPosition" then
		action.position = origin
	elseif rule.policy == "gapclose" then
		action.position = ControlAlly.AbilityAI.gapclosePosition(context, ability, rule)
		if not action.position then
			return nil
		end
	elseif rule.policy == "point" then
		if rule.lineProjectile then
			local predicted = ControlAlly.Targeting.predictPosition(context.target, ability, rule)
			local predictedDistance = ControlAlly.Utils.distance2D(origin, predicted)
			local travelDistance = ControlAlly.Utils.ruleValue(
				ability,
				rule,
				"travelDistance",
				"travelDistanceSpecial",
				range
			) or range
			if predictedDistance > travelDistance + radius then
				return nil
			end
			action.position = predictedDistance > range and ControlAlly.Utils.positionToward(origin, predicted, range)
				or predicted
			action.impactPosition = predicted
		else
			action.position, aoeHits = ControlAlly.Targeting.bestAoePosition(context, ability, rule, radius, range)
		end
		if not action.position then
			return nil
		end
	elseif rule.policy == "noTarget" then
		local noTargetRadius = math.max(radius, ControlAlly.Constants.DEFAULT_NO_TARGET_RADIUS)
		if not rule.alwaysNoTarget and distance > noTargetRadius then
			return nil
		end
	elseif rule.policy == "toggle" then
		local toggleRadius = math.max(radius, ControlAlly.Constants.DEFAULT_NO_TARGET_RADIUS)
		local desired = ControlAlly.AbilityAI.toggleDesired(context, ability, rule, toggleRadius)
		if not desired and context.controller.ownedToggles[id] ~= true then
			return nil
		end
		if ControlAlly.Utils.call(Ability.GetToggleState, ability) == desired then
			return nil
		end
		action.desiredToggle = desired
		action.urgent = desired == false
	elseif rule.policy == "vector" or rule.policy == "vectorTarget" then
		local predicted = ControlAlly.Targeting.predictPosition(context.target, ability, rule)
		if not predicted then
			return nil
		end
		local direction = ControlAlly.Utils.normalized2D(origin, predicted)
		if not direction then
			return nil
		end
		if rule.policy == "vectorTarget" then
			action.policy = "vectorTarget"
			action.target = context.target
			action.position = origin
			action.vectorEnd = Vector(
				predicted.x + direction.x * math.max(radius, 180),
				predicted.y + direction.y * math.max(radius, 180),
				predicted.z or 0
			)
		else
			local start = ControlAlly.Utils.positionToward(origin, predicted, math.min(range, distance))
			if rule.vectorPerpendicular then
				local perpendicular = Vector(-direction.y, direction.x, 0)
				local half = math.min(range, math.max(radius * 2, 300)) * 0.5
				start =
					Vector(predicted.x - perpendicular.x * half, predicted.y - perpendicular.y * half, predicted.z or 0)
				action.vectorEnd =
					Vector(predicted.x + perpendicular.x * half, predicted.y + perpendicular.y * half, predicted.z or 0)
			else
				action.vectorEnd = predicted
			end
			action.position = start
		end
	else
		return nil
	end

	if rule.positionReservationFamily and action.position then
		local family = rule.positionReservationFamily
		local reservations = ControlAlly.Runtime.positionReservations[family] or {}
		local spacing = ControlAlly.Utils.specialValue(ability, { "min_distance" }, radius * 0.55)
		local active = {}
		for _, reservation in ipairs(reservations) do
			if reservation.expiresAt > context.now then
				active[#active + 1] = reservation
				if ControlAlly.Utils.distance2D(reservation.position, action.position) < spacing then
					ControlAlly.Runtime.positionReservations[family] = active
					return nil
				end
			end
		end
		ControlAlly.Runtime.positionReservations[family] = active
		action.positionReservationFamily = family
		action.positionReservationDuration = ControlAlly.Utils.ruleValue(
			ability,
			rule,
			"duration",
			"durationSpecial",
			ControlAlly.Utils.specialValue(ability, { "activation_delay" }, 1) + 1
		)
	end

	if action.disable and context.target then
		local targetIndex = ControlAlly.Utils.entityIndex(context.target)
		local reservedUntil = targetIndex and ControlAlly.Runtime.disableReservations[targetIndex] or -math.huge
		if
			not rule.allowDisabledTarget
			and (reservedUntil > context.now or ControlAlly.Targeting.hardDisableRemaining(context.target) > 0.32)
		then
			return nil
		end
	end
	if action.disable then
		local travelTime = 0
		local projectileSpeed = ControlAlly.Utils.ruleValue(
			ability,
			rule,
			"projectileSpeed",
			"projectileSpeedSpecial",
			0
		) or 0
		local impactDistance = ControlAlly.Utils.distance2D(origin, action.impactPosition or targetPosition)
		if projectileSpeed > 0 and impactDistance < math.huge then
			travelTime = impactDistance / projectileSpeed
		end
		local effectDelay = ControlAlly.Utils.ruleValue(ability, rule, "lead", "delaySpecial", 0) or 0
		local faceTime = action.position
				and ControlAlly.Utils.call(NPC.GetTimeToFacePosition, context.unit, action.position)
			or 0
		faceTime = type(faceTime) == "number" and math.max(0, faceTime) or 0
		action.reservationDuration = math.max(
			0.40,
			faceTime + (ControlAlly.Utils.call(Ability.GetCastPoint, ability) or 0) + effectDelay + travelTime + 0.15
		)
	end

	local score = (rule.priority or 60) + (action.scoreBonus or 0)
	local damage = rule.estimatedDamage or ControlAlly.Utils.call(Ability.GetDamage, ability) or 0
	if damage <= 0 then
		damage = ControlAlly.Utils.specialValue(ability, {
			"damage",
			"base_damage",
			"main_damage",
			"poof_damage",
			"quill_base_damage",
			"damage_per_second",
			"damage_percent",
			"drop_damage",
			"max_damage",
		}, 0)
	end
	score = score + math.min(math.max(damage, 0) / 25, 18)
	if action.disable then
		score = score + 18
	end
	if aoeHits > 1 then
		score = score + (aoeHits - 1) * 12
	end
	if context.target then
		score = score + (100 - ControlAlly.Utils.healthPct(context.target)) * 0.08
	end
	if
		rule.preferDisabledTarget
		and context.target
		and ControlAlly.Targeting.hardDisableRemaining(context.target) > 0.15
	then
		score = score + 24
	end
	if rule.preferLowHealth and context.target then
		score = score + (100 - ControlAlly.Utils.healthPct(context.target)) * 0.35
	end

	if
		rule.policy == "enemy"
		and not rule.attackModifier
		and context.target
		and ControlAlly.Utils.call(NPC.IsLinkensProtected, context.target) == true
	then
		local targetIndex = ControlAlly.Utils.entityIndex(context.target)
		if targetIndex and (ControlAlly.Runtime.linkensReservations[targetIndex] or -math.huge) > context.now then
			return nil
		end
		if source == "item" and rule.linkPriority then
			score = 200 + rule.linkPriority
			action.breaksLinkens = true
		else
			return nil
		end
	end
	action.score = score
	return action
end

function ControlAlly.AbilityAI.bestAbilityAction(context)
	if not ControlAlly.UI.UseAbilities or ControlAlly.UI.UseAbilities:Get() ~= true then
		return nil
	end
	local best
	local catalog = ControlAlly.AbilityAI.catalog(context.controller, context.now)
	for _, entry in ipairs(catalog.abilities) do
		local id = entry.id
		if
			ControlAlly.Menu.isAbilityEnabled(id)
			and not ControlAlly.Profiles.HiddenAbilities[id]
			and not (context.controller.heroName == "npc_dota_hero_invoker" and ControlAlly.Profiles.InvokerSpells[id])
		then
			local rule = entry.rule
			local action = ControlAlly.AbilityAI.buildAction(context, entry.ability, id, rule, "ability")
			if action and (not best or action.score > best.score) then
				best = action
			end
		end
	end
	return best
end

function ControlAlly.ItemAI.bestAction(context)
	if not ControlAlly.UI.UseItems or ControlAlly.UI.UseItems:Get() ~= true then
		return nil
	end
	local best
	local catalog = ControlAlly.AbilityAI.catalog(context.controller, context.now)
	for _, entry in ipairs(catalog.items) do
		local rule = ControlAlly.Profiles.getItemRule(entry.id)
		if rule and not ControlAlly.Profiles.SupportItems[entry.id] and ControlAlly.Menu.isItemEnabled(entry.id) then
			local action = ControlAlly.AbilityAI.buildAction(context, entry.ability, entry.id, rule, "item")
			if action and (not best or action.score > best.score) then
				best = action
			end
		end
	end
	return best
end

function ControlAlly.ItemAI.refresherAction(context, currentAction)
	if
		currentAction
		or not context.target
		or not ControlAlly.UI.UseItems
		or ControlAlly.UI.UseItems:Get() ~= true
		or (context.controller.heroName == "npc_dota_hero_tinker" and ControlAlly.Menu.isAbilityEnabled("tinker_rearm"))
	then
		return nil
	end
	local refresherEntry
	for _, entry in ipairs(ControlAlly.AbilityAI.catalog(context.controller, context.now).items) do
		if
			(entry.id == "item_refresher" or entry.id == "item_refresher_shard")
			and ControlAlly.Menu.isItemEnabled(entry.id)
			and ControlAlly.AbilityAI.isReady(context.controller, entry.ability, entry.id, false, true)
		then
			refresherEntry = entry
			break
		end
	end
	if not refresherEntry then
		return nil
	end
	local useful = 0
	local totalCooldown = 0
	local followupMana = 0
	for id in pairs(context.controller.usedAbilitiesSinceRefresh) do
		local ability = ControlAlly.AbilityAI.findAbility(context.controller, id, context.now)
		local remaining = ControlAlly.Utils.cooldownRemaining(ability)
		if ability and ControlAlly.Menu.isAbilityEnabled(id) and remaining > 0.10 then
			local rule = ControlAlly.Profiles.getAbilityRule(
				context.controller.profileName or context.controller.heroName,
				id
			) or ControlAlly.Profiles.InvokerSpells[id] or ControlAlly.AbilityAI.genericRule(ability, id)
			if rule and ControlAlly.AbilityAI.wouldBeUsableIfReady(context, ability, rule) then
				useful = useful + 1
				totalCooldown = totalCooldown + remaining
				followupMana = followupMana + (ControlAlly.Utils.call(Ability.GetManaCost, ability) or 0)
			end
		end
	end
	if useful < 2 or totalCooldown < ControlAlly.Constants.REFRESHER_MIN_TOTAL_COOLDOWN then
		return nil
	end
	local mana = ControlAlly.Utils.call(NPC.GetMana, context.unit) or 0
	local cost = ControlAlly.Utils.call(Ability.GetManaCost, refresherEntry.ability) or 0
	if mana < cost + followupMana then
		return nil
	end
	return {
		ability = refresherEntry.ability,
		id = refresherEntry.id,
		policy = "noTarget",
		score = 138,
		urgent = true,
		source = "item",
		isRefresher = true,
	}
end

function ControlAlly.SupportAI.refreshAllies(now, force)
	now = now or ControlAlly.Utils.gameTime()
	if
		not force
		and now - (ControlAlly.Runtime.lastAllyScanAt or -math.huge) < ControlAlly.Constants.ALLY_SCAN_INTERVAL
	then
		return ControlAlly.Runtime.allies
	end
	ControlAlly.Runtime.lastAllyScanAt = now
	local allies = {}
	local localHero = ControlAlly.Runtime.localHero
	for _, hero in ipairs(ControlAlly.Utils.call(Heroes.GetAll) or {}) do
		local states = Enum.ModifierState
		local invalidState = states
			and (
				ControlAlly.Utils.hasState(hero, states.MODIFIER_STATE_INVULNERABLE)
				or ControlAlly.Utils.hasState(hero, states.MODIFIER_STATE_OUT_OF_GAME)
				or ControlAlly.Utils.hasState(hero, states.MODIFIER_STATE_UNTARGETABLE)
			)
		if
			ControlAlly.Utils.isValidHero(hero, true)
			and ControlAlly.Utils.call(Entity.IsDormant, hero) ~= true
			and ControlAlly.Utils.call(NPC.IsIllusion, hero) ~= true
			and not invalidState
			and localHero
			and ControlAlly.Utils.call(Entity.IsSameTeam, hero, localHero) == true
		then
			allies[#allies + 1] = hero
		end
	end
	ControlAlly.Runtime.allies = allies
	return allies
end

function ControlAlly.SupportAI.reservationAvailable(rule, now)
	local family = rule.family
	return not family or (ControlAlly.Runtime.supportReservations[family] or -math.huge) <= now
end

function ControlAlly.SupportAI.reserve(action, now)
	local family = action.supportFamily
	if not family then
		return
	end
	local duration = ControlAlly.Utils.ruleValue(action.ability, action.rule, "duration", "durationSpecial", 0.65)
		or 0.65
	ControlAlly.Runtime.supportReservations[family] = now + math.max(0.65, duration)
end

function ControlAlly.SupportAI.allyTargetAction(context, ability, id, rule)
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
	local range = ControlAlly.AbilityAI.castRange(context.unit, ability, rule)
	local bestTarget
	local bestScore = -math.huge
	for _, ally in ipairs(ControlAlly.Runtime.allies) do
		local allyPosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, ally)
		local reservationKey = rule.family .. ":" .. tostring(ControlAlly.Utils.entityIndex(ally) or -1)
		if
			(ControlAlly.Runtime.supportReservations[reservationKey] or -math.huge) <= context.now
			and origin
			and allyPosition
			and ControlAlly.Utils.distance2D(origin, allyPosition) <= range + 40
		then
			local healthPct = ControlAlly.Utils.healthPct(ally)
			local hurt = ControlAlly.Utils.wasRecentlyHurt(ally, context.now)
			local enemyPosition = context.target and ControlAlly.Utils.call(Entity.GetAbsOrigin, context.target)
			local fighting = ControlAlly.Utils.call(NPC.IsAttacking, ally) == true
				and enemyPosition
				and ControlAlly.Utils.distance2D(allyPosition, enemyPosition)
					<= (ControlAlly.Utils.call(NPC.GetAttackRange, ally) or 150) + 350
			local threshold = rule.defensiveHealthPct or 75
			if (hurt and healthPct <= threshold) or (id == "item_solar_crest" and fighting and context.target) then
				local score = (rule.priority or 100) + (100 - healthPct) * 0.7 + (hurt and 18 or 0)
				if score > bestScore then
					bestTarget = ally
					bestScore = score
				end
			end
		end
	end
	if not bestTarget then
		return nil
	end
	return {
		ability = ability,
		id = id,
		policy = "ally",
		target = bestTarget,
		score = bestScore,
		urgent = rule.urgent == true,
		source = "item",
		rule = rule,
		supportFamily = rule.family .. ":" .. tostring(ControlAlly.Utils.entityIndex(bestTarget) or -1),
	}
end

function ControlAlly.SupportAI.noTargetAction(context, ability, id, rule)
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
	local radius = ControlAlly.AbilityAI.radius(ability, rule)
	local need = 0
	local fighting = 0
	local critical = false
	for _, ally in ipairs(ControlAlly.Runtime.allies) do
		local position = ControlAlly.Utils.call(Entity.GetAbsOrigin, ally)
		if origin and position and ControlAlly.Utils.distance2D(origin, position) <= radius then
			local healthPct = ControlAlly.Utils.healthPct(ally)
			local mana = ControlAlly.Utils.call(NPC.GetMana, ally) or 0
			local maxMana = ControlAlly.Utils.call(NPC.GetMaxMana, ally) or 0
			local missingMana = math.max(0, maxMana - mana)
			local missingHealth = math.max(
				0,
				(ControlAlly.Utils.call(Entity.GetMaxHealth, ally) or 0)
					- (ControlAlly.Utils.call(Entity.GetHealth, ally) or 0)
			)
			if id == "item_arcane_boots" then
				local amount = ControlAlly.Utils.ruleValue(ability, rule, "amount", "amountSpecial", 0) or 0
				if missingMana >= amount * 0.65 then
					need = need + 1
				end
				critical = critical or missingMana >= amount * 1.5
			elseif id == "item_guardian_greaves" then
				local heal = ControlAlly.Utils.ruleValue(ability, rule, "heal", "healSpecial", 0) or 0
				local manaAmount = ControlAlly.Utils.ruleValue(ability, rule, "amount", "amountSpecial", 0) or 0
				if missingHealth >= heal * 0.55 or missingMana >= manaAmount * 0.65 then
					need = need + 1
				end
				critical = critical or healthPct <= 32
			elseif id == "item_pipe" then
				if
					ControlAlly.Utils.wasRecentlyHurt(ally, context.now)
					and healthPct <= (rule.defensiveHealthPct or 75)
				then
					need = need + 1
				end
				critical = critical or (healthPct <= 36 and ControlAlly.Utils.wasRecentlyHurt(ally, context.now))
			elseif ControlAlly.Utils.call(NPC.IsAttacking, ally) == true and context.target then
				local enemyPosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.target)
				if
					enemyPosition
					and ControlAlly.Utils.distance2D(position, enemyPosition)
						<= (ControlAlly.Utils.call(NPC.GetAttackRange, ally) or 150) + 350
				then
					fighting = fighting + 1
				end
			end
		end
	end
	if id == "item_boots_of_bearing" then
		need = fighting
	end
	if need < 2 and not critical then
		return nil
	end
	return {
		ability = ability,
		id = id,
		policy = "noTarget",
		score = (rule.priority or 80) + need * 12,
		urgent = rule.urgent == true,
		source = "item",
		rule = rule,
		supportFamily = rule.family,
	}
end

function ControlAlly.SupportAI.bestAction(context)
	if not ControlAlly.UI.UseItems or ControlAlly.UI.UseItems:Get() ~= true then
		return nil
	end
	local best
	for _, entry in ipairs(ControlAlly.AbilityAI.catalog(context.controller, context.now).items) do
		local rule = ControlAlly.Profiles.SupportItems[entry.id]
		if
			rule
			and rule.policy ~= "refresher"
			and ControlAlly.Menu.isItemEnabled(entry.id)
			and ControlAlly.SupportAI.reservationAvailable(rule, context.now)
			and ControlAlly.AbilityAI.isReady(context.controller, entry.ability, entry.id, false, true)
		then
			local action
			if rule.policy == "ally" then
				action = ControlAlly.SupportAI.allyTargetAction(context, entry.ability, entry.id, rule)
			elseif
				rule.policy == "allyNoTarget"
				or rule.policy == "manaBoots"
				or rule.policy == "greaves"
				or rule.policy == "combatBoots"
			then
				action = ControlAlly.SupportAI.noTargetAction(context, entry.ability, entry.id, rule)
			elseif rule.policy == "chaseBoots" and context.target then
				local distance = ControlAlly.Utils.distance2D(
					ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit),
					ControlAlly.Utils.call(Entity.GetAbsOrigin, context.target)
				)
				local attackRange = ControlAlly.Utils.call(NPC.GetAttackRange, context.unit) or 150
				if distance > attackRange + 120 then
					action = {
						ability = entry.ability,
						id = entry.id,
						policy = "noTarget",
						score = rule.priority,
						source = "item",
						rule = rule,
						supportFamily = rule.family .. ":" .. tostring(
							ControlAlly.Utils.entityIndex(context.unit) or -1
						),
					}
				end
			elseif
				rule.policy == "powerTreads"
				and PowerTreads
				and PowerTreads.GetStats
				and Hero.GetPrimaryAttribute
			then
				local current = ControlAlly.Utils.call(PowerTreads.GetStats, entry.ability)
				local desired = ControlAlly.Utils.call(Hero.GetPrimaryAttribute, context.unit)
				if desired == Enum.Attributes.DOTA_ATTRIBUTE_ALL then
					if ControlAlly.Utils.healthPct(context.unit) < 50 then
						desired = Enum.Attributes.DOTA_ATTRIBUTE_STRENGTH
					elseif ControlAlly.Utils.manaPct(context.unit) < 28 then
						desired = Enum.Attributes.DOTA_ATTRIBUTE_INTELLECT
					else
						desired = Enum.Attributes.DOTA_ATTRIBUTE_AGILITY
					end
				end
				if current ~= nil and desired ~= nil and current ~= desired then
					action = {
						ability = entry.ability,
						id = entry.id,
						policy = "noTarget",
						score = rule.priority,
						source = "item",
						rule = rule,
						supportFamily = rule.family .. ":" .. tostring(
							ControlAlly.Utils.entityIndex(context.unit) or -1
						),
						treadsBefore = current,
					}
				end
			end
			if action and (not best or action.score > best.score) then
				best = action
			end
		end
	end
	return best
end

function ControlAlly.MeepoAI.netTiming(controller, target, ability, rule)
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, controller.unit)
	local targetPosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, target)
	if not origin or not targetPosition then
		return nil
	end
	local range = ControlAlly.AbilityAI.castRange(controller.unit, ability, rule)
	local radius = ControlAlly.AbilityAI.radius(ability, rule)
	local speed = ControlAlly.Utils.ruleValue(ability, rule, "projectileSpeed", "projectileSpeedSpecial", 0) or 0
	if speed <= 0 then
		return nil
	end
	local position = ControlAlly.Targeting.predictPosition(target, ability, rule)
	local predictedDistance = ControlAlly.Utils.distance2D(origin, position)
	if predictedDistance > range + radius then
		return nil
	end
	local castPosition = predictedDistance > range and ControlAlly.Utils.positionToward(origin, position, range)
		or position
	local castPoint = ControlAlly.Utils.call(Ability.GetCastPoint, ability, true)
		or ControlAlly.Utils.call(Ability.GetCastPoint, ability)
		or 0
	local faceTime = ControlAlly.Utils.call(NPC.GetTimeToFacePosition, controller.unit, castPosition) or 0
	local impactDelay = math.max(0, faceTime) + castPoint + ControlAlly.Utils.distance2D(origin, castPosition) / speed
	return impactDelay, castPosition
end

function ControlAlly.MeepoAI.bestNetCaster(context, target)
	local bestController
	local bestAbility
	local bestDelay = math.huge
	local bestPosition
	local rule = ControlAlly.Profiles.Heroes.npc_dota_hero_meepo.abilities.meepo_earthbind
	for _, controller in ipairs(ControlAlly.Runtime.controllers) do
		if
			controller.playerId == context.controller.playerId
			and controller.heroName == "npc_dota_hero_meepo"
			and not controller.pendingCast
			and context.now >= controller.busyUntil
			and not ControlAlly.Utils.isCommandRestricted(controller.unit)
		then
			local ability = ControlAlly.AbilityAI.findAbility(controller, "meepo_earthbind", context.now)
			if
				ControlAlly.Menu.isAbilityEnabled("meepo_earthbind")
				and ControlAlly.AbilityAI.isReady(controller, ability, "meepo_earthbind", false, false)
			then
				local delay, position = ControlAlly.MeepoAI.netTiming(controller, target, ability, rule)
				if delay and delay < bestDelay then
					bestController = controller
					bestAbility = ability
					bestDelay = delay
					bestPosition = position
				end
			end
		end
	end
	return bestController, bestAbility, bestDelay, bestPosition, rule
end

function ControlAlly.MeepoAI.sharedPlan(context)
	if not context.target then
		return nil
	end
	local targetIndex = ControlAlly.Utils.entityIndex(context.target)
	if not targetIndex then
		return nil
	end
	local key = tostring(context.controller.playerId) .. ":" .. tostring(targetIndex)
	local plan = ControlAlly.Runtime.meepoPlans[key]
	if
		plan
		and plan.target == context.target
		and plan.expiresAt > context.now
		and ControlAlly.Utils.isValidControllerUnit(plan.controller and plan.controller.unit, true)
	then
		return plan
	end
	local controller, ability, delay, position, rule = ControlAlly.MeepoAI.bestNetCaster(context, context.target)
	if not controller then
		ControlAlly.Runtime.meepoPlans[key] = nil
		return nil
	end
	plan = {
		key = key,
		target = context.target,
		targetIndex = targetIndex,
		controller = controller,
		casterIndex = ControlAlly.Utils.entityIndex(controller.unit),
		ability = ability,
		delay = delay,
		position = position,
		rule = rule,
		expiresAt = context.now + 0.12,
	}
	ControlAlly.Runtime.meepoPlans[key] = plan
	return plan
end

function ControlAlly.MeepoAI.netAction(context)
	local states = Enum.ModifierState
	local invalidTarget = states
		and (
			ControlAlly.Utils.hasState(context.target, states.MODIFIER_STATE_INVULNERABLE)
			or ControlAlly.Utils.hasState(context.target, states.MODIFIER_STATE_OUT_OF_GAME)
		)
	if
		not ControlAlly.UI.UseAbilities
		or ControlAlly.UI.UseAbilities:Get() ~= true
		or context.controller.heroName ~= "npc_dota_hero_meepo"
		or not context.target
		or ControlAlly.Utils.isMagicImmune(context.target)
		or invalidTarget
	then
		return nil
	end
	local targetIndex = ControlAlly.Utils.entityIndex(context.target)
	if not targetIndex then
		return nil
	end
	local chain = ControlAlly.Runtime.meepoNetChains[targetIndex]
	if chain and chain.target ~= context.target then
		ControlAlly.Runtime.meepoNetChains[targetIndex] = nil
		chain = nil
	end
	if chain and chain.inFlightUntil and context.now <= chain.inFlightUntil then
		return nil
	end
	if chain and chain.inFlightUntil and context.now > chain.inFlightUntil then
		if ControlAlly.Utils.modifierRemaining(context.target, "modifier_meepo_earthbind", context.now) <= 0 then
			ControlAlly.Runtime.meepoNetChains[targetIndex] = nil
			chain = nil
		else
			chain.inFlightUntil = nil
			chain.casterIndex = nil
		end
	end

	local plan = ControlAlly.MeepoAI.sharedPlan(context)
	if not plan or plan.controller ~= context.controller or not plan.ability or not plan.position then
		return nil
	end
	local ability = plan.ability
	local impactDelay = plan.delay
	local position = plan.position
	local rule = plan.rule
	local rootRemaining = ControlAlly.Utils.modifierRemaining(context.target, "modifier_meepo_earthbind", context.now)
	if rootRemaining > impactDelay + ControlAlly.Constants.MEEPO_NET_CHAIN_OVERLAP then
		return nil
	end
	local duration = ControlAlly.Utils.ruleValue(ability, rule, "duration", "durationSpecial", 0) or 0
	return {
		ability = ability,
		id = "meepo_earthbind",
		policy = "point",
		position = position,
		score = 154,
		urgent = rootRemaining > 0,
		source = "ability",
		rule = rule,
		isMeepoNet = true,
		meepoTargetIndex = targetIndex,
		meepoImpactAt = context.now + impactDelay,
		meepoRootDuration = duration,
		reservationTarget = context.target,
		dedupeKey = "meepo_earthbind:" .. tostring(targetIndex),
	}
end

function ControlAlly.MeepoAI.onCastResult(controller, pending, success, now)
	if not pending.isMeepoNet or not pending.meepoTargetIndex then
		return
	end
	local chain = ControlAlly.Runtime.meepoNetChains[pending.meepoTargetIndex]
	if not chain or chain.casterIndex ~= ControlAlly.Utils.entityIndex(controller.unit) then
		return
	end
	if not success then
		ControlAlly.Runtime.meepoNetChains[pending.meepoTargetIndex] = nil
		return
	end
	chain.confirmed = true
	chain.inFlightUntil = (pending.meepoImpactAt or now) + ControlAlly.Constants.MEEPO_NET_HIT_GRACE
	controller.meepo.lastNetAt = now
end

function ControlAlly.MeepoAI.poofAction(context)
	if
		not ControlAlly.UI.UseAbilities
		or ControlAlly.UI.UseAbilities:Get() ~= true
		or context.controller.heroName ~= "npc_dota_hero_meepo"
		or not context.target
		or not ControlAlly.Menu.isAbilityEnabled("meepo_poof")
	then
		return nil
	end
	local ability = ControlAlly.AbilityAI.findAbility(context.controller, "meepo_poof", context.now)
	if not ControlAlly.AbilityAI.isReady(context.controller, ability, "meepo_poof", false, false) then
		return nil
	end
	local groupPoof = Ability.GetAltCastState and ControlAlly.Utils.call(Ability.GetAltCastState, ability) == true
	if groupPoof then
		return {
			ability = ability,
			id = "meepo_poof_group_toggle",
			policy = "toggleAlt",
			score = 190,
			urgent = true,
			source = "ability",
			rule = { policy = "toggleAlt" },
			desiredAlt = false,
			allowRapid = true,
			dedupeKey = "meepo_poof_group_toggle",
		}
	end
	local plan = ControlAlly.MeepoAI.sharedPlan(context)
	if plan and plan.casterIndex == ControlAlly.Utils.entityIndex(context.controller.unit) then
		local anotherPoof = false
		for _, other in ipairs(ControlAlly.Runtime.controllers) do
			if
				other ~= context.controller
				and other.playerId == context.controller.playerId
				and other.heroName == "npc_dota_hero_meepo"
			then
				local candidate = ControlAlly.AbilityAI.findAbility(other, "meepo_poof", context.now)
				if ControlAlly.AbilityAI.isReady(other, candidate, "meepo_poof", false, false) then
					anotherPoof = true
					break
				end
			end
		end
		if anotherPoof then
			return nil
		end
	end
	local rule = ControlAlly.Profiles.Heroes.npc_dota_hero_meepo.abilities.meepo_poof
	local radius = ControlAlly.AbilityAI.radius(ability, rule)
	local targetPosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.target)
	local destination
	local destinationDistance = math.huge
	for _, controller in ipairs(ControlAlly.Runtime.controllers) do
		if controller.playerId == context.controller.playerId and controller.heroName == "npc_dota_hero_meepo" then
			local position = ControlAlly.Utils.call(Entity.GetAbsOrigin, controller.unit)
			local distance = ControlAlly.Utils.distance2D(position, targetPosition)
			if distance <= radius and distance < destinationDistance then
				destination = controller.unit
				destinationDistance = distance
			end
		end
	end
	if not destination then
		return nil
	end
	return {
		ability = ability,
		id = "meepo_poof",
		policy = "ally",
		target = destination,
		score = 84,
		source = "ability",
		rule = rule,
		groupPoof = groupPoof,
	}
end

function ControlAlly.AlchemistAI.syncBrewing(controller, now)
	local state = controller.alchemist
	local throw = ControlAlly.AbilityAI.findAbility(controller, "alchemist_unstable_concoction_throw", now)
	local visible = throw and ControlAlly.Utils.call(Ability.IsHidden, throw) ~= true
	if visible and not state.brewing then
		state.brewing = true
		local modifier =
			ControlAlly.Utils.call(NPC.GetModifier, controller.unit, "modifier_alchemist_unstable_concoction")
		local created = modifier and ControlAlly.Utils.call(Modifier.GetCreationTime, modifier)
		state.startedAt = type(created) == "number" and created or now
	end
	if state.brewing and not visible then
		local start = ControlAlly.AbilityAI.findAbility(controller, "alchemist_unstable_concoction", now)
		local explosionTime = ControlAlly.Utils.specialValueExact(start, "brew_explosion", 0) or 0
		if explosionTime <= 0 then
			local brewTime = ControlAlly.Utils.specialValueExact(start, "brew_time", 5.5) or 5.5
			explosionTime = math.max(brewTime + 2.0, ControlAlly.Constants.ALCHEMIST_BREW_FALLBACK)
		end
		if now - state.startedAt > explosionTime + 0.50 then
			state.brewing = false
			state.startedAt = -math.huge
			state.target = nil
		end
	end
	return state.brewing, throw
end

function ControlAlly.AlchemistAI.throwTarget(controller, preferred, throw, now)
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, controller.unit)
	local range = ControlAlly.AbilityAI.castRange(controller.unit, throw, {})
	local function valid(target)
		local states = Enum.ModifierState
		local invalidState = states
			and (
				ControlAlly.Utils.hasState(target, states.MODIFIER_STATE_INVULNERABLE)
				or ControlAlly.Utils.hasState(target, states.MODIFIER_STATE_OUT_OF_GAME)
				or ControlAlly.Utils.hasState(target, states.MODIFIER_STATE_UNTARGETABLE)
			)
		return ControlAlly.Targeting.isValidEnemy(target)
			and not ControlAlly.Utils.isMagicImmune(target)
			and not invalidState
			and ControlAlly.Utils.distance2D(origin, ControlAlly.Utils.call(Entity.GetAbsOrigin, target)) <= range
	end
	if valid(preferred) then
		return preferred
	end
	local best
	local bestTime = math.huge
	for _, enemy in ipairs(ControlAlly.Runtime.enemies) do
		if valid(enemy) then
			local position = ControlAlly.Utils.call(Entity.GetAbsOrigin, enemy)
			local faceTime = ControlAlly.Utils.call(NPC.GetTimeToFacePosition, controller.unit, position) or 0
			if faceTime < bestTime then
				best = enemy
				bestTime = faceTime
			end
		end
	end
	return best
end

function ControlAlly.AlchemistAI.nextAction(context, emergency)
	if context.controller.heroName ~= "npc_dota_hero_alchemist" then
		return nil
	end
	local controller = context.controller
	local state = controller.alchemist
	local brewing, throw = ControlAlly.AlchemistAI.syncBrewing(controller, context.now)
	if brewing then
		if
			not throw
			or not ControlAlly.AbilityAI.isReady(
				controller,
				throw,
				"alchemist_unstable_concoction_throw",
				true,
				false,
				true,
				true
			)
		then
			return nil
		end
		local start = ControlAlly.AbilityAI.findAbility(controller, "alchemist_unstable_concoction", context.now)
		local brewTime = ControlAlly.Utils.specialValueExact(start, "brew_time", 0) or 0
		local explosionTime = ControlAlly.Utils.specialValueExact(start, "brew_explosion", brewTime) or brewTime
		local elapsed = math.max(0, context.now - state.startedAt)
		local target =
			ControlAlly.AlchemistAI.throwTarget(controller, state.target or context.target, throw, context.now)
		if not target then
			return nil
		end
		local castPoint = ControlAlly.Utils.call(Ability.GetCastPoint, throw) or 0
		local faceTime = ControlAlly.Utils.call(
			NPC.GetTimeToFacePosition,
			controller.unit,
			ControlAlly.Utils.call(Entity.GetAbsOrigin, target)
		) or 0
		local shouldThrow = emergency
			or elapsed >= brewTime * 0.78
			or elapsed + math.max(0, faceTime) + castPoint + 0.12 >= explosionTime
		if not shouldThrow then
			return nil
		end
		return {
			ability = throw,
			id = "alchemist_unstable_concoction_throw",
			policy = "enemy",
			target = target,
			reservationTarget = target,
			score = 520,
			urgent = true,
			source = "ability",
			allowRapid = true,
			alchemistStage = "throw",
		}
	end
	if
		emergency
		or not ControlAlly.UI.UseAbilities
		or ControlAlly.UI.UseAbilities:Get() ~= true
		or not context.target
		or not ControlAlly.Menu.isAbilityEnabled("alchemist_unstable_concoction")
		or not ControlAlly.Menu.isAbilityEnabled("alchemist_unstable_concoction_throw")
	then
		return nil
	end
	local start = ControlAlly.AbilityAI.findAbility(controller, "alchemist_unstable_concoction", context.now)
	if not ControlAlly.AbilityAI.isReady(controller, start, "alchemist_unstable_concoction", false, false) then
		return nil
	end
	local target = ControlAlly.AlchemistAI.throwTarget(controller, context.target, throw, context.now)
	if not target then
		return nil
	end
	return {
		ability = start,
		id = "alchemist_unstable_concoction",
		policy = "noTarget",
		reservationTarget = target,
		score = 88,
		source = "ability",
		alchemistStage = "start",
	}
end

function ControlAlly.AlchemistAI.onCastResult(controller, pending, success, now)
	if not pending.alchemistStage then
		return
	end
	local state = controller.alchemist
	if pending.alchemistStage == "start" then
		state.brewing = success
		state.startedAt = success and now or -math.huge
		state.target = success and pending.castTarget or nil
	elseif pending.alchemistStage == "throw" and success then
		state.brewing = false
		state.startedAt = -math.huge
		state.target = nil
	end
end

function ControlAlly.AlchemistAI.finishBrews(now)
	for _, controller in pairs(ControlAlly.Runtime.controllerStates) do
		if controller.heroName == "npc_dota_hero_alchemist" then
			ControlAlly.Combat.confirmPendingCast(controller, now)
			local brewing = ControlAlly.AlchemistAI.syncBrewing(controller, now)
			if brewing and not controller.pendingCast and now >= controller.busyUntil then
				local action = ControlAlly.AlchemistAI.nextAction({
					controller = controller,
					unit = controller.unit,
					target = controller.alchemist.target,
					now = now,
				}, true)
				if action and ControlAlly.Orders.cast(controller, action, now) then
					return true
				end
			end
		end
	end
	return false
end

function ControlAlly.TechiesAI.createMinePlan(context, ability, rule)
	local targetPosition = ControlAlly.Targeting.predictPosition(context.target, ability, rule)
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
	if not targetPosition or not origin then
		return nil
	end
	local direction = ControlAlly.Utils.normalized2D(origin, targetPosition)
	if not direction then
		return nil
	end
	local radius = ControlAlly.AbilityAI.radius(ability, rule)
	local minimumSpacing = ControlAlly.Utils.specialValue(ability, { "min_distance", "minimum_proximity" }, radius)
	local triggerRadius = ControlAlly.Utils.specialValue(ability, { "radius", "trigger_radius" }, radius)
	local reanchorRadius = ControlAlly.Utils.specialValue(ability, { "placement_radius", "radius" }, radius)
	local ringRadius = math.max(minimumSpacing + 12, triggerRadius * 0.55)
	local range = ControlAlly.AbilityAI.castRange(context.unit, ability, rule)
	local edgeBuffer = math.min(24, range * 0.05)
	if ringRadius + edgeBuffer >= range then
		return nil
	end
	local targetDistance = ControlAlly.Utils.distance2D(origin, targetPosition)
	if targetDistance > range + triggerRadius then
		return nil
	end
	local maximumCenterDistance = math.max(0, range - ringRadius - edgeBuffer)
	local center = targetDistance > maximumCenterDistance
			and ControlAlly.Utils.positionToward(origin, targetPosition, maximumCenterDistance)
		or targetPosition
	local points = {}
	for index = 1, 3 do
		local offset = ControlAlly.Utils.rotate2D(direction, (index - 1) * math.pi * 2 / 3)
		points[index] = Vector(center.x + offset.x * ringRadius, center.y + offset.y * ringRadius, center.z or 0)
	end
	return {
		target = context.target,
		targetIndex = ControlAlly.Utils.entityIndex(context.target),
		points = points,
		nextIndex = 1,
		completed = false,
		anchor = targetPosition,
		triggerRadius = triggerRadius,
		reanchorRadius = reanchorRadius,
		createdAt = context.now,
	}
end

function ControlAlly.TechiesAI.mineAction(context)
	if
		(context.controller.profileName or context.controller.heroName) ~= "npc_dota_hero_techies"
		or not context.target
		or not ControlAlly.UI.UseAbilities
		or ControlAlly.UI.UseAbilities:Get() ~= true
		or not ControlAlly.Menu.isAbilityEnabled("techies_land_mines")
	then
		return nil
	end
	local ability = ControlAlly.AbilityAI.findAbility(context.controller, "techies_land_mines", context.now)
	local rule = ControlAlly.Profiles.Heroes.npc_dota_hero_techies.abilities.techies_land_mines
	if
		not ability
		or not ControlAlly.AbilityAI.isReady(context.controller, ability, "techies_land_mines", false, false)
	then
		return nil
	end
	local state = context.controller.techies
	local targetIndex = ControlAlly.Utils.entityIndex(context.target)
	local liveTargetPosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.target)
	if
		state.minePlan
		and (
			context.now - state.minePlan.createdAt > 5.0
			or (
				state.minePlan.nextIndex == 1
				and ControlAlly.Utils.distance2D(state.minePlan.anchor, liveTargetPosition)
					> state.minePlan.reanchorRadius * 0.75
			)
		)
	then
		state.minePlan = nil
	end
	if not state.minePlan or state.minePlan.target ~= context.target or state.minePlan.targetIndex ~= targetIndex then
		state.minePlan = ControlAlly.TechiesAI.createMinePlan(context, ability, rule)
	end
	local plan = state.minePlan
	if not plan or plan.completed then
		return nil
	end
	local position = plan.points[plan.nextIndex]
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
	local range = ControlAlly.AbilityAI.castRange(context.unit, ability, rule)
	if
		not position
		or ControlAlly.Utils.distance2D(origin, position) > range + ControlAlly.Constants.CAST_RANGE_BUFFER
	then
		state.minePlan = nil
		return nil
	end
	return {
		ability = ability,
		id = "techies_land_mines",
		policy = "point",
		position = position,
		score = 148,
		urgent = true,
		source = "ability",
		rule = rule,
		techiesMine = true,
		techiesMineIndex = plan.nextIndex,
		techiesMineTargetIndex = targetIndex,
		dedupeKey = "techies_mine_plan:" .. tostring(targetIndex) .. ":" .. tostring(plan.nextIndex),
	}
end

function ControlAlly.TechiesAI.onCastResult(controller, pending, success)
	if not pending.techiesMine then
		return
	end
	local plan = controller.techies.minePlan
	if not plan or plan.targetIndex ~= pending.techiesMineTargetIndex or plan.nextIndex ~= pending.techiesMineIndex then
		return
	end
	if not success then
		controller.techies.minePlan = nil
		return
	end
	plan.nextIndex = plan.nextIndex + 1
	plan.completed = plan.nextIndex > #plan.points
end

function ControlAlly.SpecialAI.invalidateCatalog(controller)
	controller.catalog = nil
	controller.catalogRefreshAt = -math.huge
	ControlAlly.Runtime.lastMenuSyncAt = -math.huge
end

function ControlAlly.SpecialAI.exposedAbility(controller, id)
	local ability = ControlAlly.Utils.call(NPC.GetAbility, controller.unit, id)
	if not ability or ControlAlly.Utils.call(Ability.IsActivated, ability) == false then
		return nil
	end
	return ControlAlly.Utils.call(Ability.IsHidden, ability) ~= true and ability or nil
end

function ControlAlly.SpecialAI.reconcileController(controller, now)
	if controller.special.stage then
		return
	end
	local profileName = controller.profileName or controller.heroName
	local stageByAbility = {
		npc_dota_hero_ancient_apparition = {
			id = "ancient_apparition_ice_blast_release",
			stage = "aa_release",
		},
		npc_dota_hero_morphling = { id = "morphling_morph_replicate", stage = "morph_copied" },
		npc_dota_hero_spectre = { id = "spectre_reality", stage = "spectre_reality" },
		npc_dota_hero_ember_spirit = {
			id = "ember_spirit_activate_fire_remnant",
			stage = "ember_activate",
		},
		npc_dota_hero_monkey_king = { id = "monkey_king_primal_spring", stage = "monkey_spring" },
	}
	local transition = stageByAbility[profileName]
	if transition and ControlAlly.SpecialAI.exposedAbility(controller, transition.id) then
		controller.special.stage = transition.stage
		controller.special.startedAt = now
		return
	end
	if
		profileName == "npc_dota_hero_dazzle"
		and not ControlAlly.Utils.isNothlProjection(controller.unit)
		and XHelpers
		and XHelpers.XNPC
		and XHelpers.XNPC.GetNothlProjection
	then
		local projection = ControlAlly.Utils.call(XHelpers.XNPC.GetNothlProjection, XHelpers.XNPC, controller.unit)
		if ControlAlly.Utils.isValidControllerUnit(projection, true) then
			controller.special.stage = "dazzle_active"
			controller.special.startedAt = now
		end
	end
end

function ControlAlly.SpecialAI.requiresRetention(controller)
	local special = controller.special
	local stage = special and special.stage
	if not stage then
		return false
	end
	if stage == "aa_release" then
		return true
	end
	if stage == "dazzle_active" then
		local projection = XHelpers
			and XHelpers.XNPC
			and XHelpers.XNPC.GetNothlProjection
			and ControlAlly.Utils.call(XHelpers.XNPC.GetNothlProjection, XHelpers.XNPC, controller.unit)
		if ControlAlly.Utils.isValidControllerUnit(projection, true) then
			return true
		end
		special.stage = nil
		return false
	end
	local abilityByStage = {
		morph_copied = "morphling_morph_replicate",
		spectre_reality = "spectre_reality",
		ember_activate = "ember_spirit_activate_fire_remnant",
		monkey_spring = "monkey_king_primal_spring",
	}
	local id = abilityByStage[stage]
	if id and ControlAlly.SpecialAI.exposedAbility(controller, id) then
		return true
	end
	if ControlAlly.Utils.gameTime() - (special.startedAt or -math.huge) <= 2.0 then
		return true
	end
	special.stage = nil
	return false
end

function ControlAlly.SpecialAI.ready(context, id, allowHidden, ignoreManaFloor, allowUnlearned)
	if not ControlAlly.Menu.isAbilityEnabled(id) then
		return nil
	end
	local ability = ControlAlly.AbilityAI.findAbility(context.controller, id, context.now)
	if
		not ControlAlly.AbilityAI.isReady(
			context.controller,
			ability,
			id,
			allowHidden == true,
			false,
			ignoreManaFloor == true,
			allowUnlearned == true
		)
	then
		return nil
	end
	return ability
end

function ControlAlly.SpecialAI.loneDruidAction(context)
	if (context.controller.profileName or context.controller.heroName) ~= "npc_dota_hero_lone_druid" then
		return nil
	end
	local summon = ControlAlly.SpecialAI.ready(context, "lone_druid_spirit_bear", false)
	if not summon then
		return nil
	end
	local bear = CustomEntities
		and CustomEntities.GetSpiritBear
		and ControlAlly.Utils.call(CustomEntities.GetSpiritBear, summon)
	if ControlAlly.Utils.isValidControllerUnit(bear, true) then
		return nil
	end
	return {
		ability = summon,
		id = "lone_druid_spirit_bear",
		policy = "noTarget",
		score = 142,
		urgent = true,
		source = "ability",
		specialStage = "lone_summon",
	}
end

function ControlAlly.KezAI.switchAction(context)
	if (context.controller.profileName or context.controller.heroName) ~= "npc_dota_hero_kez" then
		return nil
	end
	local state = context.controller.kez
	if
		context.now - state.lastSwitchAt < 0.35
		or (state.lastSwitchAt > -math.huge and state.castsAfterSwitch <= 0 and context.now - state.lastSwitchAt < 1.5)
	then
		return nil
	end
	local ability = ControlAlly.SpecialAI.ready(context, "kez_switch_weapons", false)
	if not ability then
		return nil
	end
	local forms = {
		katana = { "kez_echo_slash", "kez_grappling_claw", "kez_kazurai_katana", "kez_raptor_dance" },
		sai = { "kez_falcon_rush", "kez_talon_toss", "kez_shodo_sai", "kez_ravens_veil" },
	}
	local currentForm = ControlAlly.Utils.call(NPC.HasModifier, context.unit, "modifier_kez_sai") == true and "sai"
		or "katana"
	local otherForm = currentForm == "katana" and "sai" or "katana"
	local mana = ControlAlly.Utils.call(NPC.GetMana, context.unit) or 0
	local function variants(id)
		return { id, id .. "_ad" }
	end
	local currentReady = false
	for _, logicalId in ipairs(forms[currentForm]) do
		if ControlAlly.Menu.isAbilityEnabled(logicalId) then
			for _, id in ipairs(variants(logicalId)) do
				local candidate = ControlAlly.Utils.call(NPC.GetAbility, context.unit, id)
				if ControlAlly.AbilityAI.isReady(context.controller, candidate, id, true, false) then
					currentReady = true
					break
				end
			end
		end
		if currentReady then
			break
		end
	end
	if currentReady then
		return nil
	end
	local otherUseful = false
	for _, logicalId in ipairs(forms[otherForm]) do
		if ControlAlly.Menu.isAbilityEnabled(logicalId) then
			for _, id in ipairs(variants(logicalId)) do
				local candidate = ControlAlly.Utils.call(NPC.GetAbility, context.unit, id)
				local level = candidate and (ControlAlly.Utils.call(Ability.GetLevel, candidate) or 0) or 0
				local cost = candidate and (ControlAlly.Utils.call(Ability.GetManaCost, candidate) or 0) or math.huge
				if level > 0 and ControlAlly.Utils.cooldownRemaining(candidate) <= 0.03 and mana >= cost then
					otherUseful = true
					break
				end
			end
		end
		if otherUseful then
			break
		end
	end
	if not otherUseful then
		return nil
	end
	return {
		ability = ability,
		id = "kez_switch_weapons",
		policy = "noTarget",
		score = 18,
		source = "ability",
		specialStage = "kez_switch",
		dedupeKey = "kez_switch_weapons:" .. otherForm,
	}
end

function ControlAlly.SpecialAI.spectreAction(context)
	if
		(context.controller.profileName or context.controller.heroName) ~= "npc_dota_hero_spectre" or not context.target
	then
		return nil
	end
	local state = context.controller.special
	if state.stage == "spectre_reality" then
		local reality = ControlAlly.SpecialAI.ready(context, "spectre_reality", true)
		if reality then
			return {
				ability = reality,
				id = "spectre_reality",
				policy = "point",
				position = ControlAlly.Targeting.predictPosition(context.target, reality, {}),
				score = 190,
				urgent = true,
				source = "ability",
				specialStage = "spectre_reality",
				allowRapid = true,
			}
		end
		if context.now - state.startedAt > 1.25 then
			state.stage = nil
		end
		return nil
	end
	local distance = ControlAlly.Utils.distance2D(
		ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit),
		ControlAlly.Utils.call(Entity.GetAbsOrigin, context.target)
	)
	local attackRange = ControlAlly.Utils.call(NPC.GetAttackRange, context.unit) or 150
	if distance <= attackRange + 250 then
		return nil
	end
	local haunt = ControlAlly.SpecialAI.ready(context, "spectre_haunt", false)
	if haunt then
		return {
			ability = haunt,
			id = "spectre_haunt",
			policy = "noTarget",
			reservationTarget = context.target,
			score = 118,
			source = "ability",
			specialStage = "spectre_open",
		}
	end
	local shadowStep = ControlAlly.SpecialAI.ready(context, "spectre_shadow_step", false)
	if shadowStep then
		return {
			ability = shadowStep,
			id = "spectre_shadow_step",
			policy = "enemy",
			target = context.target,
			reservationTarget = context.target,
			score = 118,
			source = "ability",
			specialStage = "spectre_open",
		}
	end
	return nil
end

function ControlAlly.SpecialAI.emberAction(context)
	if
		(context.controller.profileName or context.controller.heroName) ~= "npc_dota_hero_ember_spirit"
		or not context.target
	then
		return nil
	end
	local state = context.controller.special
	if state.stage == "ember_activate" then
		local activate = ControlAlly.SpecialAI.ready(context, "ember_spirit_activate_fire_remnant", true)
		if activate then
			return {
				ability = activate,
				id = "ember_spirit_activate_fire_remnant",
				policy = "point",
				position = ControlAlly.Targeting.predictPosition(context.target, activate, {}),
				score = 176,
				urgent = true,
				source = "ability",
				committedMotion = true,
				specialStage = "ember_activate",
				allowRapid = true,
			}
		end
		if context.now - state.startedAt > 1.0 then
			state.stage = nil
		end
		return nil
	end
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
	local targetPosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.target)
	local attackRange = ControlAlly.Utils.call(NPC.GetAttackRange, context.unit) or 150
	if ControlAlly.Utils.distance2D(origin, targetPosition) <= attackRange + 225 then
		return nil
	end
	local remnant = ControlAlly.SpecialAI.ready(context, "ember_spirit_fire_remnant", false)
	if not remnant then
		return nil
	end
	local range = ControlAlly.AbilityAI.castRange(context.unit, remnant, {})
	local predicted = ControlAlly.Targeting.predictPosition(context.target, remnant, {})
	if ControlAlly.Utils.distance2D(origin, predicted) > range then
		predicted = ControlAlly.Utils.positionToward(origin, predicted, range)
	end
	return {
		ability = remnant,
		id = "ember_spirit_fire_remnant",
		policy = "point",
		position = predicted,
		reservationTarget = context.target,
		score = 92,
		source = "ability",
		specialStage = "ember_place",
	}
end

function ControlAlly.SpecialAI.hoodwinkAction(context)
	if
		(context.controller.profileName or context.controller.heroName) ~= "npc_dota_hero_hoodwink"
		or not context.target
	then
		return nil
	end
	local ability = ControlAlly.SpecialAI.ready(context, "hoodwink_bushwhack", false)
	if not ability or (not Trees or not Trees.InRadius) then
		return nil
	end
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
	local predicted = ControlAlly.Targeting.predictPosition(context.target, ability, {})
	if not origin or not predicted then
		return nil
	end
	local radius = ControlAlly.Utils.specialValueExact(ability, "trap_radius", 0) or 0
	if radius <= 0 then
		return nil
	end
	local castRange = ControlAlly.AbilityAI.castRange(context.unit, ability, {})
	local bestPosition
	local bestDistance = math.huge
	local function considerTree(tree)
		if Tree.IsActive and ControlAlly.Utils.call(Tree.IsActive, tree) == false then
			return
		end
		local treePosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, tree)
		local treeDistance = ControlAlly.Utils.distance2D(predicted, treePosition)
		if treeDistance > radius * 1.90 then
			return
		end
		local position = predicted
		if treeDistance > radius * 0.90 then
			position = ControlAlly.Utils.positionToward(predicted, treePosition, treeDistance * 0.50)
		end
		if
			ControlAlly.Utils.distance2D(origin, position) <= castRange + ControlAlly.Constants.CAST_RANGE_BUFFER
			and treeDistance < bestDistance
		then
			bestPosition = position
			bestDistance = treeDistance
		end
	end
	for _, tree in ipairs(ControlAlly.Utils.call(Trees.InRadius, predicted, radius * 1.90, true) or {}) do
		considerTree(tree)
	end
	if TempTrees and TempTrees.InRadius then
		for _, tree in ipairs(ControlAlly.Utils.call(TempTrees.InRadius, predicted, radius * 1.90) or {}) do
			considerTree(tree)
		end
	end
	if not bestPosition then
		return nil
	end
	return {
		ability = ability,
		id = "hoodwink_bushwhack",
		policy = "point",
		position = bestPosition,
		reservationTarget = context.target,
		score = 104,
		source = "ability",
	}
end

function ControlAlly.SpecialAI.monkeyAction(context)
	if
		(context.controller.profileName or context.controller.heroName) ~= "npc_dota_hero_monkey_king"
		or not context.target
	then
		return nil
	end
	local state = context.controller.special
	if state.stage == "monkey_spring" then
		local spring = ControlAlly.SpecialAI.ready(context, "monkey_king_primal_spring", true)
		if spring then
			local position = ControlAlly.Targeting.predictPosition(context.target, spring, {})
			local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
			local range = ControlAlly.AbilityAI.castRange(context.unit, spring, {})
			if ControlAlly.Utils.distance2D(origin, position) <= range + ControlAlly.Constants.CAST_RANGE_BUFFER then
				return {
					ability = spring,
					id = "monkey_king_primal_spring",
					policy = "point",
					position = position,
					score = 184,
					urgent = true,
					source = "ability",
					specialStage = "monkey_spring",
					allowRapid = true,
				}
			end
		end
		if context.now - state.startedAt > 1.0 then
			state.stage = nil
		end
		return nil
	end
	local treeDance = ControlAlly.SpecialAI.ready(context, "monkey_king_tree_dance", false)
	if not treeDance or not Trees or not Trees.InRadius then
		return nil
	end
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
	local targetPosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.target)
	local attackRange = ControlAlly.Utils.call(NPC.GetAttackRange, context.unit) or 150
	if ControlAlly.Utils.distance2D(origin, targetPosition) <= attackRange + 250 then
		return nil
	end
	local range = ControlAlly.AbilityAI.castRange(context.unit, treeDance, {})
	local bestTree
	local bestDistance = math.huge
	for _, tree in ipairs(ControlAlly.Utils.call(Trees.InRadius, origin, range, true) or {}) do
		if not Tree.IsActive or ControlAlly.Utils.call(Tree.IsActive, tree) ~= false then
			local position = ControlAlly.Utils.call(Entity.GetAbsOrigin, tree)
			local distance = ControlAlly.Utils.distance2D(position, targetPosition)
			if distance < bestDistance then
				bestTree = tree
				bestDistance = distance
			end
		end
	end
	if not bestTree then
		return nil
	end
	return {
		ability = treeDance,
		id = "monkey_king_tree_dance",
		policy = "tree",
		target = bestTree,
		reservationTarget = context.target,
		score = 96,
		source = "ability",
		specialStage = "monkey_tree",
	}
end

function ControlAlly.SpecialAI.marciAction(context)
	if
		(context.controller.profileName or context.controller.heroName) ~= "npc_dota_hero_marci" or not context.target
	then
		return nil
	end
	local ability = ControlAlly.SpecialAI.ready(context, "marci_companion_run", false)
	if not ability then
		return nil
	end
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
	local targetPosition = ControlAlly.Targeting.predictPosition(context.target, ability, {})
	local range = ControlAlly.AbilityAI.castRange(context.unit, ability, {})
	local bestAlly
	local bestDistance = math.huge
	for _, ally in ipairs(ControlAlly.Runtime.allies) do
		if ally ~= context.unit then
			local position = ControlAlly.Utils.call(Entity.GetAbsOrigin, ally)
			local fromCaster = ControlAlly.Utils.distance2D(origin, position)
			local toTarget = ControlAlly.Utils.distance2D(position, targetPosition)
			if fromCaster <= range + ControlAlly.Constants.CAST_RANGE_BUFFER and toTarget < bestDistance then
				bestAlly = ally
				bestDistance = toTarget
			end
		end
	end
	if not bestAlly then
		return nil
	end
	return {
		ability = ability,
		id = "marci_companion_run",
		policy = "vectorTarget",
		target = bestAlly,
		position = ControlAlly.Utils.call(Entity.GetAbsOrigin, bestAlly),
		vectorEnd = targetPosition,
		reservationTarget = context.target,
		score = 94,
		source = "ability",
		committedMotion = true,
		rule = {
			projectileSpeedSpecial = "move_speed",
			motionExtraDurationSpecial = "max_lob_travel_time",
		},
		specialStage = "marci_rebound",
	}
end

function ControlAlly.SpecialAI.dawnbreakerAction(context)
	if
		(context.controller.profileName or context.controller.heroName) ~= "npc_dota_hero_dawnbreaker"
		or not context.target
	then
		return nil
	end
	local converge = ControlAlly.SpecialAI.ready(context, "dawnbreaker_converge", true)
	if not converge then
		return nil
	end
	local distance = ControlAlly.Utils.distance2D(
		ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit),
		ControlAlly.Utils.call(Entity.GetAbsOrigin, context.target)
	)
	local attackRange = ControlAlly.Utils.call(NPC.GetAttackRange, context.unit) or 150
	if distance <= attackRange + 180 then
		return nil
	end
	return {
		ability = converge,
		id = "dawnbreaker_converge",
		policy = "noTarget",
		score = 134,
		urgent = true,
		source = "ability",
		committedMotion = true,
		allowRapid = true,
		specialStage = "dawn_converge",
	}
end

function ControlAlly.SpecialAI.ancientApparitionAction(context)
	if (context.controller.profileName or context.controller.heroName) ~= "npc_dota_hero_ancient_apparition" then
		return nil
	end
	local state = context.controller.special
	local release =
		ControlAlly.AbilityAI.findAbility(context.controller, "ancient_apparition_ice_blast_release", context.now)
	if
		not ControlAlly.Menu.isAbilityEnabled("ancient_apparition_ice_blast")
		or not ControlAlly.AbilityAI.isReady(
			context.controller,
			release,
			"ancient_apparition_ice_blast_release",
			true,
			false,
			true,
			true
		)
	then
		release = nil
	end
	if release and (state.stage ~= "aa_release" or context.now >= state.startedAt) then
		return {
			ability = release,
			id = "ancient_apparition_ice_blast_release",
			policy = "noTarget",
			score = 220,
			urgent = true,
			source = "ability",
			allowRapid = true,
			specialStage = "aa_release",
			dedupeKey = "aa_ice_blast_release",
		}
	end
	if state.stage == "aa_release" and not release and context.now > state.startedAt + 1.5 then
		state.stage = nil
		state.target = nil
	end
	if state.stage == "aa_release" or not context.target then
		return nil
	end
	local launch = ControlAlly.SpecialAI.ready(context, "ancient_apparition_ice_blast", false)
	if not launch then
		return nil
	end
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
	local position = ControlAlly.Targeting.predictPosition(context.target, launch, {
		projectileSpeedSpecial = "speed",
	})
	local speed = ControlAlly.Utils.specialValueExact(launch, "speed", 0) or 0
	local travelTime = speed > 0 and ControlAlly.Utils.distance2D(origin, position) / speed or 0
	return {
		ability = launch,
		id = "ancient_apparition_ice_blast",
		policy = "point",
		position = position,
		reservationTarget = context.target,
		score = 126,
		source = "ability",
		specialStage = "aa_launch",
		specialTravelTime = travelTime,
	}
end

function ControlAlly.SpecialAI.shadowFiendAction(context)
	if
		(context.controller.profileName or context.controller.heroName) ~= "npc_dota_hero_nevermore"
		or not context.target
	then
		return nil
	end
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
	local targetPosition = ControlAlly.Targeting.predictPosition(context.target, nil, {})
	local distance = ControlAlly.Utils.distance2D(origin, targetPosition)
	local best
	local bestError = math.huge
	for _, id in ipairs({ "nevermore_shadowraze1", "nevermore_shadowraze2", "nevermore_shadowraze3" }) do
		local ability = ControlAlly.SpecialAI.ready(context, id, false)
		if ability then
			local razeRange = ControlAlly.Utils.specialValueExact(ability, "shadowraze_range", 0) or 0
			local radius = ControlAlly.Utils.specialValueExact(ability, "shadowraze_radius", 0) or 0
			local errorDistance = math.abs(distance - razeRange)
			if razeRange > 0 and radius > 0 and errorDistance <= radius and errorDistance < bestError then
				best = ability
				bestError = errorDistance
			end
		end
	end
	if not best then
		return nil
	end
	local faceTime = ControlAlly.Utils.call(NPC.GetTimeToFacePosition, context.unit, targetPosition) or 0
	if faceTime > 0.055 then
		ControlAlly.Orders.face(context.controller, ControlAlly.Utils.normalized2D(origin, targetPosition), context.now)
		return nil
	end
	local id = ControlAlly.Utils.abilityName(best)
	return {
		ability = best,
		id = id,
		policy = "noTarget",
		score = 102 - bestError * 0.01,
		source = "ability",
		dedupeKey = id .. ":" .. tostring(ControlAlly.Utils.entityIndex(context.target) or -1),
	}
end

function ControlAlly.SpecialAI.dazzleAction(context)
	if
		(context.controller.profileName or context.controller.heroName) ~= "npc_dota_hero_dazzle"
		or ControlAlly.Utils.isNothlProjection(context.controller.unit)
	then
		return nil
	end
	local projection = XHelpers
		and XHelpers.XNPC
		and XHelpers.XNPC.GetNothlProjection
		and ControlAlly.Utils.call(XHelpers.XNPC.GetNothlProjection, XHelpers.XNPC, context.controller.unit)
	if ControlAlly.Utils.isValidControllerUnit(projection, true) then
		local start = ControlAlly.AbilityAI.findAbility(context.controller, "dazzle_nothl_projection", context.now)
		local minimumDuration = ControlAlly.Utils.specialValueExact(start, "min_duration", 0) or 0
		local maximumDuration = ControlAlly.Utils.specialValueExact(start, "max_duration", 0) or 0
		local leashStart = ControlAlly.Utils.specialValueExact(start, "leash_start", 0) or 0
		local elapsed = context.now - (context.controller.special.startedAt or context.now)
		local ownerPosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
		local projectionPosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, projection)
		local shouldEnd = ControlAlly.Utils.healthPct(projection) <= 24
			or (elapsed >= minimumDuration and not ControlAlly.Targeting.isValidEnemy(context.target))
			or (maximumDuration > 0 and elapsed + 0.20 >= maximumDuration)
			or (leashStart > 0 and ControlAlly.Utils.distance2D(ownerPosition, projectionPosition) >= leashStart * 0.90)
		if not shouldEnd then
			return nil
		end
		local finish = ControlAlly.AbilityAI.findAbility(context.controller, "dazzle_nothl_projection_end", context.now)
		if
			not ControlAlly.Menu.isAbilityEnabled("dazzle_nothl_projection")
			or not ControlAlly.AbilityAI.isReady(
				context.controller,
				finish,
				"dazzle_nothl_projection_end",
				true,
				false,
				true,
				true
			)
		then
			return nil
		end
		return {
			ability = finish,
			id = "dazzle_nothl_projection_end",
			policy = "noTarget",
			score = 198,
			urgent = true,
			source = "ability",
			allowRapid = true,
			specialStage = "dazzle_projection_end",
		}
	end
	if context.controller.special.stage == "dazzle_active" then
		context.controller.special.stage = nil
	end
	if not context.target then
		return nil
	end
	local ability = ControlAlly.SpecialAI.ready(context, "dazzle_nothl_projection", false)
	if not ability then
		return nil
	end
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
	local position = ControlAlly.Targeting.predictPosition(context.target, ability, {})
	local range = ControlAlly.AbilityAI.castRange(context.unit, ability, {})
	if ControlAlly.Utils.distance2D(origin, position) > range then
		position = ControlAlly.Utils.positionToward(origin, position, range)
	end
	return {
		ability = ability,
		id = "dazzle_nothl_projection",
		policy = "point",
		position = position,
		reservationTarget = context.target,
		score = 112,
		source = "ability",
		specialStage = "dazzle_projection",
	}
end

function ControlAlly.SpecialAI.morphlingAction(context)
	if (context.controller.profileName or context.controller.heroName) ~= "npc_dota_hero_morphling" then
		return nil
	end
	local state = context.controller.special
	if state.stage == "morph_copied" then
		local returnAbility =
			ControlAlly.AbilityAI.findAbility(context.controller, "morphling_morph_replicate", context.now)
		if
			context.now - state.startedAt > 1.0
			and (not returnAbility or ControlAlly.Utils.call(Ability.IsActivated, returnAbility) == false)
		then
			state.stage = nil
			ControlAlly.SpecialAI.invalidateCatalog(context.controller)
		elseif
			ControlAlly.Utils.healthPct(context.unit) > 30 and ControlAlly.Targeting.isValidEnemy(context.target)
		then
			return nil
		end
	end
	if state.stage == "morph_copied" then
		local finish = ControlAlly.SpecialAI.ready(context, "morphling_morph_replicate", true, true, true)
		if finish then
			return {
				ability = finish,
				id = "morphling_morph_replicate",
				policy = "noTarget",
				score = 190,
				urgent = true,
				source = "ability",
				allowRapid = true,
				specialStage = "morph_return",
			}
		end
		return nil
	end
	if not context.target then
		return nil
	end
	local replicate = ControlAlly.SpecialAI.ready(context, "morphling_replicate", false)
	if not replicate then
		return nil
	end
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
	local targetPosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.target)
	local range = ControlAlly.AbilityAI.castRange(context.unit, replicate, {})
	if ControlAlly.Utils.distance2D(origin, targetPosition) > range + ControlAlly.Constants.CAST_RANGE_BUFFER then
		return nil
	end
	return {
		ability = replicate,
		id = "morphling_replicate",
		policy = "enemy",
		target = context.target,
		reservationTarget = context.target,
		score = 114,
		source = "ability",
		specialStage = "morph_replicate",
	}
end

function ControlAlly.SpecialAI.earthSpiritAction(context)
	if (context.controller.profileName or context.controller.heroName) ~= "npc_dota_hero_earth_spirit" then
		return nil
	end
	local state = context.controller.special
	local target = ControlAlly.Targeting.isValidEnemy(context.target) and context.target or state.target
	if not ControlAlly.Targeting.isValidEnemy(target) then
		state.stage = nil
		state.followup = nil
		return nil
	end
	if state.stage == "earth_followup" and state.followup then
		local ability = ControlAlly.SpecialAI.ready(context, state.followup, false)
		if not ability then
			if context.now - state.startedAt > 0.75 then
				state.stage = nil
				state.followup = nil
			end
			return nil
		end
		local rule = ControlAlly.Profiles.Heroes.npc_dota_hero_earth_spirit.abilities[state.followup]
		return {
			ability = ability,
			id = state.followup,
			policy = "point",
			position = ControlAlly.Targeting.predictPosition(target, ability, rule),
			reservationTarget = target,
			score = 178,
			urgent = true,
			source = "ability",
			rule = {
				committedMotion = state.followup == "earth_spirit_rolling_boulder",
				projectileSpeedSpecial = "speed",
			},
			specialStage = "earth_followup",
			allowRapid = true,
		}
	end
	local stone = ControlAlly.SpecialAI.ready(context, "earth_spirit_stone_caller", false)
	if not stone then
		return nil
	end
	local followup
	for _, id in ipairs({
		"earth_spirit_rolling_boulder",
		"earth_spirit_boulder_smash",
		"earth_spirit_geomagnetic_grip",
	}) do
		if ControlAlly.SpecialAI.ready(context, id, false) then
			followup = id
			break
		end
	end
	if not followup then
		return nil
	end
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
	local predicted = ControlAlly.Targeting.predictPosition(target, stone, {})
	local range = ControlAlly.AbilityAI.castRange(context.unit, stone, {})
	local distance = ControlAlly.Utils.distance2D(origin, predicted)
	local position = predicted
	if followup == "earth_spirit_rolling_boulder" then
		position = ControlAlly.Utils.positionToward(origin, predicted, math.min(range, distance * 0.45))
	elseif followup == "earth_spirit_boulder_smash" then
		local smash = ControlAlly.AbilityAI.findAbility(context.controller, "earth_spirit_boulder_smash", context.now)
		local searchRadius = ControlAlly.Utils.specialValueExact(smash, "rock_search_aoe", range * 0.15) or range * 0.15
		position = ControlAlly.Utils.positionToward(origin, predicted, math.min(searchRadius * 0.85, distance))
	elseif distance > range then
		position = ControlAlly.Utils.positionToward(origin, predicted, range)
	end
	return {
		ability = stone,
		id = "earth_spirit_stone_caller",
		policy = "point",
		position = position,
		reservationTarget = target,
		score = 116,
		urgent = true,
		source = "ability",
		specialStage = "earth_stone",
		earthFollowup = followup,
	}
end

function ControlAlly.SpecialAI.pangolierAction(context)
	if
		(context.controller.profileName or context.controller.heroName) ~= "npc_dota_hero_pangolier"
		or not context.target
		or context.controller.special.stage == "pango_rolling"
	then
		return nil
	end
	local ability = ControlAlly.SpecialAI.ready(context, "pangolier_gyroshell", false)
	if not ability then
		return nil
	end
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
	local targetPosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.target)
	local faceTime = ControlAlly.Utils.call(NPC.GetTimeToFacePosition, context.unit, targetPosition) or 0
	if faceTime > 0.055 then
		ControlAlly.Orders.face(context.controller, ControlAlly.Utils.normalized2D(origin, targetPosition), context.now)
		return nil
	end
	return {
		ability = ability,
		id = "pangolier_gyroshell",
		policy = "noTarget",
		reservationTarget = context.target,
		score = 116,
		urgent = true,
		source = "ability",
		specialStage = "pango_roll_start",
	}
end

function ControlAlly.SpecialAI.oracleAction(context)
	if (context.controller.profileName or context.controller.heroName) ~= "npc_dota_hero_oracle" then
		return nil
	end
	local state = context.controller.special
	if state.stage == "oracle_flames" and ControlAlly.Utils.isValidHero(state.target, true) then
		local flames = ControlAlly.SpecialAI.ready(context, "oracle_purifying_flames", false)
		if flames then
			return {
				ability = flames,
				id = "oracle_purifying_flames",
				policy = "ally",
				target = state.target,
				reservationTarget = state.target,
				score = 188,
				urgent = true,
				source = "ability",
				specialStage = "oracle_flames",
				allowRapid = true,
			}
		end
		if context.now - state.startedAt > 0.75 then
			state.stage = nil
			state.target = nil
		end
		return nil
	end
	local edict = ControlAlly.SpecialAI.ready(context, "oracle_fates_edict", false)
	local flames = ControlAlly.SpecialAI.ready(context, "oracle_purifying_flames", false)
	local probe = edict or flames
	if probe then
		local ally = ControlAlly.AbilityAI.bestAllyTarget(context, probe, {
			allyMode = "heal",
			allyHealthPct = 70,
			allyModifiers = { "modifier_oracle_fates_edict" },
		})
		if ally then
			if ControlAlly.Utils.hasAnyModifier(ally, { "modifier_oracle_false_promise" }) and flames then
				return {
					ability = flames,
					id = "oracle_purifying_flames",
					policy = "ally",
					target = ally,
					reservationTarget = ally,
					score = 176,
					urgent = true,
					source = "ability",
					specialStage = "oracle_flames",
				}
			end
			if edict and flames then
				return {
					ability = edict,
					id = "oracle_fates_edict",
					policy = "ally",
					target = ally,
					reservationTarget = ally,
					score = 142,
					urgent = true,
					source = "ability",
					specialStage = "oracle_edict",
				}
			end
		end
	end
	if context.target then
		local fortune = ControlAlly.SpecialAI.ready(context, "oracle_fortunes_end", false)
		if fortune then
			local distance = ControlAlly.Utils.distance2D(
				ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit),
				ControlAlly.Utils.call(Entity.GetAbsOrigin, context.target)
			)
			if
				distance <= ControlAlly.AbilityAI.castRange(context.unit, fortune, {})
				and ControlAlly.Utils.call(NPC.IsLinkensProtected, context.target) ~= true
				and ControlAlly.AbilityAI.unitTargetIsSafe(context.target, false)
			then
				return {
					ability = fortune,
					id = "oracle_fortunes_end",
					policy = "enemy",
					target = context.target,
					reservationTarget = context.target,
					score = 88,
					source = "ability",
				}
			end
		end
	end
	return nil
end

function ControlAlly.SpecialAI.pugnaAction(context)
	if
		(context.controller.profileName or context.controller.heroName) ~= "npc_dota_hero_pugna"
		or not context.target
		or ControlAlly.Utils.isMagicImmune(context.target)
	then
		return nil
	end
	local state = context.controller.special
	local target = ControlAlly.Targeting.isValidEnemy(state.target) and state.target or context.target
	if
		ControlAlly.Utils.call(NPC.IsLinkensProtected, target) == true
		or not ControlAlly.AbilityAI.unitTargetIsSafe(target, false)
	then
		state.stage = nil
		state.target = nil
		return nil
	end
	local function inRange(ability)
		return ability
			and ControlAlly.Utils.distance2D(
					ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit),
					ControlAlly.Utils.call(Entity.GetAbsOrigin, target)
				)
				<= ControlAlly.AbilityAI.castRange(context.unit, ability, {}) + ControlAlly.Constants.CAST_RANGE_BUFFER
	end
	local drain = ControlAlly.SpecialAI.ready(context, "pugna_life_drain", false)
	if state.stage == "pugna_drain" then
		if inRange(drain) then
			return {
				ability = drain,
				id = "pugna_life_drain",
				policy = "enemy",
				target = target,
				reservationTarget = target,
				score = 184,
				urgent = true,
				source = "ability",
				specialStage = "pugna_drain",
				allowRapid = true,
			}
		end
		state.stage = nil
	end
	local decrepify = ControlAlly.SpecialAI.ready(context, "pugna_decrepify", false)
	if
		inRange(decrepify)
		and drain
		and not ControlAlly.Utils.hasAnyModifier(target, { "modifier_pugna_decrepify" })
	then
		return {
			ability = decrepify,
			id = "pugna_decrepify",
			policy = "enemy",
			target = target,
			reservationTarget = target,
			score = 126,
			source = "ability",
			specialStage = "pugna_decrepify",
		}
	end
	if inRange(drain) then
		return {
			ability = drain,
			id = "pugna_life_drain",
			policy = "enemy",
			target = target,
			reservationTarget = target,
			score = 112,
			source = "ability",
			specialStage = "pugna_drain",
		}
	end
	return nil
end

function ControlAlly.SpecialAI.winterWyvernAction(context)
	if
		(context.controller.profileName or context.controller.heroName) ~= "npc_dota_hero_winter_wyvern"
		or not context.target
	then
		return nil
	end
	local ability = ControlAlly.SpecialAI.ready(context, "winter_wyvern_splinter_blast", false)
	if not ability then
		return nil
	end
	local targetPosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.target)
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
	local splitRadius = ControlAlly.Utils.specialValueExact(ability, "split_radius", 0) or 0
	local range = ControlAlly.AbilityAI.castRange(context.unit, ability, {})
	local team = ControlAlly.Utils.call(Entity.GetTeamNum, context.unit)
	local carriers = team
			and ControlAlly.Utils.call(
				NPCs.InRadius,
				targetPosition,
				splitRadius,
				team,
				Enum.TeamType.TEAM_ENEMY,
				false,
				true
			)
		or {}
	local best
	local bestDistance = math.huge
	for _, carrier in ipairs(carriers) do
		local position = ControlAlly.Utils.call(Entity.GetAbsOrigin, carrier)
		local distance = ControlAlly.Utils.distance2D(origin, position)
		if
			carrier ~= context.target
			and distance <= range + ControlAlly.Constants.CAST_RANGE_BUFFER
			and ControlAlly.Utils.call(NPC.IsLinkensProtected, carrier) ~= true
			and ControlAlly.AbilityAI.unitTargetIsSafe(carrier, false)
			and distance < bestDistance
		then
			best = carrier
			bestDistance = distance
		end
	end
	if not best then
		return nil
	end
	return {
		ability = ability,
		id = "winter_wyvern_splinter_blast",
		policy = "enemy",
		target = best,
		reservationTarget = context.target,
		score = 92,
		source = "ability",
	}
end

function ControlAlly.SpecialAI.controlActiveMotion(context)
	if (context.controller.profileName or context.controller.heroName) ~= "npc_dota_hero_pangolier" then
		return false
	end
	local state = context.controller.special
	local rolling = ControlAlly.Utils.hasAnyModifier(context.unit, {
		"modifier_pangolier_gyroshell",
		"modifier_pangolier_gyroshell_ricochet",
	})
	if state.stage ~= "pango_rolling" and not rolling then
		return false
	end
	if not rolling and context.now - state.startedAt > 0.35 then
		state.stage = nil
		state.target = nil
		return false
	end
	local target = ControlAlly.Targeting.isValidEnemy(context.target) and context.target or state.target
	if ControlAlly.Targeting.isValidEnemy(target) then
		local position = ControlAlly.Targeting.predictPosition(target, nil, {})
		ControlAlly.Orders.move(context.controller, position, context.now)
	end
	return true
end

function ControlAlly.SpecialAI.smartUltimateAction(context)
	local profileName = context.controller.profileName or context.controller.heroName
	local target = context.target
	local function inRange(ability, unitTarget)
		return ability
			and unitTarget
			and ControlAlly.Utils.distance2D(
					ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit),
					ControlAlly.Utils.call(Entity.GetAbsOrigin, unitTarget)
				)
				<= ControlAlly.AbilityAI.castRange(context.unit, ability, {}) + ControlAlly.Constants.CAST_RANGE_BUFFER
	end
	local function directTargetIsSafe(unitTarget, allowMagicImmune)
		return unitTarget
			and (allowMagicImmune or not ControlAlly.Utils.isMagicImmune(unitTarget))
			and ControlAlly.Utils.call(NPC.IsLinkensProtected, unitTarget) ~= true
			and ControlAlly.AbilityAI.unitTargetIsSafe(unitTarget, false)
	end
	if profileName == "npc_dota_hero_axe" and target then
		local ability = ControlAlly.SpecialAI.ready(context, "axe_culling_blade", false)
		local damage = ability and ControlAlly.Utils.specialValueExact(ability, "damage", 0) or 0
		if
			inRange(ability, target)
			and directTargetIsSafe(target, true)
			and damage > 0
			and (ControlAlly.Utils.call(Entity.GetHealth, target) or math.huge) <= damage
		then
			return {
				ability = ability,
				id = "axe_culling_blade",
				policy = "enemy",
				target = target,
				reservationTarget = target,
				score = 190,
				urgent = true,
				source = "ability",
			}
		end
	elseif profileName == "npc_dota_hero_necrolyte" and target then
		local ability = ControlAlly.SpecialAI.ready(context, "necrolyte_reapers_scythe", false)
		if ability then
			local health = ControlAlly.Utils.call(Entity.GetHealth, target) or math.huge
			local maxHealth = ControlAlly.Utils.call(Entity.GetMaxHealth, target) or health
			local damagePerHealth = ControlAlly.Utils.specialValueExact(ability, "damage_per_health", 0) or 0
			local magicMultiplier = ControlAlly.Utils.call(NPC.GetMagicalArmorDamageMultiplier, target) or 1
			local projectedDamage = math.max(0, maxHealth - health) * damagePerHealth * magicMultiplier
			if inRange(ability, target) and directTargetIsSafe(target, false) and projectedDamage >= health then
				return {
					ability = ability,
					id = "necrolyte_reapers_scythe",
					policy = "enemy",
					target = target,
					reservationTarget = target,
					score = 184,
					urgent = true,
					source = "ability",
				}
			end
		end
	elseif profileName == "npc_dota_hero_zuus" then
		local ability = ControlAlly.SpecialAI.ready(context, "zuus_thundergods_wrath", false)
		if ability then
			local damage = ControlAlly.Utils.specialValueExact(ability, "damage", 0) or 0
			local lethal = 0
			local pressured = 0
			for _, enemy in ipairs(ControlAlly.Runtime.enemies) do
				local health = ControlAlly.Utils.call(Entity.GetHealth, enemy) or math.huge
				local magicMultiplier = ControlAlly.Utils.call(NPC.GetMagicalArmorDamageMultiplier, enemy) or 1
				if not ControlAlly.Utils.isMagicImmune(enemy) and damage > 0 and health <= damage * magicMultiplier then
					lethal = lethal + 1
				end
				if not ControlAlly.Utils.isMagicImmune(enemy) and ControlAlly.Utils.healthPct(enemy) <= 55 then
					pressured = pressured + 1
				end
			end
			if lethal > 0 or pressured >= 2 then
				return {
					ability = ability,
					id = "zuus_thundergods_wrath",
					policy = "noTarget",
					score = 170 + lethal * 12,
					urgent = lethal > 0,
					source = "ability",
				}
			end
		end
	elseif profileName == "npc_dota_hero_earthshaker" and target then
		local totem = ControlAlly.SpecialAI.ready(context, "earthshaker_enchant_totem", false)
		if
			totem
			and ControlAlly.Utils.call(NPC.HasScepter, context.unit) == true
			and not ControlAlly.Utils.hasAnyModifier(context.unit, { "modifier_earthshaker_enchant_totem" })
		then
			local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
			local targetPosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, target)
			local leapRange = ControlAlly.Utils.specialValueExact(totem, "distance_scepter", 950) or 950
			if origin and targetPosition then
				local leapDistance = ControlAlly.Utils.distance2D(origin, targetPosition)
				if leapDistance > 175 and leapDistance <= leapRange + 50 then
					return {
						ability = totem,
						id = "earthshaker_enchant_totem",
						policy = "point",
						position = ControlAlly.Utils.positionToward(
							origin,
							targetPosition,
							math.max(0, leapDistance - 100)
						),
						score = 130,
						urgent = leapDistance > 350,
						source = "ability",
					}
				end
			end
		end
		local ability = ControlAlly.SpecialAI.ready(context, "earthshaker_echo_slam", false)
		if ability then
			local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
			local radius = ControlAlly.Utils.specialValueExact(ability, "echo_slam_echo_search_range", 0) or 0
			local team = ControlAlly.Utils.call(Entity.GetTeamNum, context.unit)
			local units = team
					and ControlAlly.Utils.call(
						NPCs.InRadius,
						origin,
						radius,
						team,
						Enum.TeamType.TEAM_ENEMY,
						false,
						true
					)
				or {}
			local heroes = 0
			local total = 0
			for _, unit in ipairs(units) do
				if
					ControlAlly.Utils.call(Entity.IsAlive, unit) == true
					and not ControlAlly.Utils.isMagicImmune(unit)
				then
					total = total + 1
					heroes = heroes + (ControlAlly.Utils.call(NPC.IsHero, unit) == true and 1 or 0)
				end
			end
			if heroes >= 1 or total >= 3 then
				return {
					ability = ability,
					id = "earthshaker_echo_slam",
					policy = "noTarget",
					score = 178 + math.min(total, 8) * 4,
					urgent = true,
					source = "ability",
				}
			end
		end
	elseif profileName == "npc_dota_hero_lich" and target then
		local ability = ControlAlly.SpecialAI.ready(context, "lich_chain_frost", false)
		if ability then
			local jumpRange = ControlAlly.Utils.specialValueExact(ability, "jump_range", 0) or 0
			if
				inRange(ability, target)
				and directTargetIsSafe(target, false)
				and ControlAlly.Targeting.clusterCount(target, jumpRange) >= 2
			then
				return {
					ability = ability,
					id = "lich_chain_frost",
					policy = "enemy",
					target = target,
					reservationTarget = target,
					score = 174,
					urgent = true,
					source = "ability",
				}
			end
		end
	elseif profileName == "npc_dota_hero_winter_wyvern" and target then
		local ability = ControlAlly.SpecialAI.ready(context, "winter_wyvern_winters_curse", false)
		if ability then
			local radius = ControlAlly.Utils.specialValueExact(ability, "radius", 0) or 0
			if
				inRange(ability, target)
				and directTargetIsSafe(target, true)
				and ControlAlly.Targeting.clusterCount(target, radius) >= 2
			then
				return {
					ability = ability,
					id = "winter_wyvern_winters_curse",
					policy = "enemy",
					target = target,
					reservationTarget = target,
					score = 180,
					urgent = true,
					source = "ability",
				}
			end
		end
	elseif profileName == "npc_dota_hero_shadow_shaman" and target then
		local ability = ControlAlly.SpecialAI.ready(context, "shadow_shaman_mass_serpent_ward", false)
		if ability then
			local radius = ControlAlly.Utils.specialValueExact(ability, "spawn_radius", 0) or 0
			if
				inRange(ability, target)
				and (
					ControlAlly.Targeting.clusterCount(
							target,
							math.max(radius * 3, ControlAlly.Constants.DEFAULT_POINT_RADIUS)
						)
						>= 2
					or ControlAlly.Utils.healthPct(target) <= 42
				)
			then
				return {
					ability = ability,
					id = "shadow_shaman_mass_serpent_ward",
					policy = "point",
					position = ControlAlly.Targeting.predictPosition(target, ability, {}),
					reservationTarget = target,
					score = 172,
					urgent = true,
					source = "ability",
				}
			end
		end
	end
	return nil
end

function ControlAlly.SpecialAI.stormBallAction(context, currentAction)
	if
		currentAction
		or not ControlAlly.UI.UseAbilities
		or ControlAlly.UI.UseAbilities:Get() ~= true
		or (context.controller.profileName or context.controller.heroName) ~= "npc_dota_hero_storm_spirit"
		or not context.target
		or context.now - context.controller.special.lastBallAt < 1.0
	then
		return nil
	end
	local ability = ControlAlly.SpecialAI.ready(context, "storm_spirit_ball_lightning", false)
	if not ability then
		return nil
	end
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
	local targetPosition = ControlAlly.Targeting.predictPosition(context.target, ability, {})
	if not origin or not targetPosition then
		return nil
	end
	local attackRange = ControlAlly.Utils.call(NPC.GetAttackRange, context.unit) or 150
	local distance = ControlAlly.Utils.distance2D(origin, targetPosition)
	local engagementRadius = attackRange + 260
	if distance <= engagementRadius then
		return nil
	end
	local maximumMana = ControlAlly.Utils.call(NPC.GetMaxMana, context.unit) or 0
	local currentMana = ControlAlly.Utils.call(NPC.GetMana, context.unit) or 0
	local initialBase = ControlAlly.Utils.specialValueExact(ability, "ball_lightning_initial_mana_base", 0) or 0
	local initialPercent = ControlAlly.Utils.specialValueExact(ability, "ball_lightning_initial_mana_percentage", 0)
		or 0
	local travelBase = ControlAlly.Utils.specialValueExact(ability, "ball_lightning_travel_cost_base", 0) or 0
	local travelPercent = ControlAlly.Utils.specialValueExact(ability, "ball_lightning_travel_cost_percent", 0) or 0
	local reserveMana = 0
	for _, id in ipairs({ "storm_spirit_static_remnant", "storm_spirit_electric_vortex" }) do
		local followup = ControlAlly.AbilityAI.findAbility(context.controller, id, context.now)
		if followup and (ControlAlly.Utils.call(Ability.GetLevel, followup) or 0) > 0 then
			reserveMana = reserveMana + (ControlAlly.Utils.call(Ability.GetManaCost, followup) or 0)
			if id == "storm_spirit_electric_vortex" then
				engagementRadius =
					math.max(engagementRadius, ControlAlly.AbilityAI.castRange(context.unit, followup, {}))
			end
		end
	end
	local initialCost = initialBase + maximumMana * initialPercent * 0.01
	local travelCostPerHundred = travelBase + maximumMana * travelPercent * 0.01
	if travelCostPerHundred <= 0 then
		return nil
	end
	local affordableTravelMana = currentMana - initialCost - reserveMana
	local affordableDistance = math.max(0, math.floor(affordableTravelMana / travelCostPerHundred) * 100)
	if affordableDistance <= 0 or distance - affordableDistance > engagementRadius then
		return nil
	end
	local landingPosition = targetPosition
	if distance > affordableDistance then
		landingPosition = ControlAlly.Utils.positionToward(origin, targetPosition, affordableDistance)
	end
	return {
		ability = ability,
		id = "storm_spirit_ball_lightning",
		policy = "point",
		position = landingPosition,
		score = 30,
		source = "ability",
		committedMotion = true,
		rule = { projectileSpeedSpecial = "ball_lightning_move_speed" },
		specialStage = "storm_ball",
	}
end

function ControlAlly.SpecialAI.bestAction(context)
	if not ControlAlly.UI.UseAbilities or ControlAlly.UI.UseAbilities:Get() ~= true then
		return nil
	end
	local best
	local function consider(action)
		if action and (not best or action.score > best.score) then
			best = action
		end
	end
	consider(ControlAlly.TechiesAI.mineAction(context))
	consider(ControlAlly.SpecialAI.loneDruidAction(context))
	consider(ControlAlly.SpecialAI.spectreAction(context))
	consider(ControlAlly.SpecialAI.emberAction(context))
	consider(ControlAlly.SpecialAI.hoodwinkAction(context))
	consider(ControlAlly.SpecialAI.monkeyAction(context))
	consider(ControlAlly.SpecialAI.marciAction(context))
	consider(ControlAlly.SpecialAI.dawnbreakerAction(context))
	consider(ControlAlly.SpecialAI.ancientApparitionAction(context))
	consider(ControlAlly.SpecialAI.shadowFiendAction(context))
	consider(ControlAlly.SpecialAI.dazzleAction(context))
	consider(ControlAlly.SpecialAI.morphlingAction(context))
	consider(ControlAlly.SpecialAI.earthSpiritAction(context))
	consider(ControlAlly.SpecialAI.pangolierAction(context))
	consider(ControlAlly.SpecialAI.oracleAction(context))
	consider(ControlAlly.SpecialAI.pugnaAction(context))
	consider(ControlAlly.SpecialAI.winterWyvernAction(context))
	consider(ControlAlly.SpecialAI.smartUltimateAction(context))
	consider(ControlAlly.KezAI.switchAction(context))
	return best
end

function ControlAlly.SpecialAI.onCastResult(controller, pending, success, now)
	local stage = pending.specialStage
	local profileName = controller.profileName or controller.heroName
	if profileName == "npc_dota_hero_kez" and success and pending.source == "ability" then
		if stage == "kez_switch" then
			controller.kez.lastSwitchAt = now
			controller.kez.castsAfterSwitch = 0
			ControlAlly.SpecialAI.invalidateCatalog(controller)
		elseif pending.id ~= "kez_switch_weapons" then
			controller.kez.formCasts[pending.id] = now
			controller.kez.castsAfterSwitch = controller.kez.castsAfterSwitch + 1
		end
	end
	if not stage then
		return
	end
	if not success then
		if stage ~= "storm_ball" then
			controller.special.stage = nil
		end
		return
	end
	if stage == "spectre_open" then
		controller.special.stage = "spectre_reality"
		controller.special.target = pending.castTarget
		controller.special.startedAt = now
		ControlAlly.SpecialAI.invalidateCatalog(controller)
	elseif stage == "spectre_reality" or stage == "ember_activate" or stage == "monkey_spring" then
		controller.special.stage = nil
		controller.special.target = nil
		ControlAlly.SpecialAI.invalidateCatalog(controller)
	elseif stage == "ember_place" then
		controller.special.stage = "ember_activate"
		controller.special.target = pending.castTarget
		controller.special.startedAt = now
		ControlAlly.SpecialAI.invalidateCatalog(controller)
	elseif stage == "monkey_tree" then
		controller.special.stage = "monkey_spring"
		controller.special.target = pending.castTarget
		controller.special.startedAt = now
		ControlAlly.SpecialAI.invalidateCatalog(controller)
	elseif stage == "lone_summon" or stage == "dawn_converge" then
		ControlAlly.SpecialAI.invalidateCatalog(controller)
	elseif stage == "storm_ball" then
		controller.special.lastBallAt = now
	elseif stage == "aa_launch" then
		controller.special.stage = "aa_release"
		controller.special.target = pending.castTarget
		controller.special.startedAt = now + (pending.specialTravelTime or 0)
		ControlAlly.SpecialAI.invalidateCatalog(controller)
	elseif stage == "aa_release" then
		controller.special.stage = nil
		ControlAlly.SpecialAI.invalidateCatalog(controller)
	elseif stage == "dazzle_projection" then
		controller.special.stage = "dazzle_active"
		controller.special.startedAt = now
		ControlAlly.SpecialAI.invalidateCatalog(controller)
	elseif stage == "dazzle_projection_end" then
		controller.special.stage = nil
		controller.special.target = nil
		ControlAlly.SpecialAI.invalidateCatalog(controller)
	elseif stage == "morph_replicate" then
		controller.special.stage = "morph_copied"
		controller.special.startedAt = now
		ControlAlly.SpecialAI.invalidateCatalog(controller)
	elseif stage == "morph_return" then
		controller.special.stage = nil
		ControlAlly.SpecialAI.invalidateCatalog(controller)
	elseif stage == "earth_stone" then
		controller.special.stage = "earth_followup"
		controller.special.followup = pending.earthFollowup
		controller.special.target = pending.castTarget
		controller.special.startedAt = now
	elseif stage == "earth_followup" then
		controller.special.stage = nil
		controller.special.followup = nil
		controller.special.target = nil
	elseif stage == "pango_roll_start" then
		controller.special.stage = "pango_rolling"
		controller.special.target = pending.castTarget
		controller.special.startedAt = now
	elseif stage == "oracle_edict" then
		controller.special.stage = "oracle_flames"
		controller.special.target = pending.castTarget
		controller.special.startedAt = now
	elseif stage == "oracle_flames" then
		controller.special.stage = nil
		controller.special.target = nil
	elseif stage == "pugna_decrepify" then
		controller.special.stage = "pugna_drain"
		controller.special.target = pending.castTarget
		controller.special.startedAt = now
	elseif stage == "pugna_drain" then
		controller.special.stage = nil
		controller.special.target = nil
	end
end

function ControlAlly.SpecialAI.finishManagedActions(now)
	for _, controller in pairs(ControlAlly.Runtime.controllerStates) do
		if
			(controller.profileName or controller.heroName) == "npc_dota_hero_ancient_apparition"
			and controller.special.stage == "aa_release"
			and ControlAlly.Utils.isValidControllerUnit(controller.unit, true)
		then
			ControlAlly.Combat.confirmPendingCast(controller, now)
			if
				not controller.pendingCast
				and now >= (controller.busyUntil or -math.huge)
				and ControlAlly.Utils.protectedActivity(controller.unit, controller.activeAbility) == nil
			then
				local action = ControlAlly.SpecialAI.ancientApparitionAction({
					controller = controller,
					unit = controller.unit,
					target = controller.special.target,
					now = now,
				})
				if action and action.id == "ancient_apparition_ice_blast_release" then
					return ControlAlly.Orders.cast(controller, action, now)
				end
			end
		end
	end
	return false
end

function ControlAlly.SpecialAI.handleLockedChannel(controller, now)
	local pending = controller.pendingCast
	if not pending or not pending.wasChanneling or pending.releaseIssued then
		return false
	end
	local releaseByStage = {
		hood_sharpshooter = "hoodwink_sharpshooter_release",
		ringmaster_tame = "ringmaster_tame_the_beasts_crack",
	}
	local releaseId = releaseByStage[pending.specialStage]
	if not releaseId then
		return false
	end
	local duration = pending.channelTime or 0
	if duration <= 0 then
		duration = ControlAlly.Utils.specialValue(
			pending.ability,
			{ "max_charge_time", "AbilityChannelTime", "channel_time" },
			0
		)
	end
	if duration <= 0 or now - (pending.channelStartedAt or pending.issuedAt) + 0.06 < duration then
		return false
	end
	local release = ControlAlly.AbilityAI.findAbility(controller, releaseId, now)
	if not ControlAlly.AbilityAI.isReady(controller, release, releaseId, true, false, true, true) then
		return false
	end
	if
		ControlAlly.Orders.issue(
			controller,
			Enum.UnitOrder.DOTA_UNIT_ORDER_CAST_NO_TARGET,
			nil,
			nil,
			release,
			"release_" .. releaseId,
			true,
			0.03
		)
	then
		pending.releaseIssued = true
		pending.allowEarlyEnd = true
		return true
	end
	return false
end

function ControlAlly.InvokerAI.orbsAreLearned(controller, rule, now)
	local checked = {}
	for _, orbId in ipairs(rule.orbs or {}) do
		if not checked[orbId] then
			checked[orbId] = true
			local orb = ControlAlly.AbilityAI.findAbility(controller, orbId, now)
			if not orb or (ControlAlly.Utils.call(Ability.GetLevel, orb) or 0) <= 0 then
				return false
			end
		end
	end
	return true
end

function ControlAlly.InvokerAI.invokedAbility(controller, spellId, now)
	for _, entry in ipairs(ControlAlly.AbilityAI.catalog(controller, now).abilities) do
		if entry.id == spellId and ControlAlly.Utils.call(Ability.IsHidden, entry.ability) ~= true then
			return entry.ability
		end
	end
	return nil
end

function ControlAlly.InvokerAI.hiddenSpellIsReady(controller, ability, rule)
	if not ability or ControlAlly.Utils.cooldownRemaining(ability) > 0.03 then
		return false
	end
	if Ability.IsInIndefinateCooldown and ControlAlly.Utils.call(Ability.IsInIndefinateCooldown, ability) == true then
		return false
	end
	local mana = ControlAlly.Utils.call(NPC.GetMana, controller.unit) or 0
	local cost = ControlAlly.Utils.call(Ability.GetManaCost, ability) or 0
	return mana >= cost and ControlAlly.InvokerAI.orbsAreLearned(controller, rule, ControlAlly.Utils.gameTime())
end

function ControlAlly.InvokerAI.spellScore(context, ability, spellId, rule, invoked)
	local usable = rule.policy == "iceWall" and ControlAlly.AbilityAI.rulePasses(context, ability, rule)
		or ControlAlly.AbilityAI.wouldBeUsableIfReady(context, ability, rule)
	if
		not ControlAlly.Menu.isAbilityEnabled(spellId)
		or not ControlAlly.InvokerAI.hiddenSpellIsReady(context.controller, ability, rule)
		or not usable
	then
		return nil
	end
	if rule.policy ~= "self" and rule.policy ~= "noTarget" and not context.target then
		return nil
	end
	if
		context.target
		and ControlAlly.Utils.isMagicImmune(context.target)
		and not rule.allowMagicImmune
		and (rule.policy == "enemy" or rule.policy == "point")
	then
		return nil
	end
	if
		rule.policy == "enemy"
		and context.target
		and not ControlAlly.AbilityAI.unitTargetIsSafe(context.target, false)
	then
		return nil
	end
	if
		rule.policy == "enemy"
		and context.target
		and ControlAlly.Utils.call(NPC.IsLinkensProtected, context.target) == true
	then
		return nil
	end
	if context.target and rule.targetModifiers then
		local targetIndex = ControlAlly.Utils.entityIndex(context.target)
		local key = targetIndex and (tostring(targetIndex) .. ":" .. spellId)
		if key and (ControlAlly.Runtime.effectReservations[key] or -math.huge) > context.now then
			return nil
		end
	end
	if rule.disable and context.target then
		local targetIndex = ControlAlly.Utils.entityIndex(context.target)
		if
			ControlAlly.Targeting.hardDisableRemaining(context.target) > 0.32
			or (targetIndex and (ControlAlly.Runtime.disableReservations[targetIndex] or -math.huge) > context.now)
		then
			return nil
		end
	end

	local score = rule.priority or 60
	if invoked then
		score = score + 14
	end
	if context.target then
		local healthPct = ControlAlly.Utils.healthPct(context.target)
		if rule.preferLowHealth then
			score = score + (100 - healthPct) * 0.40
		end
		if rule.preferDisabledTarget and ControlAlly.Targeting.hardDisableRemaining(context.target) > 0.15 then
			score = score + 28
		end
		if spellId == "invoker_sun_strike" then
			local damage = ControlAlly.Utils.call(Ability.GetDamage, ability) or 0
			if damage <= 0 then
				damage = ControlAlly.Utils.specialValue(ability, { "damage" }, 0)
			end
			if damage >= (ControlAlly.Utils.call(Entity.GetHealth, context.target) or math.huge) then
				score = score + 75
			end
		end
	end
	return score
end

function ControlAlly.InvokerAI.prepareSpecificSpell(context, spellId, rule)
	local controller = context.controller
	local state = controller.invoker
	if ControlAlly.InvokerAI.invokedAbility(controller, spellId, context.now) then
		return nil, "ready"
	end
	local invoke = ControlAlly.AbilityAI.findAbility(controller, "invoker_invoke", context.now)
	if not ControlAlly.AbilityAI.isReady(controller, invoke, "invoker_invoke", false, false) then
		return nil, "waiting"
	end
	local spell = ControlAlly.AbilityAI.findAbility(controller, spellId, context.now)
	local mana = ControlAlly.Utils.call(NPC.GetMana, controller.unit) or 0
	local requiredMana = (ControlAlly.Utils.call(Ability.GetManaCost, invoke) or 0)
		+ (ControlAlly.Utils.call(Ability.GetManaCost, spell) or 0)
	if mana < requiredMana then
		return nil, "waiting"
	end
	if state.spellId ~= spellId then
		state.spellId = spellId
		state.orbIndex = 1
		state.nextStepAt = context.now
	end
	if context.now < state.nextStepAt or context.now < state.waitUntil then
		return nil, "preparing"
	end
	local orbs = rule.orbs or {}
	local actualCounts, actualTotal = ControlAlly.InvokerAI.orbCounts(controller)
	local desiredCounts = ControlAlly.InvokerAI.desiredOrbCounts(rule)
	local countTracking = actualTotal > 0
	if countTracking and ControlAlly.InvokerAI.orbsMatch(actualCounts, desiredCounts) then
		state.orbIndex = #orbs + 1
	end
	if state.orbIndex <= #orbs then
		local orbId
		if countTracking then
			for _, candidateId in ipairs({ "invoker_quas", "invoker_wex", "invoker_exort" }) do
				if actualCounts[candidateId] < desiredCounts[candidateId] then
					orbId = candidateId
					break
				end
			end
		end
		orbId = orbId or orbs[state.orbIndex]
		local orb = ControlAlly.AbilityAI.findAbility(controller, orbId, context.now)
		if not ControlAlly.AbilityAI.isReady(controller, orb, orbId, false, false) then
			return nil, "waiting"
		end
		return ControlAlly.InvokerAI.internalAction(
			orb,
			orbId,
			"orb",
			string.format("invoke:%s:orb:%s:%d", spellId, orbId, state.orbIndex),
			{
				spellId = spellId,
				countTracking = countTracking,
				orbSignatureBefore = ControlAlly.InvokerAI.orbSignature(controller),
			}
		),
			"preparing"
	end
	return ControlAlly.InvokerAI.internalAction(
		invoke,
		"invoker_invoke",
		"invoke",
		"invoke:" .. spellId,
		{ spellId = spellId }
	),
		"preparing"
end

function ControlAlly.InvokerAI.comboImpactDelay(context, ability, rule)
	local castPoint = ControlAlly.Utils.call(Ability.GetCastPoint, ability, true)
		or ControlAlly.Utils.call(Ability.GetCastPoint, ability)
		or 0
	local delay = ControlAlly.Utils.ruleValue(ability, rule, "lead", "delaySpecial", 0) or 0
	local targetPosition = context.target and ControlAlly.Utils.call(Entity.GetAbsOrigin, context.target)
	local faceTime = targetPosition and ControlAlly.Utils.call(NPC.GetTimeToFacePosition, context.unit, targetPosition)
		or 0
	faceTime = type(faceTime) == "number" and math.max(0, faceTime) or 0
	local speed = ControlAlly.Utils.ruleValue(ability, rule, "projectileSpeed", "projectileSpeedSpecial", 0) or 0
	if delay <= 0 and speed > 0 and context.target then
		local distance = ControlAlly.Utils.distance2D(
			ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit),
			ControlAlly.Utils.call(Entity.GetAbsOrigin, context.target)
		)
		if distance < math.huge then
			delay = distance / speed
		end
	end
	return faceTime + castPoint + math.max(0, delay)
end

function ControlAlly.InvokerAI.selectComboSpell(context, combo)
	local candidates = {
		{ id = "invoker_sun_strike", score = 96 },
		{ id = "invoker_chaos_meteor", score = 106 },
		{ id = "invoker_emp", score = 88 },
		{ id = "invoker_deafening_blast", score = 92 },
	}
	local best
	for _, candidate in ipairs(candidates) do
		local rule = ControlAlly.Profiles.InvokerSpells[candidate.id]
		local ability = ControlAlly.AbilityAI.findAbility(context.controller, candidate.id, context.now)
		if
			rule
			and ControlAlly.Menu.isAbilityEnabled(candidate.id)
			and ControlAlly.InvokerAI.hiddenSpellIsReady(context.controller, ability, rule)
			and ControlAlly.AbilityAI.wouldBeUsableIfReady(context, ability, rule)
			and (not rule.targetManaMinPct or ControlAlly.Utils.manaPct(context.target) >= rule.targetManaMinPct)
		then
			local impactDelay = ControlAlly.InvokerAI.comboImpactDelay(context, ability, rule)
			local issueAt = combo.landingAt - impactDelay + ControlAlly.Constants.INVOKER_COMBO_CAST_TOLERANCE
			local score = candidate.score
			if candidate.id == "invoker_sun_strike" then
				score = score + (100 - ControlAlly.Utils.healthPct(context.target)) * 0.35
				local damage = ControlAlly.Utils.specialValue(ability, { "damage" }, 0)
				if damage >= (ControlAlly.Utils.call(Entity.GetHealth, context.target) or math.huge) then
					score = score + 80
				end
			elseif candidate.id == "invoker_chaos_meteor" then
				local radius = ControlAlly.AbilityAI.radius(ability, rule)
				local targetPosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.target)
				for _, enemy in ipairs(ControlAlly.Runtime.enemies) do
					if
						enemy ~= context.target
						and ControlAlly.Utils.distance2D(
								targetPosition,
								ControlAlly.Utils.call(Entity.GetAbsOrigin, enemy)
							)
							<= radius
					then
						score = score + 18
					end
				end
			elseif candidate.id == "invoker_emp" then
				score = score + ControlAlly.Utils.manaPct(context.target) * 0.35
			end
			local invoked = ControlAlly.InvokerAI.invokedAbility(context.controller, candidate.id, context.now) ~= nil
			local invoke = ControlAlly.AbilityAI.findAbility(context.controller, "invoker_invoke", context.now)
			local requiredMana = (ControlAlly.Utils.call(Ability.GetManaCost, ability) or 0)
				+ (invoked and 0 or (ControlAlly.Utils.call(Ability.GetManaCost, invoke) or 0))
			local preparationTime = ControlAlly.Constants.INVOKER_POST_INVOKE_WAIT
				+ #(rule.orbs or {}) * ControlAlly.Constants.INVOKER_ORB_GAP
				+ ControlAlly.Constants.ORDER_GAP
			if
				context.now <= issueAt + ControlAlly.Constants.INVOKER_COMBO_LATE_TOLERANCE
				and (ControlAlly.Utils.call(NPC.GetMana, context.unit) or 0) >= requiredMana
				and (invoked or issueAt - context.now >= preparationTime)
				and (not best or score > best.score)
			then
				best = {
					id = candidate.id,
					ability = ability,
					rule = rule,
					issueAt = issueAt,
					score = score,
				}
			end
		end
	end
	return best
end

function ControlAlly.InvokerAI.comboAction(context)
	local combo = context.controller.invoker.combo
	if not combo then
		return nil, nil
	end
	if
		combo.target ~= context.target
		or not ControlAlly.Targeting.isValidEnemy(combo.target)
		or ControlAlly.Utils.isMagicImmune(combo.target)
	then
		context.controller.invoker.combo = nil
		return nil, nil
	end
	local exactRemaining = ControlAlly.Utils.modifierRemaining(combo.target, "modifier_invoker_tornado", context.now)
	if exactRemaining > 0 then
		combo.landingAt = context.now + exactRemaining
		combo.sawLift = true
	elseif
		not combo.sawLift
		and context.now > (combo.expectedImpactAt or math.huge) + ControlAlly.Constants.INVOKER_TORNADO_HIT_GRACE
	then
		context.controller.invoker.combo = nil
		return nil, nil
	elseif combo.sawLift and context.now > combo.landingAt + ControlAlly.Constants.INVOKER_COMBO_FINISH_GRACE then
		context.controller.invoker.combo = nil
		return nil, nil
	end
	if not combo.followup then
		combo.followup = ControlAlly.InvokerAI.selectComboSpell(context, combo)
		if not combo.followup then
			context.controller.invoker.combo = nil
			return nil, nil
		end
	end
	local followup = combo.followup
	followup.issueAt = combo.landingAt
		- ControlAlly.InvokerAI.comboImpactDelay(context, followup.ability, followup.rule)
		+ ControlAlly.Constants.INVOKER_COMBO_CAST_TOLERANCE
	local invoked = ControlAlly.InvokerAI.invokedAbility(context.controller, followup.id, context.now)
	if not invoked then
		local prepareAction = ControlAlly.InvokerAI.prepareSpecificSpell(context, followup.id, followup.rule)
		return prepareAction, "combo_wait"
	end
	if context.now + ControlAlly.Constants.INVOKER_COMBO_CAST_TOLERANCE < followup.issueAt then
		return nil, "combo_wait"
	end
	if context.now > followup.issueAt + ControlAlly.Constants.INVOKER_COMBO_LATE_TOLERANCE then
		context.controller.invoker.combo = nil
		return nil, nil
	end
	local timedRule = ControlAlly.Utils.copyTable(followup.rule)
	timedRule.allowDisabledTarget = true
	timedRule.preferDisabledTarget = false
	local action = ControlAlly.AbilityAI.buildAction(context, invoked, followup.id, timedRule, "ability")
	if action then
		action.score = 420
		action.urgent = true
		action.invokerComboSpell = followup.id
	end
	return action, action and "combo_cast" or "combo_wait"
end

function ControlAlly.InvokerAI.iceWallAction(context, ability, rule)
	if
		not context.target
		or not ControlAlly.AbilityAI.isReady(context.controller, ability, "invoker_ice_wall", false, false)
	then
		return nil, nil
	end
	local origin = ControlAlly.Utils.call(Entity.GetAbsOrigin, context.unit)
	local targetPosition = ControlAlly.Targeting.predictPosition(context.target, ability, rule)
	if not origin or not targetPosition then
		return nil, nil
	end
	local wallDistance = ControlAlly.Utils.specialValueExact(ability, "wall_place_distance", 0) or 0
	local wallLength = ControlAlly.Utils.specialValueExact(ability, "wall_total_length", 0) or 0
	local wallWidth = ControlAlly.Utils.specialValueExact(ability, "wall_width", 0) or 0
	if wallDistance <= 0 or wallLength <= 0 then
		return nil, nil
	end
	local distance = ControlAlly.Utils.distance2D(origin, targetPosition)
	local behavior = ControlAlly.Utils.call(Ability.GetBehavior, ability) or 0
	local vectorRange = ControlAlly.Utils.specialValueExact(ability, "vector_cast_range", 0) or 0
	if
		vectorRange > 0
		and ControlAlly.Utils.hasFlag(behavior, Enum.AbilityBehavior.DOTA_ABILITY_BEHAVIOR_VECTOR_TARGETING)
	then
		if distance > vectorRange then
			local stand = ControlAlly.Utils.positionToward(targetPosition, origin, vectorRange * 0.85)
			if stand then
				local iceWall = context.controller.invoker
				iceWall.iceWallStand = iceWall.iceWallStand or { startedAt = context.now }
				if context.now - iceWall.iceWallStand.startedAt > ControlAlly.Constants.ICE_WALL_POSITION_TIMEOUT then
					iceWall.iceWallStand = nil
					return nil, nil
				end
				ControlAlly.Orders.move(context.controller, stand, context.now)
				return nil, "positioning"
			end
		end
		context.controller.invoker.iceWallStand = nil
		local towardTarget = ControlAlly.Utils.normalized2D(origin, targetPosition)
		if not towardTarget then
			return nil, nil
		end
		local perpendicular = Vector(-towardTarget.y, towardTarget.x, 0)
		local vectorLength = math.min(wallLength, vectorRange)
		local centeredStart = Vector(
			targetPosition.x - perpendicular.x * vectorLength * 0.5,
			targetPosition.y - perpendicular.y * vectorLength * 0.5,
			targetPosition.z or 0
		)
		local startPosition = ControlAlly.Utils.distance2D(origin, centeredStart) <= vectorRange and centeredStart
			or targetPosition
		return {
			ability = ability,
			id = "invoker_ice_wall",
			policy = "vector",
			position = startPosition,
			vectorEnd = Vector(
				startPosition.x + perpendicular.x * vectorLength,
				startPosition.y + perpendicular.y * vectorLength,
				targetPosition.z or 0
			),
			score = 112,
			urgent = true,
			source = "ability",
			rule = rule,
		},
			nil
	end
	local halfLength = wallLength * 0.5
	local hull = ControlAlly.Utils.call(NPC.GetHullRadius, context.target) or 0
	local alongTolerance = wallWidth * 0.5 + hull
	local minimumReach = math.max(0, wallDistance - alongTolerance)
	local maximumReach = math.sqrt(
		(wallDistance + alongTolerance) * (wallDistance + alongTolerance) + (halfLength + hull) * (halfLength + hull)
	)
	if distance < minimumReach or distance > maximumReach then
		local stand = ControlAlly.Utils.positionToward(targetPosition, origin, wallDistance)
		if
			stand
			and ControlAlly.Utils.distance2D(origin, stand) > ControlAlly.Constants.ICE_WALL_POSITION_TOLERANCE
		then
			local iceWall = context.controller.invoker
			iceWall.iceWallStand = iceWall.iceWallStand or { startedAt = context.now }
			if context.now - iceWall.iceWallStand.startedAt > ControlAlly.Constants.ICE_WALL_POSITION_TIMEOUT then
				iceWall.iceWallStand = nil
				return nil, nil
			end
			ControlAlly.Orders.move(context.controller, stand, context.now)
			return nil, "positioning"
		end
	end
	local direction = ControlAlly.Utils.normalized2D(origin, targetPosition)
	if not direction then
		return nil, nil
	end
	local minimumAlongForCross = math.sqrt(math.max(0, distance * distance - (halfLength + hull) * (halfLength + hull)))
	local desiredAlong = ControlAlly.Utils.clamp(
		math.max(wallDistance - alongTolerance, minimumAlongForCross),
		wallDistance - alongTolerance,
		math.min(distance, wallDistance + alongTolerance)
	)
	local angle = math.acos(ControlAlly.Utils.clamp(desiredAlong / math.max(distance, 0.001), -1, 1))
	local left = ControlAlly.Utils.rotate2D(direction, angle)
	local right = ControlAlly.Utils.rotate2D(direction, -angle)
	local leftPoint = Vector(origin.x + left.x * 100, origin.y + left.y * 100, origin.z or 0)
	local rightPoint = Vector(origin.x + right.x * 100, origin.y + right.y * 100, origin.z or 0)
	local leftTime = ControlAlly.Utils.call(NPC.GetTimeToFacePosition, context.unit, leftPoint) or math.huge
	local rightTime = ControlAlly.Utils.call(NPC.GetTimeToFacePosition, context.unit, rightPoint) or math.huge
	local desiredForward = leftTime <= rightTime and left or right
	local rotation = ControlAlly.Utils.call(Entity.GetRotation, context.unit)
	local forward = rotation and ControlAlly.Utils.call(rotation.GetForward, rotation)
	local offsetX = targetPosition.x - origin.x
	local offsetY = targetPosition.y - origin.y
	local aligned = false
	if forward then
		local along = offsetX * forward.x + offsetY * forward.y
		local across = math.abs(offsetX * -forward.y + offsetY * forward.x)
		aligned = math.abs(along - wallDistance) <= wallWidth * 0.5 + hull and across <= halfLength + hull
	end
	if not aligned then
		local iceWall = context.controller.invoker
		iceWall.iceWallStand = iceWall.iceWallStand or { startedAt = context.now }
		if context.now - iceWall.iceWallStand.startedAt > ControlAlly.Constants.ICE_WALL_POSITION_TIMEOUT then
			iceWall.iceWallStand = nil
			return nil, nil
		end
		ControlAlly.Orders.face(context.controller, desiredForward, context.now)
		return nil, "positioning"
	end
	context.controller.invoker.iceWallStand = nil
	return {
		ability = ability,
		id = "invoker_ice_wall",
		policy = "noTarget",
		score = 112,
		urgent = true,
		source = "ability",
		rule = rule,
	},
		nil
end

function ControlAlly.InvokerAI.chooseSpell(context)
	local bestDesired
	local bestDesiredScore = -math.huge
	local bestInvokedAction
	for spellId, rule in pairs(ControlAlly.Profiles.InvokerSpells) do
		local ability = ControlAlly.AbilityAI.findAbility(context.controller, spellId, context.now)
		local invokedAbility = ControlAlly.InvokerAI.invokedAbility(context.controller, spellId, context.now)
		local score = ControlAlly.InvokerAI.spellScore(context, ability, spellId, rule, invokedAbility ~= nil)
		if score and score > bestDesiredScore then
			bestDesired = {
				id = spellId,
				ability = ability,
				rule = rule,
				score = score,
				invoked = invokedAbility ~= nil,
			}
			bestDesiredScore = score
		end
		if invokedAbility then
			local action
			if spellId ~= "invoker_ice_wall" then
				action = ControlAlly.AbilityAI.buildAction(context, invokedAbility, spellId, rule, "ability")
			end
			if action and spellId == "invoker_tornado" then
				action.invokerComboSetup = true
			end
			if action and (not bestInvokedAction or action.score > bestInvokedAction.score) then
				bestInvokedAction = action
			end
		end
	end
	if bestDesired and bestDesired.id == "invoker_ice_wall" and bestDesired.invoked then
		local iceAction, iceStatus = ControlAlly.InvokerAI.iceWallAction(context, bestDesired.ability, bestDesired.rule)
		if iceStatus then
			return bestDesired, nil, iceStatus
		end
		return bestDesired, iceAction or bestInvokedAction, nil
	end
	return bestDesired, bestInvokedAction
end

function ControlAlly.InvokerAI.orbCounts(controller)
	local counts = {
		invoker_quas = 0,
		invoker_wex = 0,
		invoker_exort = 0,
	}
	local modifierToOrb = {
		modifier_invoker_quas_instance = "invoker_quas",
		modifier_invoker_wex_instance = "invoker_wex",
		modifier_invoker_exort_instance = "invoker_exort",
	}
	for _, modifier in ipairs(ControlAlly.Utils.call(NPC.GetModifiers, controller.unit) or {}) do
		local orbId = modifierToOrb[ControlAlly.Utils.call(Modifier.GetName, modifier)]
		if orbId then
			local stacks = ControlAlly.Utils.call(Modifier.GetStackCount, modifier) or 0
			counts[orbId] = math.max(counts[orbId] + 1, stacks)
		end
	end
	return counts, counts.invoker_quas + counts.invoker_wex + counts.invoker_exort
end

function ControlAlly.InvokerAI.orbSignature(controller)
	local counts = ControlAlly.InvokerAI.orbCounts(controller)
	return string.format("%d:%d:%d", counts.invoker_quas, counts.invoker_wex, counts.invoker_exort)
end

function ControlAlly.InvokerAI.desiredOrbCounts(rule)
	local counts = {
		invoker_quas = 0,
		invoker_wex = 0,
		invoker_exort = 0,
	}
	for _, orbId in ipairs(rule.orbs or {}) do
		counts[orbId] = (counts[orbId] or 0) + 1
	end
	return counts
end

function ControlAlly.InvokerAI.orbsMatch(actual, desired)
	return actual.invoker_quas == desired.invoker_quas
		and actual.invoker_wex == desired.invoker_wex
		and actual.invoker_exort == desired.invoker_exort
end

function ControlAlly.InvokerAI.internalAction(ability, id, stage, dedupeKey, metadata)
	metadata = metadata or {}
	return {
		ability = ability,
		id = id,
		policy = "noTarget",
		score = 500,
		urgent = true,
		internal = true,
		allowRapid = true,
		executeFast = true,
		orderGap = ControlAlly.Constants.INVOKER_INTERNAL_ORDER_GAP,
		invokerStage = stage,
		invokerSpellId = metadata.spellId,
		invokerCountTracking = metadata.countTracking == true,
		orbSignatureBefore = metadata.orbSignatureBefore,
		dedupeKey = dedupeKey,
	}
end

function ControlAlly.InvokerAI.nextAction(context)
	local controller = context.controller
	local state = controller.invoker
	local comboAction, comboStatus = ControlAlly.InvokerAI.comboAction(context)
	if comboAction or comboStatus then
		return comboAction, comboStatus
	end
	if context.now < state.waitUntil then
		return nil, "preparing"
	end

	local desired, invokedAction, specialStatus = ControlAlly.InvokerAI.chooseSpell(context)
	if specialStatus then
		return invokedAction, specialStatus
	end
	if not desired then
		state.spellId = nil
		state.orbIndex = 1
		return invokedAction, nil
	end
	if desired.invoked then
		state.spellId = nil
		state.orbIndex = 1
		return invokedAction, nil
	end
	if invokedAction and invokedAction.score + 18 >= desired.score then
		return invokedAction, nil
	end

	local invoke = ControlAlly.AbilityAI.findAbility(controller, "invoker_invoke", context.now)
	if not ControlAlly.AbilityAI.isReady(controller, invoke, "invoker_invoke", false, false) then
		return invokedAction, nil
	end
	local mana = ControlAlly.Utils.call(NPC.GetMana, controller.unit) or 0
	local requiredMana = (ControlAlly.Utils.call(Ability.GetManaCost, invoke) or 0)
		+ (ControlAlly.Utils.call(Ability.GetManaCost, desired.ability) or 0)
	if mana < requiredMana then
		return invokedAction, nil
	end

	if state.spellId ~= desired.id then
		state.spellId = desired.id
		state.orbIndex = 1
		state.nextStepAt = context.now
	end
	if context.now < state.nextStepAt then
		return nil, "preparing"
	end

	local orbs = desired.rule.orbs or {}
	local actualCounts, actualTotal = ControlAlly.InvokerAI.orbCounts(controller)
	local desiredCounts = ControlAlly.InvokerAI.desiredOrbCounts(desired.rule)
	local countTracking = actualTotal > 0
	if countTracking and ControlAlly.InvokerAI.orbsMatch(actualCounts, desiredCounts) then
		state.orbIndex = #orbs + 1
	end
	if state.orbIndex <= #orbs then
		local orbId
		if countTracking then
			for _, candidateId in ipairs({ "invoker_quas", "invoker_wex", "invoker_exort" }) do
				if actualCounts[candidateId] < desiredCounts[candidateId] then
					orbId = candidateId
					break
				end
			end
		end
		orbId = orbId or orbs[state.orbIndex]
		local orb = ControlAlly.AbilityAI.findAbility(controller, orbId, context.now)
		if ControlAlly.AbilityAI.isReady(controller, orb, orbId, false, false) then
			return ControlAlly.InvokerAI.internalAction(
				orb,
				orbId,
				"orb",
				string.format("invoke:%s:orb:%s:%d", desired.id, orbId, state.orbIndex),
				{
					spellId = desired.id,
					countTracking = countTracking,
					orbSignatureBefore = ControlAlly.InvokerAI.orbSignature(controller),
				}
			),
				"preparing"
		end
		return invokedAction, nil
	end
	return ControlAlly.InvokerAI.internalAction(
		invoke,
		"invoker_invoke",
		"invoke",
		"invoke:" .. desired.id,
		{ spellId = desired.id }
	),
		"preparing"
end

function ControlAlly.InvokerAI.onActionConfirmed(controller, pending, now)
	if not pending or not pending.internal then
		return
	end
	local state = controller.invoker
	if pending.invokerStage == "orb" then
		if not pending.invokerCountTracking then
			state.orbIndex = state.orbIndex + 1
		end
		state.nextStepAt = now + ControlAlly.Constants.INVOKER_ORB_GAP
	elseif pending.invokerStage == "invoke" then
		state.waitUntil = now + ControlAlly.Constants.INVOKER_POST_INVOKE_WAIT
		state.nextStepAt = state.waitUntil
		state.orbIndex = 1
	end
end

function ControlAlly.InvokerAI.onSpellCastResult(controller, pending, success, now)
	if pending.invokerComboSpell then
		if success then
			controller.invoker.combo = nil
		else
			controller.invoker.combo = nil
		end
		return
	end
	if not pending.invokerComboSetup then
		return
	end
	if not success or not ControlAlly.Targeting.isValidEnemy(pending.castTarget) then
		controller.invoker.combo = nil
		return
	end
	local target = pending.castTarget
	local rule = ControlAlly.Profiles.InvokerSpells.invoker_tornado
	local speed = ControlAlly.Utils.ruleValue(pending.ability, rule, "projectileSpeed", "projectileSpeedSpecial", 0)
		or 0
	local duration = ControlAlly.Utils.ruleValue(pending.ability, rule, "duration", "durationSpecial", 0) or 0
	local distance = ControlAlly.Utils.distance2D(
		ControlAlly.Utils.call(Entity.GetAbsOrigin, controller.unit),
		pending.impactPosition or ControlAlly.Utils.call(Entity.GetAbsOrigin, target)
	)
	local travel = speed > 0 and distance < math.huge and distance / speed or 0
	controller.invoker.combo = {
		target = target,
		landingAt = now + travel + duration,
		expectedImpactAt = now + travel,
		sawLift = false,
		followup = nil,
	}
end

function ControlAlly.TinkerAI.rearmChannelTime(rearm)
	return ControlAlly.Utils.specialValueExact(rearm, "AbilityChannelTime", 0) or 0
end

function ControlAlly.TinkerAI.rearmAction(context, currentAction)
	local controller = context.controller
	if
		not ControlAlly.UI.UseAbilities
		or ControlAlly.UI.UseAbilities:Get() ~= true
		or controller.heroName ~= "npc_dota_hero_tinker"
		or currentAction
		or not context.target
		or not ControlAlly.Menu.isAbilityEnabled("tinker_rearm")
		or context.now - controller.lastRearmAt < ControlAlly.Constants.TINKER_REARM_GAP
		or controller.lastRefreshableCastAt <= controller.lastRearmAt
	then
		return nil
	end
	local rearm = ControlAlly.AbilityAI.findAbility(controller, "tinker_rearm", context.now)
	if not ControlAlly.AbilityAI.isReady(controller, rearm, "tinker_rearm", false, false) then
		return nil
	end
	local usefulCooldowns = 0
	local cheapestFollowup = math.huge
	local rearmDelay = ControlAlly.TinkerAI.rearmChannelTime(rearm)
		+ (ControlAlly.Utils.call(Ability.GetCastPoint, rearm) or 0)
		+ 0.12
	local catalog = ControlAlly.AbilityAI.catalog(controller, context.now)
	for _, entry in ipairs(catalog.abilities) do
		if ControlAlly.Profiles.RefreshableTinkerActions[entry.id] and ControlAlly.Menu.isAbilityEnabled(entry.id) then
			local rule = ControlAlly.Profiles.getAbilityRule(controller.profileName or controller.heroName, entry.id)
			if rule and ControlAlly.AbilityAI.wouldBeUsableIfReady(context, entry.ability, rule) then
				if ControlAlly.AbilityAI.isReady(controller, entry.ability, entry.id, false, false) then
					return nil
				end
				if ControlAlly.Utils.cooldownRemaining(entry.ability) > rearmDelay then
					usefulCooldowns = usefulCooldowns + 1
					cheapestFollowup =
						math.min(cheapestFollowup, ControlAlly.Utils.call(Ability.GetManaCost, entry.ability) or 0)
				end
			end
		end
	end
	if usefulCooldowns <= 0 then
		return nil
	end
	local mana = ControlAlly.Utils.call(NPC.GetMana, controller.unit) or 0
	local rearmCost = ControlAlly.Utils.call(Ability.GetManaCost, rearm) or 0
	if mana < rearmCost + (cheapestFollowup < math.huge and cheapestFollowup or 0) then
		return nil
	end
	return {
		ability = rearm,
		id = "tinker_rearm",
		policy = "noTarget",
		score = 45,
		isRearm = true,
		source = "ability",
	}
end

function ControlAlly.Combat.confirmPendingCast(controller, now)
	local pending = controller.pendingCast
	if not pending then
		return true
	end
	local ability = pending.ability
	local cooldown = ControlAlly.Utils.cooldownRemaining(ability)
	local charges = ControlAlly.Utils.call(Ability.GetCurrentCharges, ability)
	local seconds = ControlAlly.Utils.call(Ability.SecondsSinceLastUse, ability)
	local castStart = ControlAlly.Utils.call(Ability.GetCastStartTime, ability)
	local inPhase = ControlAlly.Utils.call(Ability.IsInAbilityPhase, ability) == true
	local channel = ControlAlly.Utils.protectedActivity(controller.unit, controller.activeAbility)
	local castStartChanged = type(castStart) == "number"
		and type(pending.castStartBefore) == "number"
		and castStart > pending.castStartBefore + 0.001

	local function finish(success)
		if not success then
			if pending.committedMotion then
				ControlAlly.Utils.clearMotionLock(controller)
			end
			controller.lastIssued[pending.dedupeKey or pending.id] = nil
			if pending.supportFamily then
				ControlAlly.Runtime.supportReservations[pending.supportFamily] = nil
			end
			if pending.positionReservationFamily and pending.castPosition then
				local kept = {}
				for _, reservation in
					ipairs(ControlAlly.Runtime.positionReservations[pending.positionReservationFamily] or {})
				do
					if ControlAlly.Utils.distance2D(reservation.position, pending.castPosition) > 1 then
						kept[#kept + 1] = reservation
					end
				end
				ControlAlly.Runtime.positionReservations[pending.positionReservationFamily] = kept
			end
			if pending.disable and pending.castTarget then
				local targetIndex = ControlAlly.Utils.entityIndex(pending.castTarget)
				if targetIndex then
					ControlAlly.Runtime.disableReservations[targetIndex] = nil
				end
			end
			if pending.breaksLinkens and pending.castTarget then
				local targetIndex = ControlAlly.Utils.entityIndex(pending.castTarget)
				if targetIndex then
					ControlAlly.Runtime.linkensReservations[targetIndex] = nil
				end
			end
		else
			if pending.desiredToggle ~= nil then
				controller.ownedToggles[pending.id] = pending.desiredToggle and true or nil
				local record, index = ControlAlly.Roster.toggleRegistryRecord(
					controller.unit,
					controller.playerId,
					pending.desiredToggle == true
				)
				if record then
					record.abilities[pending.id] = pending.desiredToggle and true or nil
					if index and next(record.abilities) == nil then
						ControlAlly.Runtime.toggleOwnershipRegistry[index] = nil
					end
				end
			end
			if pending.internal then
				ControlAlly.InvokerAI.onActionConfirmed(controller, pending, now)
			else
				if pending.attackModifier then
					controller.castsSinceAttack = 0
					controller.lastAttackTarget = ControlAlly.Utils.entityIndex(pending.castTarget)
				else
					controller.castsSinceAttack = controller.castsSinceAttack + 1
				end
				if pending.source == "ability" and not pending.isRearm then
					controller.usedAbilitiesSinceRefresh[pending.id] = now
				end
				if pending.refreshable then
					controller.lastRefreshableCastAt = now
				end
				if pending.isRearm then
					controller.lastRearmAt = now
					controller.usedAbilitiesSinceRefresh = {}
				end
				if pending.isRefresher then
					controller.lastRefresherAt = now
					controller.usedAbilitiesSinceRefresh = {}
				end
			end
		end
		ControlAlly.InvokerAI.onSpellCastResult(controller, pending, success, now)
		ControlAlly.MeepoAI.onCastResult(controller, pending, success, now)
		ControlAlly.AlchemistAI.onCastResult(controller, pending, success, now)
		ControlAlly.TechiesAI.onCastResult(controller, pending, success)
		ControlAlly.SpecialAI.onCastResult(controller, pending, success, now)
		controller.pendingCast = nil
		controller.activeAbility = nil
		return true
	end

	if pending.sessionGeneration ~= ControlAlly.Runtime.sessionGeneration then
		return finish(false)
	end

	if inPhase or channel == ability then
		pending.started = true
		pending.channelEndedAt = nil
		if channel == ability then
			pending.wasChanneling = true
			if not pending.channelStartedAt then
				local reportedStart = ControlAlly.Utils.call(Ability.GetChannelStartTime, ability)
				pending.channelStartedAt = type(reportedStart) == "number" and reportedStart > 0 and reportedStart
					or now
			end
		end
		local hardTimeout = math.max(
			(pending.channelTime or 0) + 1.40,
			pending.internal and 0.70 or ControlAlly.Constants.PENDING_PHASE_HARD_TIMEOUT
		)
		if now - pending.issuedAt > hardTimeout then
			return finish(pending.allowEarlyEnd == true)
		end
		return false
	end
	if castStartChanged then
		pending.started = true
	end
	local orbChanged = pending.internal
		and pending.invokerStage == "orb"
		and pending.orbSignatureBefore ~= nil
		and ControlAlly.InvokerAI.orbSignature(controller) ~= pending.orbSignatureBefore
	local invokedAppeared = pending.internal
		and pending.invokerStage == "invoke"
		and pending.invokerSpellId
		and ControlAlly.InvokerAI.invokedAbility(controller, pending.invokerSpellId, now) ~= nil
	local refreshObserved = false
	if pending.isRefresher then
		local elapsed = math.max(0, now - pending.issuedAt)
		for id, before in pairs(pending.refreshCooldownsBefore or {}) do
			local refreshed = ControlAlly.AbilityAI.findAbility(controller, id, now)
			local naturalRemaining = math.max(0, (before or 0) - elapsed)
			if naturalRemaining > 0.10 and ControlAlly.Utils.cooldownRemaining(refreshed) + 0.10 < naturalRemaining then
				refreshObserved = true
				break
			end
		end
	end
	local successEvidence = cooldown > (pending.cooldownBefore or 0) + 0.02
		or (type(charges) == "number" and type(pending.chargesBefore) == "number" and charges < pending.chargesBefore)
		or (type(seconds) == "number" and seconds >= 0 and (type(pending.secondsBefore) ~= "number" or pending.secondsBefore < 0 or seconds + 0.05 < pending.secondsBefore))
		or orbChanged
		or invokedAppeared
		or (pending.alchemistStage == "throw" and pending.hiddenBefore == false and ControlAlly.Utils.call(
			Ability.IsHidden,
			ability
		) == true)
		or refreshObserved
		or (pending.toggleBefore ~= nil and ControlAlly.Utils.call(Ability.GetToggleState, ability) ~= pending.toggleBefore)
		or (pending.altBefore ~= nil and Ability.GetAltCastState and ControlAlly.Utils.call(
			Ability.GetAltCastState,
			ability
		) ~= pending.altBefore)
		or (pending.treadsBefore ~= nil and PowerTreads and PowerTreads.GetStats and ControlAlly.Utils.call(
			PowerTreads.GetStats,
			ability
		) ~= pending.treadsBefore)
		or (
			pending.attackModifier
			and now - pending.issuedAt > 0.08
			and ControlAlly.Utils.call(NPC.IsAttacking, controller.unit) == true
		)

	if pending.isRearm then
		if pending.wasChanneling then
			local elapsed = math.max(0, now - pending.issuedAt)
			local resetObserved = false
			for id, before in pairs(pending.refreshCooldownsBefore or {}) do
				local refreshed = ControlAlly.AbilityAI.findAbility(controller, id, now)
				local current = ControlAlly.Utils.cooldownRemaining(refreshed)
				local naturalRemaining = math.max(0, (before or 0) - elapsed)
				if naturalRemaining > 0.10 and current + 0.10 < naturalRemaining then
					resetObserved = true
					break
				end
			end
			if resetObserved then
				return finish(true)
			end
			pending.channelEndedAt = pending.channelEndedAt or now
			if now - pending.channelEndedAt < ControlAlly.Constants.PENDING_CHANNEL_END_DEBOUNCE then
				return false
			end
			local channelElapsed = pending.channelEndedAt - (pending.channelStartedAt or pending.issuedAt)
			if pending.started and channelElapsed + 0.15 >= (pending.channelTime or 0) then
				return finish(true)
			end
			if now - pending.channelEndedAt > 0.18 then
				return finish(false)
			end
			return false
		end
		local timeout = math.max(1.40, (pending.channelTime or 0) + 0.80)
		if now - pending.issuedAt > timeout then
			return finish(false)
		end
		return false
	end

	if pending.channelled and pending.wasChanneling then
		if pending.allowEarlyEnd then
			return finish(true)
		end
		pending.channelEndedAt = pending.channelEndedAt or now
		if now - pending.channelEndedAt < ControlAlly.Constants.PENDING_CHANNEL_END_DEBOUNCE then
			return false
		end
		local channelElapsed = pending.channelEndedAt - (pending.channelStartedAt or pending.issuedAt)
		local expected = pending.channelTime or 0
		local durationCompleted = expected > 0 and channelElapsed + 0.15 >= expected
		if (successEvidence and expected <= 0) or (durationCompleted and (successEvidence or pending.started)) then
			return finish(true)
		end
		if now - pending.channelEndedAt > 0.18 then
			return finish(false)
		end
		return false
	end

	if successEvidence then
		return finish(true)
	end
	local timeout = pending.internal and 0.70 or 1.40
	if now - pending.issuedAt <= timeout then
		return false
	end
	return finish(false)
end

function ControlAlly.Combat.chooseAction(first, second)
	if not first then
		return second
	end
	if not second then
		return first
	end
	return first.score >= second.score and first or second
end

function ControlAlly.Combat.rollbackPendingReservations(controller)
	local pending = controller and controller.pendingCast
	if not pending or (not pending.supportFamily and not pending.positionReservationFamily) then
		return
	end
	local cooldown = ControlAlly.Utils.cooldownRemaining(pending.ability)
	local charges = ControlAlly.Utils.call(Ability.GetCurrentCharges, pending.ability)
	local likelyCast = pending.started
		or cooldown > (pending.cooldownBefore or 0) + 0.02
		or (type(charges) == "number" and type(pending.chargesBefore) == "number" and charges < pending.chargesBefore)
	if likelyCast then
		return
	end
	if pending.supportFamily then
		ControlAlly.Runtime.supportReservations[pending.supportFamily] = nil
	end
	if pending.positionReservationFamily and pending.castPosition then
		local kept = {}
		for _, reservation in ipairs(ControlAlly.Runtime.positionReservations[pending.positionReservationFamily] or {}) do
			if ControlAlly.Utils.distance2D(reservation.position, pending.castPosition) > 1 then
				kept[#kept + 1] = reservation
			end
		end
		ControlAlly.Runtime.positionReservations[pending.positionReservationFamily] = kept
	end
end

function ControlAlly.Combat.maintainInactiveControllers(now, detachedOnly)
	for _, controller in pairs(ControlAlly.Runtime.controllerStates) do
		if
			(not detachedOnly or controller.detached == true)
			and ControlAlly.Utils.isValidControllerUnit(controller.unit, true)
		then
			ControlAlly.Combat.confirmPendingCast(controller, now)
			if
				not controller.pendingCast
				and now >= (controller.busyUntil or -math.huge)
				and ControlAlly.Utils.protectedActivity(controller.unit, controller.activeAbility) == nil
			then
				for id in pairs(controller.ownedToggles or {}) do
					local ability = ControlAlly.AbilityAI.findAbility(controller, id, now)
					if not ability or ControlAlly.Utils.call(Ability.GetToggleState, ability) ~= true then
						controller.ownedToggles[id] = nil
						local record, index =
							ControlAlly.Roster.toggleRegistryRecord(controller.unit, controller.playerId, false)
						if record then
							record.abilities[id] = nil
							if index and next(record.abilities) == nil then
								ControlAlly.Runtime.toggleOwnershipRegistry[index] = nil
							end
						end
					elseif
						ControlAlly.Orders.cast(controller, {
							ability = ability,
							id = id,
							policy = "toggle",
							score = 1000,
							urgent = true,
							source = "ability",
							desiredToggle = false,
							allowRapid = true,
							dedupeKey = "cleanup_toggle:" .. id,
						}, now)
					then
						return true
					end
				end
			end
		end
	end
	return false
end

function ControlAlly.Combat.finishStopRequests()
	for _, controller in pairs(ControlAlly.Runtime.controllerStates) do
		if controller.stopRequested then
			if not ControlAlly.Utils.isValidControllerUnit(controller.unit, true) then
				controller.stopRequested = false
			elseif ControlAlly.Runtime.orderBudget <= 0 then
				return
			else
				local now = ControlAlly.Utils.gameTime()
				if
					not ControlAlly.Runtime.inSession
					and ControlAlly.Utils.isMotionLocked(controller, now)
					and ControlAlly.Utils.protectedActivity(controller.unit, controller.activeAbility) == nil
				then
					ControlAlly.Utils.clearMotionLock(controller)
				end
				ControlAlly.Orders.stop(controller)
			end
		end
	end
end

function ControlAlly.Combat.updateController(controller, target, now)
	if now < controller.nextThinkAt then
		return
	end
	local thinkInterval = ControlAlly.Constants.CONTROLLER_THINK_INTERVAL
	if
		controller.heroName == "npc_dota_hero_invoker"
		and now < (ControlAlly.Runtime.invokerFastUntil or -math.huge)
	then
		thinkInterval = ControlAlly.Constants.INVOKER_INTERNAL_ORDER_GAP
	end
	controller.nextThinkAt = now + thinkInterval
	if
		not ControlAlly.Utils.isValidControllerUnit(controller.unit, true)
		or ControlAlly.Utils.call(Entity.IsDormant, controller.unit) == true
		or ControlAlly.Utils.isCommandRestricted(controller.unit)
	then
		return
	end
	if not ControlAlly.Combat.confirmPendingCast(controller, now) then
		ControlAlly.SpecialAI.handleLockedChannel(controller, now)
		return
	end
	if
		now < controller.busyUntil
		or ControlAlly.Utils.isMotionLocked(controller, now)
		or ControlAlly.Utils.protectedActivity(controller.unit, controller.activeAbility) ~= nil
	then
		return
	end
	if controller.interleaveTarget then
		if
			now >= controller.interleaveDeadline
			or not ControlAlly.Targeting.isValidEnemy(controller.interleaveTarget)
		then
			controller.interleaveTarget = nil
			controller.interleaveDeadline = -math.huge
			controller.castsSinceAttack = 0
		else
			if not ControlAlly.Orders.attack(controller, controller.interleaveTarget, now, true) then
				if now + 0.05 >= controller.interleaveDeadline then
					controller.interleaveTarget = nil
					controller.interleaveDeadline = -math.huge
					controller.castsSinceAttack = 0
				else
					return
				end
			else
				return
			end
		end
	end
	if
		controller.heroName == "npc_dota_hero_invoker"
		and ControlAlly.Utils.hasAnyModifier(controller.unit, { "modifier_invoker_ghost_walk_self" })
		and ControlAlly.Utils.healthPct(controller.unit) < ControlAlly.Constants.GHOST_WALK_EXIT_HEALTH
	then
		local unitPosition = ControlAlly.Utils.call(Entity.GetAbsOrigin, controller.unit)
		local enemyPosition = target and ControlAlly.Utils.call(Entity.GetAbsOrigin, target)
		if unitPosition and enemyPosition then
			local dx = unitPosition.x - enemyPosition.x
			local dy = unitPosition.y - enemyPosition.y
			local length = math.sqrt(dx * dx + dy * dy)
			if length > 0.001 then
				ControlAlly.Orders.move(
					controller,
					Vector(unitPosition.x + dx / length * 550, unitPosition.y + dy / length * 550, unitPosition.z or 0),
					now
				)
			end
		end
		return
	end

	local context = {
		controller = controller,
		unit = controller.unit,
		target = ControlAlly.Targeting.isValidEnemy(target) and target or nil,
		now = now,
	}
	if ControlAlly.SpecialAI.controlActiveMotion(context) then
		return
	end
	local action
	local invokerStatus
	if
		controller.heroName == "npc_dota_hero_invoker"
		and ControlAlly.UI.UseAbilities
		and ControlAlly.UI.UseAbilities:Get() == true
	then
		action, invokerStatus = ControlAlly.InvokerAI.nextAction(context)
		if action and not action.internal then
			action.fastCombo = true
			action.executeFast = true
			action.orderGap = ControlAlly.Constants.INVOKER_INTERNAL_ORDER_GAP
		end
	end
	local meepoAction = ControlAlly.MeepoAI.netAction(context)
	action = ControlAlly.Combat.chooseAction(action, meepoAction)
	action = ControlAlly.Combat.chooseAction(action, ControlAlly.MeepoAI.poofAction(context))
	action = ControlAlly.Combat.chooseAction(action, ControlAlly.AlchemistAI.nextAction(context, false))
	action = ControlAlly.Combat.chooseAction(action, ControlAlly.SpecialAI.bestAction(context))
	if not invokerStatus then
		action = ControlAlly.Combat.chooseAction(action, ControlAlly.AbilityAI.bestAbilityAction(context))
		action = ControlAlly.Combat.chooseAction(action, ControlAlly.ItemAI.bestAction(context))
	end
	local supportAction = ControlAlly.SupportAI.bestAction(context)
	if not invokerStatus or (supportAction and supportAction.urgent) then
		action = ControlAlly.Combat.chooseAction(action, supportAction)
	end
	if not action then
		action = ControlAlly.SpecialAI.stormBallAction(context, nil)
	end
	action = action or ControlAlly.TinkerAI.rearmAction(context, action)
	action = action or ControlAlly.ItemAI.refresherAction(context, action)

	if (invokerStatus == "preparing" or invokerStatus == "positioning") and not action then
		if invokerStatus == "positioning" then
			return
		end
		local waitUntil = controller.invoker and controller.invoker.waitUntil or -math.huge
		local nextStepAt = controller.invoker and controller.invoker.nextStepAt or -math.huge
		if now < waitUntil or now < nextStepAt then
			return
		end
	end
	if
		context.target
		and ControlAlly.UI.AttackBetweenCasts
		and ControlAlly.UI.AttackBetweenCasts:Get() == true
		and controller.castsSinceAttack >= ControlAlly.Constants.MAX_CASTS_BEFORE_ATTACK
		and (not action or not action.urgent)
	then
		if ControlAlly.Orders.attack(controller, context.target, now, true) then
			return
		end
	end
	if action and ControlAlly.Orders.cast(controller, action, now) then
		return
	end
	if context.target then
		ControlAlly.Orders.attack(controller, context.target, now, false)
	elseif ControlAlly.UI.FollowCursor and ControlAlly.UI.FollowCursor:Get() == true then
		local cursor = ControlAlly.Utils.call(Input.GetWorldCursorPos)
		if cursor then
			ControlAlly.Orders.move(controller, cursor, now)
		end
	end
end

function ControlAlly:resetControllerSessionState(controller, now)
	self.Combat.rollbackPendingReservations(controller)
	local activeAbility = controller.activeAbility
	local activity = self.Utils.protectedActivity(controller.unit, activeAbility)
	local pending = controller.pendingCast
	local keepPending = pending and activity == pending.ability
	if keepPending then
		pending.sessionGeneration = self.Runtime.sessionGeneration
	end
	controller.pendingCast = keepPending and pending or nil
	controller.activeAbility = keepPending and pending.ability or (activity == activeAbility and activeAbility or nil)
	controller.busyUntil = keepPending and math.max(controller.busyUntil or now, now) or now
	controller.nextThinkAt = now
	controller.lastIssued = {}
	controller.castsSinceAttack = 0
	controller.lastAttackTarget = nil
	controller.lastAttackAt = -math.huge
	controller.interleaveTarget = nil
	controller.interleaveDeadline = -math.huge
	controller.lastMovePosition = nil
	controller.lastFaceAt = -math.huge
	controller.usedAbilitiesSinceRefresh = {}
	controller.invoker.spellId = nil
	controller.invoker.orbIndex = 1
	controller.invoker.nextStepAt = now
	controller.invoker.waitUntil = -math.huge
	controller.invoker.combo = nil
	controller.invoker.iceWallStand = nil
	controller.techies.minePlan = nil
	if not (keepPending and pending and pending.committedMotion) then
		self.Utils.clearMotionLock(controller)
	end
	if
		not keepPending
		and controller.special.stage ~= "aa_release"
		and controller.special.stage ~= "morph_copied"
		and controller.special.stage ~= "dazzle_active"
	then
		controller.special.stage = nil
		controller.special.target = nil
		controller.special.followup = nil
		controller.special.startedAt = -math.huge
	end
end

function ControlAlly:startSession(now)
	self.Runtime.inSession = true
	self.Runtime.sessionGeneration = (self.Runtime.sessionGeneration or 0) + 1
	self.Runtime.lockedTarget = nil
	self.Runtime.lastTargetSwitchAt = -math.huge
	self.Runtime.disableReservations = {}
	self.Runtime.linkensReservations = {}
	self.Runtime.effectReservations = {}
	self.Runtime.supportReservations = {}
	self.Runtime.positionReservations = {}
	self.Runtime.meepoNetChains = {}
	self.Runtime.meepoPlans = {}
	for _, controller in ipairs(self.Runtime.controllers) do
		controller.stopRequested = false
		self:resetControllerSessionState(controller, now)
	end
	self.Utils.debug("session %d started", self.Runtime.sessionGeneration)
end

function ControlAlly:stopSession(reason)
	if not self.Runtime.inSession then
		return
	end
	self.Runtime.inSession = false
	self.Runtime.lockedTarget = nil
	self.Runtime.disableReservations = {}
	self.Runtime.linkensReservations = {}
	self.Runtime.effectReservations = {}
	self.Runtime.supportReservations = {}
	self.Runtime.positionReservations = {}
	self.Runtime.meepoNetChains = {}
	self.Runtime.meepoPlans = {}
	local now = self.Utils.gameTime()
	for _, controller in ipairs(self.Runtime.controllers) do
		self.Combat.confirmPendingCast(controller, now)
		local preserveBrew = controller.alchemist and controller.alchemist.brewing
		if not preserveBrew then
			controller.stopRequested = true
			self.Orders.stop(controller)
		end
		self:resetControllerSessionState(controller, now)
		if preserveBrew then
			controller.nextOrderAt = now
		end
	end
	self.Utils.debug("session stopped: %s", reason or "inactive")
end

function ControlAlly:resetGameState()
	self:stopSession("game reset")
	local runtime = self.Runtime
	for index in pairs(runtime.toggleOwnershipRegistry) do
		runtime.toggleOwnershipRegistry[index] = nil
	end
	runtime.wasInGame = false
	runtime.lastUpdateAt = -math.huge
	runtime.lastRosterScanAt = -math.huge
	runtime.lastControllerScanAt = -math.huge
	runtime.lastEnemyScanAt = -math.huge
	runtime.lastAllyScanAt = -math.huge
	runtime.lastMenuSyncAt = -math.huge
	runtime.lastBuiltinBindScanAt = -math.huge
	runtime.invokerFastUntil = -math.huge
	runtime.rosterInitialized = false
	runtime.rosterSignature = ""
	runtime.controllerSignature = ""
	runtime.actionMenuSignature = ""
	runtime.itemMenuSignature = ""
	runtime.roster = {}
	runtime.rosterById = {}
	runtime.playerLabelToId = {}
	runtime.controllers = {}
	runtime.allies = {}
	runtime.controllerStates = {}
	runtime.selectedPlayerIds = {}
	runtime.enemies = {}
	runtime.lockedTarget = nil
	runtime.disableReservations = {}
	runtime.linkensReservations = {}
	runtime.effectReservations = {}
	runtime.supportReservations = {}
	runtime.positionReservations = {}
	runtime.meepoNetChains = {}
	runtime.meepoPlans = {}
	runtime.activityCache = {}
	runtime.cloneCountByPlayer = {}
	runtime.orderBudget = 0
	runtime.roundRobinIndex = 1
	runtime.localPlayer = nil
	runtime.localPlayerId = nil
	runtime.localHero = nil
	runtime.builtinComboBind = nil
	runtime.builtinComboHeroName = nil
end

function ControlAlly:Init()
	if self.Utils.call(Engine.IsInGame) ~= true then
		for index in pairs(self.Runtime.toggleOwnershipRegistry) do
			self.Runtime.toggleOwnershipRegistry[index] = nil
		end
	end
	self.Menu.initialize()
end

function ControlAlly:OnUpdate()
	if not self.Runtime.initialized then
		self:Init()
	end
	if self.Utils.call(Engine.IsInGame) ~= true then
		if self.Runtime.wasInGame then
			self:resetGameState()
		end
		return
	end
	self.Runtime.wasInGame = true
	if self.Utils.call(GameRules.IsPaused) == true then
		return
	end

	local now = self.Utils.gameTime()
	local updateInterval = self.Constants.UPDATE_INTERVAL
	if now < (self.Runtime.invokerFastUntil or -math.huge) then
		updateInterval = math.min(updateInterval, self.Constants.INVOKER_INTERNAL_ORDER_GAP * 0.5)
	end
	if now - self.Runtime.lastUpdateAt < updateInterval then
		return
	end
	self.Runtime.lastUpdateAt = now
	self.Runtime.orderBudget = self.Constants.MAX_ORDERS_PER_UPDATE
	self.Roster.scanPlayers(now, false)
	self.Roster.refreshControllers(now, false)
	self.Menu.syncActionOptions(now, false)
	self.Targeting.refreshBuiltinComboBind(now, false)
	self.Targeting.refreshEnemies(now, false)
	self.AlchemistAI.finishBrews(now)
	self.SpecialAI.finishManagedActions(now)
	self.Combat.finishStopRequests()
	if self.Runtime.inSession then
		self.Combat.maintainInactiveControllers(now, true)
	end

	if not self.UI.Enabled or self.UI.Enabled:Get() ~= true then
		self:stopSession("disabled")
		self.Combat.maintainInactiveControllers(now)
		return
	end
	if not self.Targeting.isActivationHeld(now) then
		self:stopSession("key released")
		self.Combat.maintainInactiveControllers(now)
		return
	end

	local justStarted = not self.Runtime.inSession
	if justStarted then
		self:startSession(now)
	end
	self.SupportAI.refreshAllies(now, false)
	local target = self.Targeting.resolve(now, justStarted)

	local count = #self.Runtime.controllers
	if count <= 0 then
		return
	end
	local startIndex = self.Utils.clamp(self.Runtime.roundRobinIndex, 1, count)
	for offset = 0, count - 1 do
		local index = ((startIndex + offset - 1) % count) + 1
		self.Combat.updateController(self.Runtime.controllers[index], target, now)
	end
	self.Runtime.roundRobinIndex = (startIndex % count) + 1
end

function ControlAlly:OnGameEnd()
	self:resetGameState()
end

function ControlAlly:OnEntityDestroy(entity)
	if not entity then
		return
	end
	if entity == self.Runtime.lockedTarget then
		self.Runtime.lockedTarget = nil
	end
	local index = self.Utils.entityIndex(entity)
	if index then
		self.Runtime.activityCache[index] = nil
		self.Runtime.toggleOwnershipRegistry[index] = nil
		self.Runtime.disableReservations[index] = nil
		self.Runtime.linkensReservations[index] = nil
		self.Runtime.meepoNetChains[index] = nil
		local prefix = tostring(index) .. ":"
		for key in pairs(self.Runtime.effectReservations) do
			if key:sub(1, #prefix) == prefix then
				self.Runtime.effectReservations[key] = nil
			end
		end
		local suffix = ":" .. tostring(index)
		for key in pairs(self.Runtime.supportReservations) do
			if key:sub(-#suffix) == suffix then
				self.Runtime.supportReservations[key] = nil
			end
		end
		for key, plan in pairs(self.Runtime.meepoPlans) do
			if
				plan.target == entity
				or (plan.controller and plan.controller.unit == entity)
				or plan.targetIndex == index
				or plan.casterIndex == index
			then
				self.Runtime.meepoPlans[key] = nil
			end
		end
	end
	if index and self.Runtime.controllerStates[index] then
		self.Runtime.controllerStates[index] = nil
		self.Runtime.lastControllerScanAt = -math.huge
		self.Runtime.controllerSignature = ""
	end
end

function ControlAlly:OnUnitInventoryUpdated(unit)
	for _, controller in ipairs(self.Runtime.controllers) do
		if controller.unit == unit then
			controller.catalog = nil
			controller.catalogRefreshAt = -math.huge
		end
	end
	self.Runtime.lastMenuSyncAt = -math.huge
	self.Runtime.itemMenuSignature = ""
end

function ControlAlly:OnSetDormant(unit, dormancyType)
	if dormancyType == Enum.DormancyType.ENTITY_NOT_DORMANT then
		return
	end
	if unit == self.Runtime.lockedTarget then
		self.Runtime.lockedTarget = nil
	end
	local index = self.Utils.entityIndex(unit)
	if index and self.Runtime.controllerStates[index] then
		local controller = self.Runtime.controllerStates[index]
		local retainForSafety = (controller.alchemist and controller.alchemist.brewing)
			or next(controller.ownedToggles or {}) ~= nil
			or controller.pendingCast ~= nil
			or controller.stopRequested == true
			or self.Utils.protectedActivity(controller.unit, controller.activeAbility) ~= nil
			or self.SpecialAI.requiresRetention(controller)
		if retainForSafety then
			controller.detached = true
		else
			self.Runtime.controllerStates[index] = nil
		end
		self.Runtime.lastControllerScanAt = -math.huge
	end
end

local callbackWrapper = XHelpers and (XHelpers.WrapCallbacks or XHelpers.BaseScript)
if callbackWrapper then
	return callbackWrapper(ControlAlly)
end
return ControlAlly