extends RefCounted
## Static game data: unit and building stats.

const UNITS := {
	"worker": {
		"name": "SCV (рабочий)", "hp": 45, "speed": 120.0, "radius": 9.0,
		"damage": 5, "range": 6.0, "cooldown": 1.5, "sight": 160.0,
		"cost": 50, "supply": 1, "time": 12.0, "hotkey": KEY_Q, "anti_air": false,
	},
	"marine": {
		"name": "Marine (пехотинец)", "hp": 45, "speed": 105.0, "radius": 10.0,
		"damage": 6, "range": 130.0, "cooldown": 0.65, "sight": 240.0,
		"cost": 50, "supply": 1, "time": 14.0, "hotkey": KEY_Q, "anti_air": false,
	},
	"tank": {
		"name": "Siege Tank (танк)", "hp": 160, "speed": 75.0, "radius": 16.0,
		"damage": 30, "range": 240.0, "cooldown": 2.2, "sight": 300.0, "splash": 40.0,
		"cost": 150, "supply": 3, "time": 25.0, "hotkey": KEY_T, "anti_air": false,
	},
	"wraith": {
		"name": "Wraith (истребитель)", "hp": 120, "speed": 150.0, "radius": 13.0,
		"damage": 10, "range": 150.0, "cooldown": 1.1, "sight": 280.0,
		"cost": 150, "supply": 2, "time": 28.0, "hotkey": KEY_V, "air": true,
	},
	# Heavy missile bomber: salvos of homing missiles against ground and air, splash damage.
	"stormbird": {
		"name": "Stormbird (ракетоносец)", "hp": 280, "speed": 125.0, "radius": 18.0,
		"damage": 32, "range": 240.0, "cooldown": 1.6, "sight": 340.0, "splash": 50.0,
		"cost": 300, "supply": 4, "time": 40.0, "hotkey": KEY_B, "air": true,
	},
	# Siege bomber: one huge bunker-buster missile at a time, only against buildings.
	"devastator": {
		"name": "Devastator (бомбардировщик)", "hp": 340, "speed": 105.0, "radius": 20.0,
		"damage": 260, "range": 270.0, "cooldown": 3.5, "sight": 340.0,
		"cost": 400, "supply": 5, "time": 50.0, "hotkey": KEY_N, "air": true, "buildings_only": true,
	},
	# Anti-air vehicle: long-range missiles that hit only flyers.
	"aa": {
		"name": "AA Rover (ПВО)", "hp": 140, "speed": 95.0, "radius": 15.0,
		"damage": 20, "range": 280.0, "cooldown": 0.9, "sight": 330.0,
		"cost": 125, "supply": 2, "time": 22.0, "hotkey": KEY_Y, "air_only": true,
	},
	# Boss unit: one per side, trained at the Command Center once a Barracks is up.
	"titan": {
		"name": "Titan (босс)", "hp": 1400, "speed": 50.0, "radius": 30.0,
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
		"name": "Command Center", "short": "COMMAND", "hp": 1500, "size": Vector2(130, 100),
		"cost": 400, "time": 70.0, "supply": 10, "trains": ["worker", "titan"], "hotkey": KEY_C,
	},
	"depot": {
		"name": "Supply Depot", "short": "DEPOT", "hp": 400, "size": Vector2(70, 70),
		"cost": 100, "time": 20.0, "supply": 8, "trains": [], "hotkey": KEY_V,
	},
	"barracks": {
		"name": "Barracks", "short": "BARRACKS", "hp": 1000, "size": Vector2(110, 90),
		"cost": 150, "time": 40.0, "trains": ["marine"], "hotkey": KEY_B,
	},
	"factory": {
		"name": "Factory", "short": "FACTORY", "hp": 1250, "size": Vector2(120, 90),
		"cost": 200, "time": 50.0, "trains": ["tank", "aa"], "hotkey": KEY_F, "requires": "barracks",
	},
	"bunker": {
		"name": "Bunker", "short": "BUNKER", "hp": 550, "size": Vector2(80, 64),
		"cost": 100, "time": 25.0, "trains": [], "hotkey": KEY_U, "requires": "barracks",
		"damage": 7, "range": 150.0, "cooldown": 0.45, "anti_air": false,
	},
	"ebay": {
		"name": "Engineering Bay", "short": "ENG BAY", "hp": 850, "size": Vector2(100, 80),
		"cost": 125, "time": 35.0, "trains": [], "research": ["weapons", "armor"], "hotkey": KEY_E,
	},
	"turret": {
		"name": "Missile Turret", "short": "TURRET", "hp": 300, "size": Vector2(50, 50),
		"cost": 100, "time": 20.0, "trains": [], "hotkey": KEY_T, "requires": "ebay",
		"damage": 12, "range": 230.0, "cooldown": 0.85, "air_bonus": 2.0,
	},
	"starport": {
		"name": "Starport", "short": "STARPORT", "hp": 1300, "size": Vector2(120, 100),
		"cost": 200, "time": 50.0, "trains": ["wraith", "stormbird", "devastator"], "hotkey": KEY_P, "requires": "factory",
	},
	"silo": {
		"name": "Missile Silo", "short": "SILO", "hp": 600, "size": Vector2(70, 70),
		"cost": 200, "time": 40.0, "trains": [], "hotkey": KEY_M, "requires": "ebay",
	},
}

## Missile built in a Missile Silo and launched at any point of the map. It hits everything
## (both sides!) within radius: full damage at the centre, half at the edge.
const MISSILE := {"name": "Ракета", "cost": 150, "time": 30.0, "damage": 320.0, "radius": 170.0,
	"flight": 4.0, "arm_key": KEY_M, "launch_key": KEY_L}

## Team-wide research done in the Engineering Bay.
const UPGRADES := {
	"weapons": {"name": "Оружие", "cost": [100, 175], "time": 40.0, "hotkey": KEY_G, "max": 2},
	"armor": {"name": "Броня", "cost": [100, 175], "time": 40.0, "hotkey": KEY_R, "max": 2},
}

const WORKER_BUILDS := ["depot", "barracks", "bunker", "ebay", "turret", "factory", "starport", "silo", "cc"]
const MAX_SUPPLY := 200
