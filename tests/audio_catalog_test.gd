extends SceneTree

func _initialize() -> void:
	var catalog: GameSoundCatalog = load("res://content/audio/catalog.tres") as GameSoundCatalog
	assert(catalog != null)
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/audio/catalog.json")) as Dictionary
	var rows: Array = parsed["clips"] as Array
	assert(catalog.clips.size() == rows.size())
	var seen: Dictionary[StringName, bool] = {}
	for index: int in range(catalog.clips.size()):
		var clip: GameSoundClip = catalog.clips[index]
		var row: Dictionary = rows[index] as Dictionary
		assert(not seen.has(clip.id))
		seen[clip.id] = true
		assert(String(clip.id) == String(row["id"]))
		assert(clip.stream != null, "Every database record must load an imported AudioStream")
		assert(absf(clip.stream.get_length() - clip.duration_seconds) < 0.01)
		assert(clip.frame_count == int(row["frame_count"]))
		assert(clip.source_end_frame - clip.source_start_frame == clip.frame_count)
		assert(clip.sample_rate == 48000)
		assert(clip.onset_frame >= 0 and clip.energy_peak_frame >= clip.onset_frame)
		assert(clip.energy_peak_frame < clip.active_end_frame and clip.active_end_frame <= clip.frame_count)
		assert(clip.stream.instantiate_playback() != null)
		if clip.stream is AudioStreamWAV:
			var wav: AudioStreamWAV = clip.stream as AudioStreamWAV
			assert(wav.mix_rate == 48000 and not wav.stereo)
			assert(wav.format == AudioStreamWAV.FORMAT_16_BITS)
			assert(wav.data.size() == clip.frame_count * 2)
			assert(wav.loop_mode == AudioStreamWAV.LOOP_DISABLED)
		if clip.stream is AudioStreamOggVorbis:
			assert(not (clip.stream as AudioStreamOggVorbis).loop)
	assert(catalog.variants(&"sword_metal_slide").size() == 6)
	assert(catalog.variants(&"heavy_swing_thud").size() == 21)
	assert(catalog.variants(&"wood_weapon_impact").size() == 16)
	assert(catalog.variants(&"body_punch").size() == 4)
	assert(catalog.find_clip(&"sword_metal_slide_01") != null)
	assert(catalog.find_clip(&"missing") == null)
	assert(catalog.variants(&"missing").is_empty())
	print("AUDIO_CATALOG_OK: %d streams load with source intervals, bounded timing markers and variant lookup" % catalog.clips.size())
	quit()
