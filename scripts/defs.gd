extends RefCounted
## Static game data: unit and building stats.

const UNITS := {
	"worker": {
		"name": "Рабочий", "hp": 45, "armor": 0, "speed": 120.0, "radius": 9.0,
		"damage": 5, "range": 6.0, "cooldown": 1.5, "sight": 160.0,
		"cost": 50, "supply": 1, "time": 12.0, "hotkey": KEY_Q, "anti_air": false,
	},
	"marine": {
		"name": "Солдат", "hp": 45, "armor": 0, "speed": 105.0, "radius": 10.0,
		"damage": 6, "range": 130.0, "cooldown": 0.65, "sight": 240.0,
		"cost": 50, "supply": 1, "time": 14.0, "hotkey": KEY_Q, "anti_air": false,
	},
	# Medic: no weapon; heals the most damaged friendly unit within "range" (vehicles and flyers too).
	"medic": {
		"name": "Медик", "hp": 60, "armor": 0, "speed": 110.0, "radius": 10.0,
		"damage": 0, "range": 130.0, "cooldown": 1.0, "sight": 260.0,
		"cost": 75, "supply": 1, "time": 18.0, "hotkey": KEY_E, "healer": true, "heal_rate": 14.0,
		"heals": ["infantry"],
	},
	# Mechanic: repair vehicle, no weapon; repairs vehicles, aircraft and buildings in "range".
	"mechanic": {
		"name": "Ремонтник", "hp": 120, "armor": 2, "speed": 95.0, "radius": 13.0,
		"damage": 0, "range": 140.0, "cooldown": 1.0, "sight": 280.0,
		"cost": 100, "supply": 2, "time": 20.0, "hotkey": KEY_R, "healer": true, "heal_rate": 18.0,
		"heals": ["vehicle", "air", "building"],
	},
	# --- Commanders: unarmed squad leaders (see SQUADS). Big sight like a scout; members near
	# their commander get bonuses and follow it.
	"officer": {
		"name": "Офицер", "hp": 130, "armor": 1, "speed": 110.0, "radius": 11.0,
		"damage": 0, "range": 0.0, "cooldown": 1.0, "sight": 420.0,
		"cost": 100, "supply": 1, "time": 20.0, "hotkey": KEY_C, "unarmed": true, "commands": "infantry",
	},
	"command_vehicle": {
		"name": "Командирский БТР", "hp": 320, "armor": 4, "speed": 85.0, "radius": 16.0,
		"damage": 0, "range": 0.0, "cooldown": 1.0, "sight": 400.0,
		"cost": 175, "supply": 2, "time": 28.0, "hotkey": KEY_C, "unarmed": true, "commands": "vehicle",
	},
	"command_ship": {
		"name": "Командирский самолёт", "hp": 260, "armor": 2, "speed": 140.0, "radius": 17.0,
		"damage": 0, "range": 0.0, "cooldown": 1.0, "sight": 460.0,
		"cost": 200, "supply": 2, "time": 32.0, "hotkey": KEY_C, "unarmed": true, "air": true, "commands": "air",
	},
	# Scout: unarmed, very fast hover drone with huge sight; drops sensor beacons (F).
	"scout": {
		"name": "Разведдрон", "hp": 55, "armor": 0, "speed": 215.0, "radius": 10.0,
		"damage": 0, "range": 0.0, "cooldown": 1.0, "sight": 460.0,
		"cost": 60, "supply": 1, "time": 14.0, "hotkey": KEY_R, "unarmed": true,
		"beacon_cooldown": 25.0,
	},
	# Sensor beacon left by a Seeker: does not move, sees far, burns out after "lifetime" seconds.
	"beacon": {
		"name": "Сенсорный маяк", "hp": 40, "armor": 0, "speed": 0.0, "radius": 8.0,
		"damage": 0, "range": 0.0, "cooldown": 1.0, "sight": 380.0,
		"cost": 0, "supply": 0, "time": 0.0, "unarmed": true, "static": true, "lifetime": 90.0,
	},
	"tank": {
		"name": "Танк", "hp": 160, "armor": 4, "speed": 75.0, "radius": 16.0,
		"damage": 30, "range": 240.0, "cooldown": 2.2, "sight": 300.0, "splash": 40.0,
		"cost": 150, "supply": 3, "time": 25.0, "hotkey": KEY_T, "anti_air": false,
	},
	"wraith": {
		"name": "Истребитель", "hp": 120, "armor": 1, "speed": 150.0, "radius": 13.0,
		"damage": 10, "range": 150.0, "cooldown": 1.1, "sight": 280.0,
		"cost": 150, "supply": 2, "time": 28.0, "hotkey": KEY_V, "air": true,
	},
	# Heavy missile bomber: salvos of homing missiles against ground and air, splash damage.
	"stormbird": {
		"name": "Штурмовик", "hp": 280, "armor": 2, "speed": 125.0, "radius": 18.0,
		"damage": 32, "range": 240.0, "cooldown": 1.6, "sight": 340.0, "splash": 50.0,
		"cost": 300, "supply": 4, "time": 40.0, "hotkey": KEY_B, "air": true,
	},
	# Siege bomber: one huge bunker-buster missile at a time, only against buildings.
	"devastator": {
		"name": "Бомбардировщик", "hp": 280, "armor": 3, "speed": 105.0, "radius": 20.0,
		"damage": 120, "range": 200.0, "cooldown": 4.5, "sight": 340.0,
		"cost": 400, "supply": 5, "time": 50.0, "hotkey": KEY_N, "air": true, "buildings_only": true,
	},
	# Kamikaze drone: fast and fragile, dives into a building and explodes (dies on impact).
	"drone": {
		"name": "Дрон-камикадзе", "hp": 40, "armor": 0, "speed": 210.0, "radius": 9.0,
		"damage": 250, "range": 8.0, "cooldown": 1.0, "sight": 280.0,
		"cost": 100, "supply": 1, "time": 15.0, "hotkey": KEY_K, "air": true, "buildings_only": true,
		"kamikaze": true,
	},
	# Anti-air vehicle: long-range missiles that hit only flyers.
	"aa": {
		"name": "Зенитная установка", "hp": 140, "armor": 3, "speed": 95.0, "radius": 15.0,
		"damage": 20, "range": 280.0, "cooldown": 0.9, "sight": 330.0,
		"cost": 125, "supply": 2, "time": 22.0, "hotkey": KEY_Y, "air_only": true,
	},
	# Boss unit: one per side, trained at the Command Center once a Barracks is up.
	"titan": {
		"name": "Шагоход", "hp": 1400, "armor": 6, "speed": 50.0, "radius": 30.0,
		"damage": 40, "range": 220.0, "cooldown": 1.6, "sight": 320.0, "splash": 60.0,
		"cost": 500, "supply": 6, "time": 45.0, "hotkey": KEY_Y, "requires": "barracks", "limit": 1,
		# every Titan rolls its own stats: each value is multiplied by a random factor from [min, max]
		"random": {"hp": [0.7, 1.4], "damage": [0.6, 1.6], "range": [0.8, 1.3], "speed": [0.7, 1.4],
			"cooldown": [0.7, 1.4], "splash": [0.6, 1.6]},
		"titles": ["Гром", "Молот", "Колосс", "Бастион", "Жнец", "Циклоп", "Буря", "Атлас", "Голиаф", "Вулкан"],
	},
}

