class_name IsleAudio
extends Node

## P6 audio rewrite: five mix buses (Master built-in + IsleAmbient / IsleBirds / IsleFire / IsleSFX),
## per-bus AudioEffect chains, per-group volume API, bird chorus on its own bus and a looping
## fireplace stream. Every player only carries its own base/behaviour offset; mix volume lives on
## the buses, so a group change is instant and never creates new players.
##
## Contract with main.gd / isle_settings.gd:
##   setup(host)                       -> idempotent build of buses, players, ambience
##   set_group_volume(group, linear)   -> group in {master, ambient, birds, fire, sfx} (also accepts
##                                        settings keys volume_master .. volume_sfx)
##   get_group_volumes() -> Dictionary  -> {"master":0.8, "ambient":0.7, "birds":0.8, "fire":0.7, "sfx":0.8}
##   set_volume(linear)                -> legacy alias for the master group
##   set_muted(bool)                   -> master bus mute
##   update_audio(delta, state)        -> state = {sun_alt, night, wind, fireplace_on}
##   play_door(open) / play_splash(power) / play_ui_click() / play_fire_crackle()

const AUDIO_DIR := "res://audio/"

const MASTER_BUS := "Master"
const BUS_AMBIENT := "IsleAmbient"
const BUS_BIRDS := "IsleBirds"
const BUS_FIRE := "IsleFire"
const BUS_SFX := "IsleSFX"

const GROUP_KEYS: Array[String] = ["master", "ambient", "birds", "fire", "sfx"]
const GROUP_BUS := {
	"master": MASTER_BUS,
	"ambient": BUS_AMBIENT,
	"birds": BUS_BIRDS,
	"fire": BUS_FIRE,
	"sfx": BUS_SFX,
}
const GROUP_SETTING_KEYS := {
	"volume_master": "master",
	"volume_ambient": "ambient",
	"volume_birds": "birds",
	"volume_fire": "fire",
	"volume_sfx": "sfx",
}

# Effect chains (idempotent: tagged effects are replaced, never stacked twice).
const EFFECT_TAG := "P6_"
const QUIET_DB := -80.0
const SILENT_LINEAR := 0.001

# --- ambience loops (all on IsleAmbient) ---
const LOOP_FILES: Array[String] = ["ocean_loop.wav", "wind_loop.wav", "night_loop.wav"]
const LOOP_NAMES: Array[String] = ["Ocean", "Wind", "Night"]
const LOOP_BASE_DB: Array[float] = [0.0, -4.5, -6.5]
const LOOP_TAU: Array[float] = [2.4, 3.2, 2.0]
const NIGHT_START_ENV := 0.02
const NIGHT_STOP_ENV := 0.015
# C2：夜层门限关闭后不再单帧 hard-stop（跳时曾瞬断约 73dB），而是按 LOOP_TAU[2] 自然淡出，
#     到该 env（约 -43dB，与实测自然黎明停点 -42.8dB 一致）才真正 stop。
const NIGHT_FADE_STOP_ENV := 0.015
# C3：壁炉声关闭时按 FIRE_FADE_TAU 淡出，到该 env 才 stop；开启时立即回到 FIRE_BASE_DB。
const FIRE_FADE_TAU := 0.9
const FIRE_FADE_STOP_ENV := 0.015

# --- bird chorus (own bus: IsleBirds) ---
const BIRD_FILES: Array[String] = ["bird_1.wav", "bird_2.wav", "bird_3.wav"]
const BIRD_BASE_DB := -13.0
const BIRD_GAP_MIN := 6.0
const BIRD_GAP_MAX := 14.0
const BIRD_POOL_SIZE := 3

# --- one-shot sfx pool (own bus: IsleSFX) ---
const SFX_POOL_SIZE := 8
const SFX_DEFS := {
	"door_open": {"file": "door_open.wav", "db": -5.0},
	"door_close": {"file": "door_close.wav", "db": -5.0},
	"ui_click": {"file": "ui_click.wav", "db": -9.0},
	"water_splash": {"file": "water_splash.wav", "db": -4.0},
	"fire_crackle": {"file": "fire_crackle.wav", "db": -10.0},
}

# --- fireplace loop (own bus: IsleFire) ---
const FIRE_FILE := "fire_crackle.wav"
const FIRE_BASE_DB := -12.0

# --- test/debug event log (kept compatible with the old P5 probe shapes) ---
const EVENT_LOG_CAP := 1024
const GAIN_LOG_DB_STEP := 3.0
const DEBUG_LOG_PATH := "D:/休闲小岛幻境/开发产物/logs/audio_main_run.log"

