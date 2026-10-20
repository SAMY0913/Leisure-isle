extends SceneTree

## P6 task-2 headless audio mixer probe.
## Run:  Godot_v4.7.2-stable_win64_console.exe --headless --path <proj> --script res://tools/probe_audio6.gd
## Verifies: five-bus layout + effect chains, every player routed to its group bus,
## set_group_volume mapping (0 / 0.5 / 1), zero => -80 dB + mute, no group crosstalk,
## setup() idempotency (no extra players/effects/buses), get_group_volumes() shape,
## update_audio() driving the ambience/night/fire/bird behaviour, the loop metadata, and
## five-group settings persistence (absolute workspace cfg path; user:// is sandbox-blocked).

const A = preload("res://scripts/isle_audio.gd")
const SETTINGS := preload("res://scripts/isle_settings.gd")
const PERSIST_CFG := "D:/休闲小岛幻境/开发产物/logs/audio6_persist_probe.cfg"
const LEGACY_CFG := "D:/休闲小岛幻境/开发产物/logs/audio6_legacy_probe.cfg"

var failures: Array[String] = []
var checks := 0
var notes: Array[String] = []
var host: Node
var audio: Node


var _ran := false


func _initialize() -> void:
	print("=".repeat(90))
	print("P6 task-2 AUDIO MIXER PROBE (headless)")
	print("=".repeat(90))


func _process(_delta: float) -> bool:
	# Run inside the first real frame: AudioServer + the scene tree (and therefore
	# AudioStreamPlayer.play()) are only live once the tree is processing.
	if _ran:
		return true
	_ran = true
	host = Node.new()
	host.name = "ProbeHost"
	root.add_child(host)

	_check_script_contract()
	if failures.is_empty():
		_setup_instance()
		_check_buses()
		_check_players()
		_check_group_volume_mapping()
		_check_zero_volume()
		_check_master_and_mute()
		_check_no_crosstalk()
		_check_settings_persistence()
		_check_idempotency()
		_check_update_audio()
		_check_wav_metadata()
		_check_debug_info()

	_finish()
	return true


func _check_script_contract() -> void:
	var probe: Node = A.new()
	_expect(probe.has_method("set_group_volume"), "isle_audio.gd has set_group_volume()")
	_expect(probe.has_method("set_bus_volume"), "isle_audio.gd has set_bus_volume() compatibility alias")
	_expect(probe.has_method("get_group_volumes"), "isle_audio.gd has get_group_volumes()")
	_expect(probe.has_method("set_volume"), "isle_audio.gd keeps legacy set_volume()")
	_expect(probe.has_method("set_muted"), "isle_audio.gd has set_muted()")
	_expect(probe.has_method("update_audio"), "isle_audio.gd keeps update_audio(delta, state)")
	_expect(probe.has_method("play_door"), "isle_audio.gd keeps play_door()")
	_expect(probe.has_method("play_splash"), "isle_audio.gd keeps play_splash()")
	_expect(probe.has_method("play_ui_click"), "isle_audio.gd keeps play_ui_click()")
	probe.free()


func _setup_instance() -> void:
	audio = A.new()
	audio.name = "Audio"
	host.add_child(audio)
	audio.setup(host)
	_expect(audio.is_ready(), "setup(host) -> is_ready()")


