class_name GameMaps
extends RefCounted
## Every playable map. The host picks one in the lobby (or with --dungeon / --map=ID before an
## automatic --host or --server); joiners take the host's map during authentication, before anyone
## spawns. The village stays the default.

const VILLAGE: String = "village"
const CRYPT: String = "crypt"
const WHITE_ROOM: String = "white_room"
const IDS: Array[String] = [VILLAGE, CRYPT, WHITE_ROOM]
const TITLES: Array[String] = ["Village", "Cinder Crypt", "White Room"]

static func from_arguments(arguments: PackedStringArray) -> String:
	for argument: String in arguments:
		if argument.begins_with("--map=") and argument.trim_prefix("--map=") in IDS:
			return argument.trim_prefix("--map=")
	return CRYPT if "--dungeon" in arguments else VILLAGE

static func title(id: String) -> String:
	return TITLES[maxi(0, IDS.find(id))]

# Each map's encounter: the village's switchable church yard and raiders, the crypt's five
# cultists, or the white room's endless raiders.
static func create_mobs(id: String) -> MobSystem:
	if id == CRYPT:
		return preload("res://gameplay/mobs/dungeon_mobs.gd").new()
	if id == WHITE_ROOM:
		return preload("res://gameplay/mobs/wave_mobs.gd").new()
	return MobSystem.new()
