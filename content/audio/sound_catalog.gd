class_name GameSoundCatalog
extends Resource
## Explicit stream dependencies keep the catalog usable in exported games.

@export var schema_version: int = 1
@export var clips: Array[GameSoundClip] = []

func find_clip(id: StringName) -> GameSoundClip:
	for clip: GameSoundClip in clips:
		if clip.id == id:
			return clip
	return null

func variants(family: StringName) -> Array[GameSoundClip]:
	var result: Array[GameSoundClip] = []
	for clip: GameSoundClip in clips:
		if clip.family == family:
			result.append(clip)
	return result