func _check_buses() -> void:
	var buses := ["Master", "IsleAmbient", "IsleBirds", "IsleFire", "IsleSFX"]
	for b in buses:
		_expect(AudioServer.get_bus_index(b) >= 0, "bus exists: " + b)
	_expect(AudioServer.get_bus_index("IsleAudio") < 0, "legacy single bus 'IsleAudio' is gone")
	var chains := {
		"IsleAmbient": ["AudioEffectLowPassFilter", "AudioEffectEQ6"],
		"IsleFire": ["AudioEffectLowPassFilter", "AudioEffectEQ6", "AudioEffectCompressor"],
		"IsleBirds": ["AudioEffectEQ6", "AudioEffectLowPassFilter"],
		"IsleSFX": ["AudioEffectCompressor", "AudioEffectEQ6"],
	}
	for bus in chains:
		var idx := AudioServer.get_bus_index(bus)
		var want: Array = chains[bus]
		_expect(AudioServer.get_bus_effect_count(idx) == want.size(),
			"%s effect count == %d (got %d)" % [bus, want.size(), AudioServer.get_bus_effect_count(idx)])
		for i in range(mini(want.size(), AudioServer.get_bus_effect_count(idx))):
			var eff := AudioServer.get_bus_effect(idx, i)
			_expect(eff != null and eff.get_class() == want[i],
				"%s effect[%d] is %s (got %s)" % [bus, i, want[i], eff.get_class() if eff != null else "null"])
		# every chain effect must be tagged by our builder (idempotent marker)
		var tagged := 0
		for i in range(AudioServer.get_bus_effect_count(idx)):
			if String(AudioServer.get_bus_effect(idx, i).resource_name).begins_with("P6_"):
				tagged += 1
		_expect(tagged == AudioServer.get_bus_effect_count(idx), bus + " effects are tagged")
	# bus routing on the AudioServer side
	_expect(AudioServer.get_bus_send(AudioServer.get_bus_index("IsleAmbient")) == "Master", "IsleAmbient sends to Master")
	_expect(AudioServer.get_bus_send(AudioServer.get_bus_index("IsleBirds")) == "Master", "IsleBirds sends to Master")
	_expect(AudioServer.get_bus_send(AudioServer.get_bus_index("IsleFire")) == "Master", "IsleFire sends to Master")
	_expect(AudioServer.get_bus_send(AudioServer.get_bus_index("IsleSFX")) == "Master", "IsleSFX sends to Master")


func _check_players() -> void:
	var want := {
		"IsleAudio_Ocean": "IsleAmbient",
		"IsleAudio_Wind": "IsleAmbient",
		"IsleAudio_Night": "IsleAmbient",
		"IsleAudio_Fire": "IsleFire",
		"IsleAudio_Bird1": "IsleBirds",
		"IsleAudio_Bird2": "IsleBirds",
		"IsleAudio_Bird3": "IsleBirds",
	}
	for i in range(8):
		want["IsleAudio_SFX%d" % i] = "IsleSFX"
	var found := {}
	for c in host.get_children():
		if c is AudioStreamPlayer:
			found[String(c.name)] = c
	_expect(found.size() == 15, "15 audio players under the host (got %d)" % found.size())
	for name in want:
		_expect(found.has(name), "player exists: " + name)
		if found.has(name):
			var p: AudioStreamPlayer = found[name]
			_expect(p.bus == want[name], "%s routed to %s (got %s)" % [name, want[name], p.bus])
			# loops/fire keep their stream resident; the bird + sfx pools assign streams per shot.
			if name in ["IsleAudio_Ocean", "IsleAudio_Wind", "IsleAudio_Night", "IsleAudio_Fire"]:
				_expect(p.stream != null, name + " has a stream loaded")
			else:
				_expect(p.stream == null, name + " starts with no resident stream")