const BUILDINGS := {
	"cc": {
		"name": "Штаб", "short": "COMMAND", "hp": 1500, "armor": 3, "size": Vector2(130, 100),
		"cost": 400, "time": 70.0, "supply": 10, "trains": ["worker", "scout", "titan"], "hotkey": KEY_C,
	},
	"depot": {
		"name": "Склад", "short": "DEPOT", "hp": 400, "armor": 1, "size": Vector2(70, 70),
		"cost": 100, "time": 20.0, "supply": 8, "trains": [], "hotkey": KEY_V,
	},
	"barracks": {
		"name": "Казарма", "short": "BARRACKS", "hp": 1000, "armor": 2, "size": Vector2(110, 90),
		"cost": 150, "time": 40.0, "trains": ["marine", "medic", "officer"], "hotkey": KEY_B,
	},
	"factory": {
		"name": "Завод", "short": "FACTORY", "hp": 1250, "armor": 2, "size": Vector2(120, 90),
		"cost": 200, "time": 50.0, "trains": ["tank", "aa", "mechanic", "command_vehicle"], "hotkey": KEY_F, "requires": "barracks",
	},
	"bunker": {
		"name": "Бункер", "short": "BUNKER", "hp": 550, "armor": 4, "size": Vector2(80, 64),
		"cost": 100, "time": 25.0, "trains": [], "hotkey": KEY_U, "requires": "barracks",
		"damage": 7, "range": 150.0, "cooldown": 0.45, "anti_air": false,
	},
	"ebay": {
		"name": "Мастерская", "short": "ENG BAY", "hp": 850, "armor": 1, "size": Vector2(100, 80),
		"cost": 125, "time": 35.0, "trains": [], "research": ["weapons", "armor"], "hotkey": KEY_E,
	},
	"turret": {
		"name": "Зенитная турель", "short": "TURRET", "hp": 300, "armor": 2, "size": Vector2(50, 50),
		"cost": 100, "time": 20.0, "trains": [], "hotkey": KEY_T, "requires": "ebay",
		"damage": 12, "range": 230.0, "cooldown": 0.85, "air_bonus": 2.0,
	},
	"starport": {
		"name": "Аэродром", "short": "STARPORT", "hp": 1300, "armor": 2, "size": Vector2(120, 100),
		"cost": 200, "time": 50.0, "trains": ["wraith", "stormbird", "devastator", "drone", "command_ship"], "hotkey": KEY_P, "requires": "factory",
	},
	"silo": {
		"name": "Ракетная шахта", "short": "SILO", "hp": 600, "armor": 3, "size": Vector2(70, 70),
		"cost": 200, "time": 40.0, "trains": [], "hotkey": KEY_M, "requires": "ebay",
	},
}