static var _event_log: Array[Dictionary] = []
static var _event_seq: int = 0
static var _event_totals: Dictionary = {}
static var _instance: IsleAudio = null

var _parent: Node = null
var _setup_done := false
var _clock := 0.0
var _phase := "day"
var _missing: Array[String] = []
var _warned: Dictionary = {}

# player arrays
var _loop_players: Array[AudioStreamPlayer] = []
var _loop_streams: Array[AudioStream] = []
var _loop_env: Array[float] = [0.9, 0.35, 0.0]
var _loop_target: Array[float] = [0.9, 0.35, 0.0]
var _loop_base_db: Array[float] = [0.0, 0.0, 0.0]
var _loop_loaded: Array[bool] = [false, false, false]

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next := 0

var _bird_players: Array[AudioStreamPlayer] = []
var _bird_streams: Array[AudioStream] = []
var _bird_loaded := false
var _bird_timer := 8.0

var _fire_player: AudioStreamPlayer = null
var _fire_stream: AudioStream = null
var _fire_loaded := false
var _fire_loop_on := false
var _fire_env := 0.0

var _group_linear := {"master": 1.0, "ambient": 1.0, "birds": 1.0, "fire": 1.0, "sfx": 1.0}
var _muted := false

var _audio_cache: Dictionary = {}
var _last_env_log := ""
var _last_gain_log := {0: 999.0, 1: 999.0, 2: 999.0}
var _night_on := false
var _last_env_acc := 0.0


# ============================================================
# lifecycle
# ============================================================
func setup(host: Node) -> void:
	_parent = host
	_instance = self
	if _setup_done:
		_apply_all_group_volumes()
		return
	_setup_done = true
	_ensure_buses()
	_build_loops()
	_build_sfx_pool()
	_build_bird_pool()
	_build_fire()
	_apply_all_group_volumes()
	_log_event("setup", {
		"loops_loaded": _count_true(_loop_loaded),
		"players": _player_count(),
		"missing": _missing.duplicate(),
		"buses": GROUP_KEYS.duplicate(),
		"night_start_env": NIGHT_START_ENV,
		"night_stop_env": NIGHT_STOP_ENV,
	})
	if is_inside_tree():
		_start_ambience()
	else:
		tree_entered.connect(_on_tree_entered_once, CONNECT_ONE_SHOT)


func _on_tree_entered_once() -> void:
	call_deferred("_start_ambience")


func is_ready() -> bool:
	return _setup_done


# ============================================================
# bus construction + effect chains
# ============================================================
func _ensure_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		idx = _find_free_bus_slot()
		if idx < 0:
			AudioServer.add_bus()
			idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, MASTER_BUS)
	return idx


func _find_free_bus_slot() -> int:
	# Prefer an unused default "Bus N" slot, never re-use a named bus.
	for i in range(AudioServer.bus_count):
		var nm := AudioServer.get_bus_name(i)
		if nm == MASTER_BUS:
			continue
		if nm.begins_with("Bus ") and AudioServer.get_bus_effect_count(i) == 0:
			return i
	return -1


func _ensure_buses() -> void:
	_ensure_bus(BUS_AMBIENT)
	_ensure_bus(BUS_BIRDS)
	_ensure_bus(BUS_FIRE)
	_ensure_bus(BUS_SFX)
	_rebuild_effects(BUS_AMBIENT, _ambient_effects())
	_rebuild_effects(BUS_BIRDS, _bird_effects())
	_rebuild_effects(BUS_FIRE, _fire_effects())
	_rebuild_effects(BUS_SFX, _sfx_effects())
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MASTER_BUS), 0.0)


func _rebuild_effects(bus_name: String, effects: Array) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	# Idempotency: only touch the chain when it is not already exactly ours.
	if _chain_matches(idx, effects):
		return
	for i in range(AudioServer.get_bus_effect_count(idx) - 1, -1, -1):
		AudioServer.remove_bus_effect(idx, i)
	for eff in effects:
		eff.resource_name = EFFECT_TAG + bus_name + "_" + eff.get_class()
		AudioServer.add_bus_effect(idx, eff)


func _chain_matches(idx: int, effects: Array) -> bool:
	if AudioServer.get_bus_effect_count(idx) != effects.size():
		return false
	for i in range(effects.size()):
		var cur := AudioServer.get_bus_effect(idx, i)
		if cur == null or cur.get_class() != effects[i].get_class():
			return false
	return true