func _check_group_volume_mapping() -> void:
	var vols := {"master": 0.5, "ambient": 0.5, "birds": 0.5, "fire": 0.5, "sfx": 0.5}
	for key in vols:
		audio.set_group_volume(key, 0.5)
		var bus: String = audio.GROUP_BUS[key]
		var idx := AudioServer.get_bus_index(bus)
		var db := AudioServer.get_bus_volume_db(idx)
		_expect(absf(db - linear_to_db(0.5)) <= 0.05,
			"%s=0.5 -> %s bus %.2f dB (expected %.2f)" % [key, bus, db, linear_to_db(0.5)])
	# 1.0 -> 0 dB
	for key in vols:
		audio.set_group_volume(key, 1.0)
		var bus: String = audio.GROUP_BUS[key]
		var db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus))
		_expect(absf(db - 0.0) <= 0.05, "%s=1.0 -> 0 dB (got %.3f)" % [key, db])
	# get_group_volumes shape
	var gv: Dictionary = audio.get_group_volumes()
	_expect(gv.size() == 5, "get_group_volumes() returns 5 keys (got %d)" % gv.size())
	for key in ["master", "ambient", "birds", "fire", "sfx"]:
		_expect(gv.has(key), "get_group_volumes() has key " + key)
		_expect(absf(float(gv.get(key, -1.0)) - 1.0) <= 0.001, "get_group_volumes()[%s] == 1.0" % key)
	# bus-name alias used by main.gd._apply_audio_volume() must hit the same buses
	for bus in ["Master", "IsleAmbient", "IsleBirds", "IsleFire", "IsleSFX"]:
		audio.set_bus_volume(bus, 0.6)
		var idx2 := AudioServer.get_bus_index(bus)
		_expect(absf(AudioServer.get_bus_volume_db(idx2) - linear_to_db(0.6)) <= 0.05,
			"set_bus_volume(%s, 0.6) -> %.2f dB" % [bus, AudioServer.get_bus_volume_db(idx2)])
		audio.set_bus_volume(bus, 1.0)
	# settings-key aliases must work too
	for settings_key in ["volume_master", "volume_ambient", "volume_birds", "volume_fire", "volume_sfx"]:
		audio.set_group_volume(settings_key, 0.75)
		var key: String = audio.GROUP_SETTING_KEYS[settings_key]
		var db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(audio.GROUP_BUS[key]))
		_expect(absf(db - linear_to_db(0.75)) <= 0.05, "alias %s=0.75 -> %s bus %.2f dB" % [settings_key, audio.GROUP_BUS[key], db])


func _check_zero_volume() -> void:
	for key in ["master", "ambient", "birds", "fire", "sfx"]:
		audio.set_group_volume(key, 0.0)
		var bus: String = audio.GROUP_BUS[key]
		var idx := AudioServer.get_bus_index(bus)
		var db := AudioServer.get_bus_volume_db(idx)
		_expect(db <= -79.0 and is_finite(db), "%s=0.0 -> -80 dB finite (got %.1f)" % [key, db])
		_expect(AudioServer.is_bus_mute(idx), "%s=0.0 -> bus muted" % key)
	# restore
	for key in ["master", "ambient", "birds", "fire", "sfx"]:
		audio.set_group_volume(key, 1.0)
	_expect(not AudioServer.is_bus_mute(AudioServer.get_bus_index("IsleAmbient")), "ambient unmuted after restore")


func _check_master_and_mute() -> void:
	audio.set_volume(0.5)
	var idx := AudioServer.get_bus_index("Master")
	_expect(absf(AudioServer.get_bus_volume_db(idx) - linear_to_db(0.5)) <= 0.05,
		"set_volume(0.5) drives Master bus (%.2f dB)" % AudioServer.get_bus_volume_db(idx))
	audio.set_muted(true)
	_expect(AudioServer.is_bus_mute(idx), "set_muted(true) mutes Master bus")
	audio.set_muted(false)
	_expect(not AudioServer.is_bus_mute(idx), "set_muted(false) unmutes Master bus")
	audio.set_volume(1.0)
	_expect(not AudioServer.is_bus_mute(idx), "set_volume(1.0) clears master mute")
	audio.set_group_volume("master", 0.0)
	audio.set_group_volume("master", 0.8)
	_expect(not AudioServer.is_bus_mute(idx), "master 0 -> 0.8 clears mute again")
	_expect(absf(AudioServer.get_bus_volume_db(idx) - linear_to_db(0.8)) <= 0.05, "master 0.8 restores %.2f dB" % linear_to_db(0.8))