## Missiles built in a Missile Silo (one loaded at a time) and launched (L + click) at a point no
## farther than "range" from the silo. Blasts hit everything, both sides: full damage at the
## centre, half at the edge of "radius".
##   cluster: splits into "bomblets" small blasts scattered over "radius";
##   napalm: a small blast, then the ground burns for "burn_time" s at "burn_dps".
const MISSILE_LAUNCH_KEY := KEY_L
const MISSILES := {
	"tactical": {"name": "Тактическая ракета", "key": KEY_M, "cost": 100, "time": 20.0, "damage": 220.0,
		"radius": 120.0, "range": 1500.0, "flight": 3.0},
	"cluster": {"name": "Кассетная ракета", "key": KEY_J, "cost": 175, "time": 30.0, "damage": 110.0,
		"radius": 220.0, "bomblets": 7, "bomblet_radius": 70.0, "range": 1500.0, "flight": 3.5},
	"napalm": {"name": "Напалм", "key": KEY_N, "cost": 150, "time": 30.0, "damage": 60.0,
		"radius": 160.0, "burn_dps": 35.0, "burn_time": 8.0, "range": 1500.0, "flight": 3.5},
	"heavy": {"name": "Тяжёлая ракета", "key": KEY_K, "cost": 300, "time": 50.0, "damage": 600.0,
		"radius": 210.0, "range": 1100.0, "flight": 5.0},
}

## Armour ("armor" on every unit and building) is subtracted from each hit, so light weapons barely
## scratch heavy targets (a marine's 6 does 2 to a tank with armour 4); every hit does at least 1.

## Target classes and weapon effectiveness. Every hit is multiplied by DAMAGE_VS[attacker][class of
## the target] (default 1.0) before armour is subtracted: tanks shred vehicles and buildings but are
## poor against infantry, rifles are poor against buildings, and so on.
const ARMOR_CLASS := {
	"worker": "infantry", "marine": "infantry", "medic": "infantry", "scout": "infantry", "beacon": "infantry",
	"officer": "infantry",
	"tank": "vehicle", "aa": "vehicle", "mechanic": "vehicle", "titan": "vehicle", "command_vehicle": "vehicle",
	"wraith": "air", "stormbird": "air", "devastator": "air", "drone": "air", "command_ship": "air",
}  # buildings are "building"
const CLASS_NAMES := {"infantry": "пехота", "vehicle": "техника", "air": "авиация", "building": "здания"}
const DAMAGE_VS := {
	"worker": {"building": 0.5},
	"marine": {"building": 0.8},
	"tank": {"infantry": 0.5, "vehicle": 1.5, "building": 2.0},
	"titan": {"infantry": 0.8, "vehicle": 1.3, "building": 1.5},
	"wraith": {"vehicle": 0.8, "air": 1.4, "building": 0.5},
	"stormbird": {"infantry": 1.2, "building": 0.7},
	"bunker": {"infantry": 1.3, "vehicle": 0.6},
	"turret": {"infantry": 0.5, "vehicle": 0.5, "air": 1.0},
}