func _ambient_effects() -> Array:
	# soften surf/wind/night: low-pass the top octave and trim the 2-6 kHz "pinch" region
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 11200.0
	lp.resonance = 0.35
	var eq := AudioEffectEQ6.new()
	eq.set_band_gain_db(0, 0.0)     # 32 Hz
	eq.set_band_gain_db(1, 0.0)     # 100 Hz
	eq.set_band_gain_db(2, -1.0)    # 320 Hz
	eq.set_band_gain_db(3, 0.0)     # 1 kHz
	eq.set_band_gain_db(4, -3.5)    # 3.2 kHz  (harsh 2-6 kHz shoulder)
	eq.set_band_gain_db(5, -2.5)    # 10 kHz
	return [lp, eq]


func _bird_effects() -> Array:
	# keep bird calls present but take the ice off the top: gentle low cut + top shelf
	var eq := AudioEffectEQ6.new()
	eq.set_band_gain_db(0, -2.0)    # 32 Hz
	eq.set_band_gain_db(1, -2.0)    # 100 Hz
	eq.set_band_gain_db(2, -1.0)    # 320 Hz
	eq.set_band_gain_db(3, 0.5)     # 1 kHz
	eq.set_band_gain_db(4, 0.5)     # 3.2 kHz
	eq.set_band_gain_db(5, -3.0)    # 10 kHz
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 13200.0
	lp.resonance = 0.2
	return [eq, lp]


func _fire_effects() -> Array:
	# fireplace: tame crackle top end, then a light compressor so pops never spike the mix
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 8200.0
	lp.resonance = 0.5
	var eq := AudioEffectEQ6.new()
	eq.set_band_gain_db(0, 0.0)
	eq.set_band_gain_db(1, 0.5)
	eq.set_band_gain_db(2, 0.0)
	eq.set_band_gain_db(3, 0.0)
	eq.set_band_gain_db(4, -2.5)    # 3.2 kHz
	eq.set_band_gain_db(5, -6.0)    # 10 kHz
	var comp := AudioEffectCompressor.new()
	comp.threshold = -18.0
	comp.ratio = 2.5
	comp.attack_us = 8000.0
	comp.release_ms = 150.0
	comp.gain = 1.0
	return [lp, eq, comp]


func _sfx_effects() -> Array:
	# gentle glue compressor on one-shots (door/ui/splash) so they sit under the ambience
	var comp := AudioEffectCompressor.new()
	comp.threshold = -16.0
	comp.ratio = 2.2
	comp.attack_us = 6000.0
	comp.release_ms = 120.0
	comp.gain = 0.0
	var eq := AudioEffectEQ6.new()
	eq.set_band_gain_db(0, -1.0)
	eq.set_band_gain_db(1, 0.0)
	eq.set_band_gain_db(2, 0.0)
	eq.set_band_gain_db(3, 0.0)
	eq.set_band_gain_db(4, 0.0)
	eq.set_band_gain_db(5, -1.5)
	return [comp, eq]