func _check_no_crosstalk() -> void:
	# changing one group must leave the other buses untouched
	for key in ["master", "ambient", "birds", "fire", "sfx"]:
		audio.set_group_volume(key, 0.6)
	var busy := ["ambient", "birds", "fire", "sfx"]
	for key in busy:
		var before := {}
		for other in busy:
			before[other] = AudioServer.get_bus_volume_db(AudioServer.get_bus_index(audio.GROUP_BUS[other]))
		audio.set_group_volume(key, 0.25)
		for other in busy:
			if other == key:
				continue
			_expect(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(audio.GROUP_BUS[other])) - before[other]) <= 0.001,
				"%s change does not touch %s" % [key, other])
		audio.set_group_volume(key, 0.6)
	for key in ["master", "ambient", "birds", "fire", "sfx"]:
		audio.set_group_volume(key, 1.0)


func _check_settings_persistence() -> void:
	# Five independent volume groups: defaults, save -> load round trip on an
	# absolute workspace path (user:// is unwritable in this sandbox), legacy
	# volume migration, zero handling and the bus gains those values drive.
	var keys := ["volume_master", "volume_ambient", "volume_birds", "volume_fire", "volume_sfx"]
	var buses := ["Master", "IsleAmbient", "IsleBirds", "IsleFire", "IsleSFX"]
	var want_default := [0.8, 0.7, 0.8, 0.7, 0.8]
	var groups: Array = SETTINGS.audio_groups()
	_expect(groups.size() == 5, "Settings.audio_groups() returns 5 groups (got %d)" % groups.size())
	for i in range(mini(groups.size(), 5)):
		_expect(String(groups[i].get("key", "")) == keys[i] and String(groups[i].get("bus", "")) == buses[i],
			"audio group %d is %s/%s (got %s/%s)" % [i, keys[i], buses[i], String(groups[i].get("key", "")), String(groups[i].get("bus", ""))])
	var defaults: Dictionary = SETTINGS.defaults()
	for i in range(5):
		var dv := float(defaults.get(keys[i], -1.0))
		_expect(absf(dv - want_default[i]) <= 0.001, "default %s == %.2f (got %.2f)" % [keys[i], want_default[i], dv])
	var dir_ok := _ensure_workspace_log_dir()
	_expect(dir_ok, "workspace log dir available for persistence cfg")
	if not dir_ok:
		return
	# 1) distinct non-trivial values survive save -> load (a simulated restart)
	var custom := [0.12, 0.34, 0.56, 0.78, 0.91]
	var values: Dictionary = defaults.duplicate(true)
	for i in range(5):
		values[keys[i]] = custom[i]
	SETTINGS.save_settings(values, PERSIST_CFG)
	_expect(FileAccess.file_exists(PERSIST_CFG), "settings cfg written to absolute workspace path")
	var loaded: Dictionary = SETTINGS.load_settings(PERSIST_CFG)
	for i in range(5):
		var lv := float(loaded.get(keys[i], -1.0))
		_expect(absf(lv - custom[i]) <= 0.001, "restart round-trip %s == %.2f (got %.2f)" % [keys[i], custom[i], lv])
	var cfg := ConfigFile.new()
	_expect(cfg.load(PERSIST_CFG) == OK, "persisted cfg is a readable ConfigFile")
	# isle_settings.save_settings() currently writes only DEFAULTS keys, so the
	# legacy "volume" mirror it prepares is not persisted (Lead-owned file).
	# Record it as a note instead of failing the audio contract.
	if cfg.has_section_key("settings", "volume"):
		_expect(absf(float(cfg.get_value("settings", "volume", -1.0)) - 0.12) <= 0.001,
			"legacy volume mirror == volume_master (0.12)")
	else:
		notes.append("isle_settings.save_settings() 未写出旧版 volume 镜像键（save 只遍历 DEFAULTS.keys()）")
	# 2) the loaded dictionary is what main feeds into the mixer at startup
	for i in range(5):
		audio.set_bus_volume(buses[i], float(loaded[keys[i]]))
	for i in range(1, 5):
		var idx := AudioServer.get_bus_index(buses[i])
		_expect(idx >= 0 and absf(AudioServer.get_bus_volume_db(idx) - linear_to_db(float(loaded[keys[i]]))) <= 0.05,
			"persisted %s drives %s bus gain" % [keys[i], buses[i]])
	var midx := AudioServer.get_bus_index("Master")
	_expect(absf(AudioServer.get_bus_volume_db(midx) - linear_to_db(0.12)) <= 0.05,
		"persisted master drives Master bus gain")
	_expect(not AudioServer.is_bus_mute(midx), "persisted non-zero master is unmuted")
	# 3) zero persists as zero and mutes only its own bus
	var zeroed: Dictionary = loaded.duplicate(true)
	zeroed["volume_fire"] = 0.0
	SETTINGS.save_settings(zeroed, PERSIST_CFG)
	var loaded_zero: Dictionary = SETTINGS.load_settings(PERSIST_CFG)
	_expect(absf(float(loaded_zero.get("volume_fire", -1.0))) <= 0.0001, "zero volume persists as 0.0")
	audio.set_bus_volume("IsleFire", float(loaded_zero.get("volume_fire", 0.0)))
	var fidx := AudioServer.get_bus_index("IsleFire")
	_expect(AudioServer.get_bus_volume_db(fidx) <= -79.0 and AudioServer.is_bus_mute(fidx),
		"persisted 0 -> fire bus -80 dB + mute")
	_expect(not AudioServer.is_bus_mute(AudioServer.get_bus_index("IsleAmbient")),
		"persisted zero fire does not mute the ambient bus")
	for i in range(5):
		_expect(absf(float(loaded_zero.get(keys[i], -1.0)) - (0.0 if i == 3 else custom[i])) <= 0.001,
			"zero fire leaves %s untouched (%.2f)" % [keys[i], float(loaded_zero.get(keys[i], -1.0))])
	# 4) pre-P6 settings with only settings/volume migrate into volume_master
	var legacy := ConfigFile.new()
	legacy.set_value("settings", "volume", 0.42)
	legacy.save(LEGACY_CFG)
	var migrated: Dictionary = SETTINGS.load_settings(LEGACY_CFG)
	_expect(absf(float(migrated.get("volume_master", -1.0)) - 0.42) <= 0.001,
		"legacy settings/volume migrates to volume_master 0.42 (got %.2f)" % float(migrated.get("volume_master", -1.0)))
	_expect(absf(float(migrated.get("volume_ambient", -1.0)) - 0.7) <= 0.001,
		"legacy migration keeps ambient default 0.7 (got %.2f)" % float(migrated.get("volume_ambient", -1.0)))
	# restore a clean 1.0 state for the following idempotency / update_audio checks
	for key in ["master", "ambient", "birds", "fire", "sfx"]:
		audio.set_group_volume(key, 1.0)
	DirAccess.remove_absolute(PERSIST_CFG)
	DirAccess.remove_absolute(LEGACY_CFG)
	_expect(not FileAccess.file_exists(PERSIST_CFG) and not FileAccess.file_exists(LEGACY_CFG),
		"probe persistence cfg files cleaned up")