## Squads: a commander takes up to "max" units of its class (select the commander together with
## the units and press KEY). Members within RADIUS of their living commander get the bonuses and
## follow it; ordering the commander orders the whole squad. The commander itself never shoots.
const SQUAD_KEY := KEY_Z
const SQUAD_DISBAND_KEY := KEY_U
const SQUAD_RADIUS := 380.0
const SQUADS := {
	"infantry": {"max": 6, "damage": 1.25, "armor": 2.0, "regen": 1.5, "excluded": ["worker", "scout", "beacon"]},
	"vehicle": {"max": 4, "damage": 1.2, "armor": 2.0, "regen": 0.0, "excluded": ["titan"]},
	"air": {"max": 4, "damage": 1.2, "armor": 1.0, "regen": 0.0, "excluded": ["drone"]},
}

## Factions. "human": the Terran-like colonists. "fog": the Silent Hill-like faction of the Fog —
## rusted, blood-stained structures and twisted creatures. Same roles and stats per kind (so the AI
## and balance stay shared), different names and models; every Fog unit and building slowly
## regenerates instead of relying on medics and mechanics alone.
const FACTION_NAMES := {"human": "Люди", "fog": "Туман"}
const FOG_REGEN := 1.5  # HP per second for Fog units and finished buildings
const FOG_NAMES := {
	"worker": "Сборщик", "marine": "Кокон", "medic": "Сиделка", "officer": "Вестник", "scout": "Глаз",
	"beacon": "Ржавый колокол", "tank": "Зверь", "aa": "Крикун", "mechanic": "Ткач",
	"command_vehicle": "Пастырь", "wraith": "Летун", "stormbird": "Рой", "devastator": "Чрево",
	"drone": "Мотылёк", "command_ship": "Проводник", "titan": "Палач",
	"cc": "Алтарь", "depot": "Склеп", "barracks": "Лечебница", "bunker": "Клетка", "ebay": "Мастерская плоти",
	"turret": "Сирена", "factory": "Скотобойня", "starport": "Гнездо", "silo": "Колодец",
}

## Ages, advanced at the Command Center (E), one after another like in Age of Empires.
## Index = age number (1 is the starting age). Every new age doubles building durability;
## from age 3 buildings get a regenerating energy shield; age 4 also boosts units.
const AGE_KEY := KEY_E
const AGES := [
	{},
	{"name": "Эпоха колонии", "short": "I"},
	{"name": "Индустриальная эпоха", "short": "II", "cost": 300, "time": 45.0, "requires": "barracks",
		"bonus": "прочность зданий ×2"},
	{"name": "Энергетическая эпоха", "short": "III", "cost": 500, "time": 60.0, "requires": "factory",
		"bonus": "прочность зданий ×2, восстанавливающийся щит зданий (30% прочности)"},
	{"name": "Звёздная эпоха", "short": "IV", "cost": 800, "time": 80.0, "requires": "starport",
		"bonus": "прочность зданий ×2, щит 60%, юниты +25% HP и урона"},
]
const AGE_SHIELD := [0.0, 0.0, 0.0, 0.3, 0.6]  # building shield as a share of max HP, per age
const AGE_UNIT_BONUS := 1.25                    # unit HP and damage multiplier in the last age

## Team-wide research done in the Engineering Bay.
const UPGRADES := {
	# Each level: +10% (at least +1) to damage / armour, stacking: level 2 = +20% (at least +2), ...
	"weapons": {"name": "Оружие", "cost": [100, 175, 250], "time": 40.0, "hotkey": KEY_G, "max": 3},
	"armor": {"name": "Броня", "cost": [100, 175, 250], "time": 40.0, "hotkey": KEY_R, "max": 3},
}

const WORKER_BUILDS := ["depot", "barracks", "bunker", "ebay", "turret", "factory", "starport", "silo", "cc"]
const MAX_SUPPLY := 200
