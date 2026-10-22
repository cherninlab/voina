class_name GameMaps
extends RefCounted
## Every playable map. The host picks one in the lobby (or with --dungeon / --map=ID before an
## automatic --host or --server); joiners take the host's map during authentication, before anyone
## spawns. The village stays the default.

const VILLAGE: String = "village"
const CRYPT: String = "crypt"
const WHITE_ROOM: String = "white_room"
const LONG_GRASS: String = "long_grass"
const IDS: Array[String] = [VILLAGE, CRYPT, WHITE_ROOM, LONG_GRASS]
const TITLES: Array[String] = ["Village", "Cinder Crypt", "White Room", "Long Grass"]
# A shading theme (ui/shading.gd) the map is shown in; empty keeps the player's own.
const SHADING: Array[String] = ["", "", "Overexposed", ""]
# Per map, per theme: shading values laid over that theme's defaults on this map only, so a theme
# tuned for daylight still reads on a night map. Map id -> {theme name -> {param: value}}.
const SHADING_ADJUST: Dictionary = {
	LONG_GRASS: {"Risograph": {"exposure": 1.4}},
}

static func from_arguments(arguments: PackedStringArray) -> String:
	for argument: String in arguments:
		if argument.begins_with("--map=") and argument.trim_prefix("--map=") in IDS:
			return argument.trim_prefix("--map=")
	return CRYPT if "--dungeon" in arguments else VILLAGE

static func title(id: String) -> String:
	return TITLES[maxi(0, IDS.find(id))]

static func shading(id: String) -> String:
	return SHADING[maxi(0, IDS.find(id))]

static func shading_adjust(id: String) -> Dictionary:
	return SHADING_ADJUST.get(id, {}) as Dictionary

# Each map's encounter: the village's switchable church yard and raiders, the crypt's five
# cultists, the white room's endless raiders, or the long grass's campfire cultists.
static func create_mobs(id: String) -> MobSystem:
	if id == CRYPT:
		return preload("res://gameplay/mobs/dungeon_mobs.gd").new()
	if id == WHITE_ROOM:
		return preload("res://gameplay/mobs/wave_mobs.gd").new()
	if id == LONG_GRASS:
		return preload("res://gameplay/mobs/camp_mobs.gd").new()
	return MobSystem.new()