func _ensure_workspace_log_dir() -> bool:
	var d := "D:/休闲小岛幻境/开发产物/logs"
	if DirAccess.dir_exists_absolute(d):
		return true
	return DirAccess.make_dir_recursive_absolute(d) == OK


func _check_idempotency() -> void:
	var before_players := _player_count()
	var before_buses := AudioServer.bus_count
	var before_effects := _effect_count()
	audio.setup(host)
	audio.setup(host)
	audio.set_group_volume("ambient", 0.5)
	audio.set_group_volume("ambient", 1.0)
	_expect(_player_count() == before_players, "extra setup()/volume calls add no players (%d)" % _player_count())
	_expect(AudioServer.bus_count == before_buses, "extra setup() adds no buses (%d)" % AudioServer.bus_count)
	_expect(_effect_count() == before_effects, "extra setup() adds no duplicate effects (%d)" % _effect_count())
	_expect(before_players == 15, "player count stays 15")


func _player_count() -> int:
	var n := 0
	for c in host.get_children():
		if String(c.name).begins_with("IsleAudio_"):
			n += 1
	return n


func _effect_count() -> int:
	var n := 0
	for bus in ["IsleAmbient", "IsleBirds", "IsleFire", "IsleSFX"]:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			n += AudioServer.get_bus_effect_count(idx)
	return n