# ============================================================
# players
# ============================================================
func _make_player(short_name: String, bus_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = "IsleAudio_" + short_name
	p.bus = bus_name
	p.volume_db = QUIET_DB
	p.autoplay = false
	var owner_node: Node = _parent if _parent != null else self
	owner_node.add_child(p)
	return p


func _build_loops() -> void:
	for i in range(LOOP_FILES.size()):
		var p := _make_player(LOOP_NAMES[i], BUS_AMBIENT)
		p.finished.connect(_on_loop_player_finished.bind(i))
		var st := _get_audio(LOOP_FILES[i], true)
		_loop_loaded[i] = st != null
		_loop_base_db[i] = LOOP_BASE_DB[i]
		var stream: AudioStream = null
		if st != null:
			stream = _load_loop_stream(st)
			p.stream = stream
		_loop_streams.append(stream)
		_loop_players.append(p)


func _build_sfx_pool() -> void:
	for i in range(SFX_POOL_SIZE):
		var p := _make_player("SFX%d" % i, BUS_SFX)
		_sfx_players.append(p)


func _build_bird_pool() -> void:
	for i in range(BIRD_POOL_SIZE):
		var p := _make_player("Bird%d" % (i + 1), BUS_BIRDS)
		_bird_players.append(p)
	_bird_streams.clear()
	var loaded := 0
	for f in BIRD_FILES:
		var st := _get_audio(f, false)
		_bird_streams.append(st)
		if st != null:
			loaded += 1
	_bird_loaded = loaded == BIRD_FILES.size()


func _build_fire() -> void:
	_fire_player = _make_player("Fire", BUS_FIRE)
	_fire_player.finished.connect(_on_fire_finished)
	var st := _get_audio(FIRE_FILE, true)
	_fire_loaded = st != null
	if st != null:
		_fire_stream = _load_loop_stream(st)
		_fire_player.stream = _fire_stream


func _start_ambience() -> void:
	if not _setup_done:
		return
	for i in range(LOOP_FILES.size()):
		if i == 2:
			continue  # night layer is gated by update_audio()
		var p := _loop_players[i]
		if p.stream == null:
			continue
		if not p.playing:
			p.volume_db = _loop_base_db[i] + linear_to_db(clampf(_loop_env[i], 0.0001, 1.0))
			p.play()
			_log_event("loop_play", {"layer": LOOP_NAMES[i], "source": "start_ambience", "volume_db": p.volume_db})
	if _fire_loop_on and _fire_player != null and _fire_player.stream != null and not _fire_player.playing:
		_fire_env = 1.0
		_fire_player.volume_db = FIRE_BASE_DB
		_fire_player.play()


# ============================================================
# volume API
# ============================================================
func set_group_volume(group: String, linear: float) -> void:
	var key := _normalize_group(group)
	if key == "":
		_log_event("group_unknown", {"group": group, "linear": linear})
		return
	var v := clampf(linear, 0.0, 1.0)
	_group_linear[key] = v
	if key == "master":
		_muted = v <= SILENT_LINEAR
	_apply_group_volume(key)
	_log_event("group", {"group": key, "linear": v, "bus": GROUP_BUS[key], "db": _group_db(v), "muted": _bus_muted(key)})


func set_bus_volume(bus_name: String, linear: float) -> void:
	# Compatibility alias used by main.gd._apply_audio_volume(): it passes the bus name
	# from Settings.audio_groups() (Master / IsleAmbient / IsleBirds / IsleFire / IsleSFX).
	var key := _normalize_group(bus_name)
	if key == "":
		_log_event("bus_unknown", {"bus": bus_name, "linear": linear})
		return
	set_group_volume(key, linear)


func get_group_volumes() -> Dictionary:
	var out := {}
	for key in GROUP_KEYS:
		out[key] = float(_group_linear[key])
	return out


func set_volume(linear: float) -> void:
	set_group_volume("master", linear)


func set_muted(muted: bool) -> void:
	_muted = muted
	_apply_master_mute()
	_log_event("master_mute", {"muted": _muted, "master_linear": _group_linear["master"]})


func _normalize_group(group: String) -> String:
	var g := group.strip_edges().to_lower()
	if GROUP_SETTING_KEYS.has(g):
		return GROUP_SETTING_KEYS[g]
	if GROUP_KEYS.has(g):
		return g
	for key in GROUP_KEYS:
		if String(GROUP_BUS[key]).to_lower() == g:
			return key
	return ""


func _apply_all_group_volumes() -> void:
	for key in GROUP_KEYS:
		_apply_group_volume(key)


func _apply_group_volume(key: String) -> void:
	var bus_name: String = GROUP_BUS[key]
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var v: float = float(_group_linear[key])
	AudioServer.set_bus_volume_db(idx, _group_db(v))
	if key == "master":
		_apply_master_mute()
	else:
		AudioServer.set_bus_mute(idx, v <= SILENT_LINEAR)


func _apply_master_mute() -> void:
	var idx := AudioServer.get_bus_index(MASTER_BUS)
	if idx < 0:
		return
	var mv: float = float(_group_linear["master"])
	AudioServer.set_bus_mute(idx, _muted or mv <= SILENT_LINEAR)


func _bus_db(idx: int) -> float:
	if idx < 0:
		return QUIET_DB
	return AudioServer.get_bus_volume_db(idx)


func _group_db(v: float) -> float:
	if v <= SILENT_LINEAR:
		return QUIET_DB
	return linear_to_db(v)


func _bus_muted(key: String) -> bool:
	var idx := AudioServer.get_bus_index(GROUP_BUS[key])
	if idx < 0:
		return false
	return AudioServer.is_bus_mute(idx)


# ============================================================
# per-frame mix logic (unchanged public behaviour)
# ============================================================
func update_audio(delta: float, state: Dictionary) -> void:
	if not _setup_done:
		return
	_clock += delta
	var sun_alt := float(state.get("sun_alt", 0.0))
	var night := clampf(float(state.get("night", 0.0)), 0.0, 1.0)
	var wind := clampf(float(state.get("wind", 0.5)), 0.0, 1.0)
	var fireplace_on := bool(state.get("fireplace_on", false))

	var day := smoothstep(-4.0, 9.0, sun_alt)
	_loop_target[0] = 0.88 + 0.12 * day
	_loop_target[1] = 0.30 + 0.70 * wind
	_loop_target[2] = smoothstep(0.02, 0.9, night)

	var new_phase := _phase_of(sun_alt, night)
	if new_phase != _phase:
		_log_event("phase", {"from": _phase, "to": new_phase, "sun_alt": sun_alt, "night": night})
		_phase = new_phase

	# night layer gate: start above NIGHT_START_ENV; below NIGHT_STOP_ENV keep playing but let
	# env fade with LOOP_TAU[2] and only stop once it reaches NIGHT_FADE_STOP_ENV (C2).
	if _loop_players.size() == 3 and _loop_loaded[2]:
		if not _night_on and _loop_target[2] >= NIGHT_START_ENV:
			_night_on = true
			_loop_env[2] = maxf(_loop_env[2], NIGHT_STOP_ENV)
			if not _loop_players[2].playing:
				_loop_players[2].volume_db = _loop_base_db[2] + linear_to_db(maxf(_loop_env[2], 0.0001))
				_loop_players[2].play()
				_log_event("loop_play", {"layer": LOOP_NAMES[2], "source": "night_gate", "env": _loop_env[2]})
		elif _night_on and _loop_target[2] < NIGHT_STOP_ENV and _loop_env[2] <= NIGHT_FADE_STOP_ENV:
			_night_on = false
			if _loop_players[2].playing:
				_loop_players[2].stop()
				_log_event("loop_stop", {"layer": LOOP_NAMES[2], "source": "night_gate", "env": _loop_env[2], "fade_tau": LOOP_TAU[2]})

	for i in range(LOOP_FILES.size()):
		var tau: float = LOOP_TAU[i]
		if i == 2 and not _night_on and not _loop_players[2].playing:
			_loop_env[i] = 0.0
		else:
			_loop_env[i] = lerpf(_loop_env[i], _loop_target[i], 1.0 - exp(-delta / maxf(tau, 0.01)))
		_apply_loop_gain(i)
		_log_gain(i)

	# fireplace stream: start immediately at FIRE_BASE_DB, stop only after a short fade (C3:
	# the old code cut from -12 dB to silence in one frame when sun_alt crossed +2°).
	if fireplace_on != _fire_loop_on:
		_fire_loop_on = fireplace_on
		if _fire_player != null and _fire_player.stream != null:
			if fireplace_on:
				_fire_env = 1.0
				_fire_player.volume_db = FIRE_BASE_DB
				if not _fire_player.playing:
					_fire_player.play()
				_log_event("fire_start", {"source": "fireplace_on", "volume_db": FIRE_BASE_DB, "sun_alt": sun_alt})
			else:
				_log_event("fire_fade", {"source": "fireplace_on", "volume_db": FIRE_BASE_DB, "sun_alt": sun_alt})
	if _fire_player != null and _fire_player.stream != null and _fire_player.playing and not _fire_loop_on:
		_fire_env = maxf(0.0, _fire_env * exp(-delta / FIRE_FADE_TAU))
		if _fire_env <= FIRE_FADE_STOP_ENV:
			var stop_env := _fire_env
			_fire_env = 0.0
			_fire_player.volume_db = QUIET_DB
			_fire_player.stop()
			_log_event("fire_stop", {"source": "fireplace_off", "stop_env": stop_env, "sun_alt": sun_alt, "fade_tau": FIRE_FADE_TAU})
		else:
			_fire_player.volume_db = FIRE_BASE_DB + linear_to_db(maxf(_fire_env, 0.0001))

	# daytime bird chorus (gap timer, only when it is clearly day)
	_bird_timer -= delta
	if _bird_timer <= 0.0:
		_bird_timer = randf_range(BIRD_GAP_MIN, BIRD_GAP_MAX)
		if day > 0.55 and night < 0.35 and sun_alt > 2.0:
			_play_bird()

	_maybe_log_env(delta)


func _phase_of(sun_alt: float, night: float) -> String:
	if sun_alt > 2.0:
		return "day"
	if sun_alt > -6.0:
		return "dusk" if _phase != "night" else "dawn"
	return "night"


func _apply_loop_gain(i: int) -> void:
	if i < 0 or i >= _loop_players.size():
		return
	var p := _loop_players[i]
	if p.stream == null:
		return
	var env: float = clampf(_loop_env[i], 0.0, 1.0)
	var db := _loop_base_db[i]
	if env > 0.0001:
		db += linear_to_db(env)
	p.volume_db = db
	if i == 2 and not _night_on and not p.playing:
		p.volume_db = QUIET_DB


func _log_gain(i: int) -> void:
	var db: float = _loop_players[i].volume_db
	var last: float = float(_last_gain_log.get(i, 999.0))
	if absf(db - last) >= GAIN_LOG_DB_STEP:
		_last_gain_log[i] = db
		_log_event("gain", {"layer": LOOP_NAMES[i], "db": db, "env": _loop_env[i], "target": _loop_target[i]})


func _maybe_log_env(delta: float) -> void:
	_last_env_acc += delta
	if _last_env_acc < 1.0:
		return
	_last_env_acc = 0.0
	var sig := "%d_%d_%d" % [int(_loop_env[0] * 100.0), int(_loop_env[1] * 100.0), int(_loop_env[2] * 100.0)]
	if sig != _last_env_log:
		_last_env_log = sig
		_log_event("env", {"env": _loop_env.duplicate(), "target": _loop_target.duplicate(), "phase": _phase})


# ============================================================
# one-shot playback
# ============================================================
func play_door(open: bool) -> void:
	_play_named("door_open" if open else "door_close", 0.0, 1.0)


func play_ui_click() -> void:
	_play_named("ui_click", 0.0, 1.0)


func play_splash(power: float) -> void:
	var pw := clampf(power, 0.0, 1.0)
	_play_named("water_splash", 0.0, 1.0, linear_to_db(0.25 + 0.75 * pw))


func play_fire_crackle() -> void:
	_play_named("fire_crackle", 0.0, 1.0)


func _play_named(key: String, extra_db: float, pitch: float, level_db: float = 0.0) -> void:
	var def: Dictionary = SFX_DEFS.get(key, {})
	if def.is_empty():
		_log_event("sfx_unknown", {"key": key})
		return
	var st := _get_audio(String(def["file"]), false)
	if st == null:
		return
	_launch_sfx(st, String(def["file"]), float(def["db"]) + extra_db + level_db, pitch, key, {})


func _play_bird() -> void:
	if _bird_players.is_empty():
		return
	var avail: Array[int] = []
	for i in range(_bird_players.size()):
		if not _bird_players[i].playing:
			avail.append(i)
	if avail.is_empty():
		return
	var slot: int = avail[randi() % avail.size()]
	if _bird_streams.is_empty():
		return
	var idx := randi() % maxi(_bird_streams.size(), 1)
	var st: AudioStream = _bird_streams[idx]
	if st == null:
		return
	var p := _bird_players[slot]
	p.stream = st
	p.pitch_scale = randf_range(0.94, 1.06)
	p.volume_db = BIRD_BASE_DB + randf_range(-1.5, 1.5)
	p.play()
	_log_event("sfx", {
		"source": "bird",
		"stream": BIRD_FILES[idx],
		"slot": slot,
		"bus": BUS_BIRDS,
		"db": p.volume_db,
		"pitch": p.pitch_scale,
		"playing_after": p.playing,
	})


func _launch_sfx(st: AudioStream, stream_name: String, db: float, pitch: float, source: String, extra: Dictionary) -> void:
	if _sfx_players.is_empty():
		return
	var slot := _find_sfx_slot()
	var p := _sfx_players[slot]
	p.stream = st
	p.pitch_scale = pitch
	p.volume_db = db
	p.play()
	var ev := {"source": source, "stream": stream_name, "slot": slot, "bus": BUS_SFX, "db": db, "pitch": pitch, "playing_after": p.playing}
	ev.merge(extra, true)
	_log_event("sfx", ev)


func _find_sfx_slot() -> int:
	for i in range(_sfx_players.size()):
		if not _sfx_players[i].playing:
			return i
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	return _sfx_next


# ============================================================
# stream loading
# ============================================================
func _get_audio(file: String, warn: bool) -> AudioStream:
	if _audio_cache.has(file):
		return _audio_cache[file]
	var path := AUDIO_DIR + file
	var st: AudioStream = null
	if ResourceLoader.exists(path):
		st = load(path) as AudioStream
	if st == null:
		_audio_cache[file] = null
		if warn:
			_missing.append(file)
			_warn_once("missing_" + file, "IsleAudio: missing audio " + path)
		return null
	_audio_cache[file] = st
	return st


func _warn_once(key: String, msg: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(msg)
	_log_event("warn_missing", {"key": key, "msg": msg})


func _load_loop_stream(st: AudioStream) -> AudioStream:
	var out: AudioStream = st.duplicate(true) as AudioStream
	if out is AudioStreamWAV:
		var w: AudioStreamWAV = out
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = _wav_frames(w)
	return out


func _wav_frames(w: AudioStreamWAV) -> int:
	var frames := _frames_from_length(w)
	if frames > 0:
		return frames
	return _qoa_total_samples(w)


func _frames_from_length(w: AudioStreamWAV) -> int:
	if w.data.is_empty():
		return 0
	var fmt: int = w.format
	var channels: int = 1 if w.stereo == false else 2
	var bytes_per_sample := 0
	match fmt:
		AudioStreamWAV.FORMAT_8_BITS:
			bytes_per_sample = 1
		AudioStreamWAV.FORMAT_16_BITS:
			bytes_per_sample = 2
		_:
			return 0  # QOA / compressed: data_size is not a frame count here
	if bytes_per_sample <= 0 or channels <= 0:
		return 0
	return w.data.size() / (bytes_per_sample * channels)


func _qoa_total_samples(w: AudioStreamWAV) -> int:
	# QOA frame header: "qoaf" + uint32 total_samples (big endian)
	var d := w.data
	if d.size() < 8:
		return 0
	if not (d[0] == 0x71 and d[1] == 0x6F and d[2] == 0x61 and d[3] == 0x66):
		return 0
	return (int(d[4]) << 24) | (int(d[5]) << 16) | (int(d[6]) << 8) | int(d[7])


func _wav_header_hex(w: AudioStreamWAV) -> String:
	var d := w.data
	var n := mini(8, d.size())
	var out := ""
	for i in n:
		out += "%02x" % int(d[i])
	return out


func _count_true(arr) -> int:
	var n := 0
	for x in arr:
		if x:
			n += 1
	return n


func _player_count() -> int:
	return _loop_players.size() + _sfx_players.size() + _bird_players.size() + (1 if _fire_player != null else 0)


# ============================================================
# playback fallbacks
# ============================================================
func _on_loop_player_finished(i: int) -> void:
	if i < 0 or i >= _loop_players.size():
		return
	var p := _loop_players[i]
	if p.stream == null:
		return
	if i == 2 and not _night_on:
		return
	if not p.playing:
		p.play()
		_log_event("loop_play", {"layer": LOOP_NAMES[i], "source": "finished_fallback", "volume_db": p.volume_db})


func _on_fire_finished() -> void:
	if not _fire_loop_on or _fire_player == null or _fire_player.stream == null:
		return
	_fire_player.play()
	_log_event("fire_restart", {"source": "finished_fallback"})


# ============================================================
# debug / test API (kept for the probes)
# ============================================================
func get_debug_info() -> Dictionary:
	var loops := []
	for i in range(LOOP_FILES.size()):
		var p := _loop_players[i]
		var w: AudioStreamWAV = p.stream as AudioStreamWAV
		loops.append({
			"name": LOOP_NAMES[i],
			"file": LOOP_FILES[i],
			"bus": BUS_AMBIENT,
			"loaded": _loop_loaded[i],
			"playing": p.playing,
			"volume_db": p.volume_db,
			"env": _loop_env[i],
			"target": _loop_target[i],
			"base_db": _loop_base_db[i],
			"frames": _wav_frames(w) if w != null else 0,
			"loop_begin": w.loop_begin if w != null else -1,
			"loop_end": w.loop_end if w != null else 0,
			"loop_mode": w.loop_mode if w != null else 0,
			"header": _wav_header_hex(w) if w != null else "",
			"mix_rate": w.mix_rate if w != null else 0,
			"format": w.format if w != null else 0,
			"stereo": w.stereo if w != null else false,
			"length": w.get_length() if w != null else 0.0,
			"data_size": w.data.size() if w != null else 0,
		})
	var buses := {}
	for key in GROUP_KEYS:
		var bus_name: String = GROUP_BUS[key]
		var idx := AudioServer.get_bus_index(bus_name)
		buses[key] = {
			"bus": bus_name,
			"index": idx,
			"linear": float(_group_linear[key]),
			"db": _bus_db(idx),
			"mute": _bus_muted(key),
			"effects": AudioServer.get_bus_effect_count(idx) if idx >= 0 else 0,
			"effect_classes": _effect_classes(idx),
		}
	return {
		"ready": _setup_done,
		"buses": buses,
		"master_bus": MASTER_BUS,
		"master_linear": float(_group_linear["master"]),
		"master_db": _bus_db(AudioServer.get_bus_index(MASTER_BUS)),
		"muted": _muted,
		"group_volumes": get_group_volumes(),
		"loops": loops,
		"loops_loaded": _count_true(_loop_loaded),
		"sfx_players": _sfx_players.size(),
		"bird_players": _bird_players.size(),
		"birds_loaded": _bird_loaded,
		"fire_loaded": _fire_loaded,
		"fire_playing": _fire_player != null and _fire_player.playing,
		"fire_env": _fire_env,
		"fire_volume_db": _fire_player.volume_db if _fire_player != null else QUIET_DB,
		"players_total": _player_count(),
		"missing": _missing.duplicate(),
		"phase": _phase,
		"night_start_env": NIGHT_START_ENV,
		"night_stop_env": NIGHT_STOP_ENV,
		"night_fade_stop_env": NIGHT_FADE_STOP_ENV,
		"event_count": _event_log.size(),
		"event_seq": _event_seq,
		"event_totals": _event_totals.duplicate(true),
		"players": _debug_players(),
	}


func _effect_classes(idx: int) -> Array:
	var out := []
	if idx < 0:
		return out
	for i in range(AudioServer.get_bus_effect_count(idx)):
		var eff := AudioServer.get_bus_effect(idx, i)
		out.append(eff.get_class() if eff != null else "")
	return out


func _debug_players() -> Array:
	var out := []
	if _parent == null:
		return out
	for c in _parent.get_children():
		if String(c.name).begins_with("IsleAudio_"):
			var is_player := c is AudioStreamPlayer
			out.append({
				"name": String(c.name),
				"type": c.get_class(),
				"playing": c.playing if is_player else false,
				"volume_db": c.volume_db if is_player else 0.0,
				"bus": c.bus if is_player else "",
				"has_stream": c.stream != null if is_player else false,
			})
	return out


static func get_event_log() -> Array:
	return _event_log.duplicate(true)


static func get_event_totals() -> Dictionary:
	return _event_totals.duplicate(true)


static func clear_event_log() -> void:
	_event_log.clear()
	_event_totals.clear()
	_event_seq = 0


static func debug_snapshot() -> Dictionary:
	var inst := _instance
	if inst == null:
		return {
			"instance": false, "seq": _event_seq, "event_count": _event_log.size(),
			"totals": _event_totals.duplicate(true), "events_tail": _event_log.slice(-24),
		}
	return {
		"instance": true,
		"seq": _event_seq,
		"event_count": _event_log.size(),
		"totals": _event_totals.duplicate(true),
		"events_tail": _event_log.slice(-24),
		"setup_done": inst._setup_done,
		"ready": inst.is_ready(),
		"clock": inst._clock,
		"phase": inst._phase,
		"master_linear": inst._group_linear["master"],
		"muted": inst._muted,
		"buses": inst.get_debug_info().get("buses", {}),
		"parent_children": inst._parent.get_child_count() if inst._parent != null else 0,
		"parent_players": inst.get_debug_info().get("players", []),
		"loops": inst.get_debug_info().get("loops", []),
		"sfx_players": inst._sfx_players.size(),
		"bird_players": inst._bird_players.size(),
		"fire_loaded": inst._fire_loaded,
		"fire_playing": inst._fire_player != null and inst._fire_player.playing,
	}


func _log_event(ev_type: String, data: Dictionary) -> void:
	_event_seq += 1
	var ev := {
		"seq": _event_seq,
		"t": Time.get_ticks_msec() / 1000.0,
		"ms": Time.get_ticks_msec(),
		"phase": _phase,
		"type": ev_type,
	}
	ev.merge(data, true)
	_event_log.append(ev)
	_event_totals[ev_type] = int(_event_totals.get(ev_type, 0)) + 1
	if data.has("layer"):
		var k := ev_type + ":" + String(data["layer"])
		_event_totals[k] = int(_event_totals.get(k, 0)) + 1
	if data.has("source"):
		var k2 := ev_type + ":" + String(data["source"])
		_event_totals[k2] = int(_event_totals.get(k2, 0)) + 1
	if data.has("group"):
		var k3 := ev_type + ":" + String(data["group"])
		_event_totals[k3] = int(_event_totals.get(k3, 0)) + 1
	while _event_log.size() > EVENT_LOG_CAP:
		_event_log.pop_front()


func _exit_tree() -> void:
	if OS.get_cmdline_user_args().has("--audio-log") or OS.get_cmdline_args().has("--audio-log"):
		_dump_debug_log()


func _dump_debug_log() -> void:
	var dir := DEBUG_LOG_PATH.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(DEBUG_LOG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(debug_snapshot(), "  "))
	f.close()