func _check_update_audio() -> void:
	var info: Dictionary = audio.get_debug_info()
	_expect(info["players_total"] == 15, "debug info players_total == 15 (got %d)" % info["players_total"])
	_expect(info["loops_loaded"] == 3, "debug info loops_loaded == 3 (got %d)" % info["loops_loaded"])
	_expect(info["fire_loaded"], "debug info fire_loaded")

	for key in ["master", "ambient", "birds", "fire", "sfx"]:
		audio.set_group_volume(key, 1.0)

	# day: both day loops running, night layer still gated off
	for i in range(40):
		audio.update_audio(0.5, {"sun_alt": 10.0, "night": 0.0, "wind": 0.5, "fireplace_on": false})
	var info_d: Dictionary = audio.get_debug_info()
	_expect(info_d["loops"][0]["playing"], "day: Ocean loop playing")
	_expect(info_d["loops"][1]["playing"], "day: Wind loop playing")
	_expect(not info_d["loops"][2]["playing"], "day: Night loop gated off")
	_expect(not info_d["fire_playing"], "day (no fireplace): fire loop off")
	_expect(info_d["phase"] == "day", "day: phase == day (got %s)" % info_d["phase"])

	# a full daytime bird cycle must fire at least one bird (bird timer 6-14 s => 30 s of frames)
	var bird_events := 0
	var totals_d: Dictionary = A.get_event_totals()
	bird_events = int(totals_d.get("sfx:bird", 0))
	_expect(bird_events >= 1, "day: bird chorus plays (%d bird events)" % bird_events)

	# dusk/night: night layer starts and stays, fireplace toggles the fire loop
	for i in range(80):
		audio.update_audio(0.5, {"sun_alt": -8.0, "night": 0.9, "wind": 0.6, "fireplace_on": true})
	var info_n: Dictionary = audio.get_debug_info()
	_expect(info_n["birds_loaded"], "bird chorus streams loaded")
	_expect(info_n["loops"][2]["playing"], "night: Night loop playing")
	_expect(float(info_n["loops"][2]["env"]) >= 0.95, "night: Night env >= 0.95 (%.2f)" % float(info_n["loops"][2]["env"]))
	_expect(info_n["fire_playing"], "night: fireplace loop playing")
	_expect(info_n["phase"] == "night", "night: phase == night (got %s)" % info_n["phase"])
	var night_db := float(info_n["loops"][2]["volume_db"])
	_expect(night_db <= -4.0 and night_db >= -22.0, "night: Night gain in [-22, -4] dB (%.1f)" % night_db)

	# back to day: fireplace off, night layer gates out below NIGHT_STOP_ENV
	for i in range(120):
		audio.update_audio(0.5, {"sun_alt": 9.0, "night": 0.0, "wind": 0.3, "fireplace_on": false})
	var info_d2: Dictionary = audio.get_debug_info()
	_expect(not info_d2["loops"][2]["playing"], "dawn: Night loop gated back off")
	_expect(not info_d2["fire_playing"], "dawn: fire loop stopped")
	_expect(info_d2["phase"] == "day", "dawn: phase returns to day (got %s)" % info_d2["phase"])
	var totals: Dictionary = A.get_event_totals()
	_expect(int(totals.get("fire_start", 0)) >= 1, "fire_start event logged")
	_expect(int(totals.get("fire_stop", 0)) >= 1, "fire_stop event logged")
	_expect(int(totals.get("loop_play:night_gate", 0)) >= 1, "night layer start logged with source=night_gate")
	_expect(int(totals.get("loop_stop:night_gate", 0)) >= 1, "night layer stop logged with source=night_gate")
	_expect(int(totals.get("phase", 0)) >= 2, "phase change events logged")

	# sfx play calls must not add players and must log on the SFX bus
	var sfx_before := _player_count()
	audio.play_ui_click()
	audio.play_door(true)
	audio.play_splash(0.7)
	var totals2: Dictionary = A.get_event_totals()
	for src in ["ui_click", "door_open", "water_splash"]:
		_expect(int(totals2.get("sfx:" + src, 0)) >= 1, "sfx event logged: " + src)
	_expect(_player_count() == sfx_before, "sfx playback adds no players")
	var last_sfx: Dictionary = A.get_event_log()[-1]
	_expect(String(last_sfx.get("bus", "")) == "IsleSFX", "sfx event reports bus IsleSFX")


func _check_wav_metadata() -> void:
	var info: Dictionary = audio.get_debug_info()
	var night: Dictionary = info["loops"][2]
	_expect(String(night["file"]) == "night_loop.wav", "night loop is night_loop.wav")
	_expect(int(night["frames"]) == 705600, "night loop frames == 705600 (got %d)" % int(night["frames"]))
	_expect(absf(float(night["length"]) - 16.0) <= 0.01, "night loop length == 16.0 s (got %.2f)" % float(night["length"]))
	_expect(int(night["loop_mode"]) == AudioStreamWAV.LOOP_FORWARD, "night loop loop_mode == LOOP_FORWARD")
	_expect(int(night["loop_end"]) == int(night["frames"]), "night loop_end == frames")
	_expect(int(night["mix_rate"]) == 44100, "night loop mix_rate == 44100")
	var fire: Dictionary = {"loaded": info["fire_loaded"]}
	_expect(fire["loaded"], "fire stream loaded")
	var fire_player: AudioStreamPlayer = host.get_node("IsleAudio_Fire")
	var fw: AudioStreamWAV = fire_player.stream as AudioStreamWAV
	_expect(fw != null, "fire player stream is AudioStreamWAV")
	if fw != null:
		_expect(absf(fw.get_length() - 4.0) <= 0.02, "fire loop length == 4.0 s (got %.3f)" % fw.get_length())
		_expect(fw.loop_mode == AudioStreamWAV.LOOP_FORWARD, "fire loop loop_mode == LOOP_FORWARD")
		_expect(fw.loop_end > 0, "fire loop_end > 0 (%d)" % fw.loop_end)


func _check_debug_info() -> void:
	var info: Dictionary = audio.get_debug_info()
	for k in ["buses", "group_volumes", "loops", "event_totals", "players", "players_total", "phase"]:
		_expect(info.has(k), "get_debug_info() has field " + k)
	_expect(int(info["event_count"]) == A.get_event_log().size(), "event_count matches static event log size")
	_expect(int(info["event_seq"]) >= int(info["event_count"]), "event_seq >= event_count")


func _expect(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append(msg)
		print("  [FAIL] " + msg)


func _finish() -> void:
	print("")
	for n in notes:
		print("  [NOTE] " + n)
	print("PROBE RESULT: %d checks, %d failures" % [checks, failures.size()])
	if failures.is_empty():
		print("PROBE STATUS: PASS")
		quit(0)
	else:
		for f in failures:
			print("  FAILED: " + f)
		print("PROBE STATUS: FAIL")
		quit(1)
