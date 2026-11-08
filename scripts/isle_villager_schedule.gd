class_name IsleVillagerSchedule
extends RefCounted
## P7-V4 lightweight daily scheduler for the lone islander.
##
## It owns no clock.  Every decision is fed the authoritative world time
## (main.gd _sim_seconds / _sim_rate), the sun altitude and IsleAstro.day_events
## of the same day, so a time jump or a different time source is handled by the
## caller's clock, never by a second 24 h timer in this file.
##
## Output is only an activity intent (kind + duration + region preference);
## the villager controller owns spots, paths, reservations and animations.
##
## Window sequence (default day length 600 s => 1 real second = 144 sim seconds):
##   00:00-wake        sleep          (wake = sunrise + 15 min, clamped 05:30..07:30)
##   wake-08:30        morning        idle / short stroll near home
##   08:30-11:30       morning_out    outdoor stroll + viewpoints
##   11:30-13:00       lunch          eat at the dining table
##   13:00-15:00       midday_rest    sit / rest
##   15:00-17:30       afternoon_out  outdoor stroll + viewpoints
##   17:30-19:00       dinner         eat
##   19:00-night       evening_rest   quiet sit (reading chair / sofa)
##   night-24:00       sleep          (night = sunset + 2 h, clamped 20:30..23:15)

const SPOT_COOLDOWN_SIM := 2700.0   # sim seconds before a used spot becomes attractive again
const KIND_MIN_REAL := {
    "sleep": 20.0,
    "eat": 8.0,
    "sit": 10.0,
    "stroll": 6.0,
    "idle": 5.0,
    # P9 新增两项白天户外生活动作
    "swing": 8.0,
    "sea_view": 8.0,
}
const KIND_MAX_REAL := {
    "sleep": 7200.0,
    "eat": 26.0,
    "sit": 48.0,
    "stroll": 20.0,
    "idle": 14.0,
    "swing": 22.0,
    "sea_view": 18.0,
}
const KIND_SHARE := {
    "sleep": 4.0,
    "eat": 3.0,
    "sit": 2.0,
    "stroll": 3.0,
    "idle": 1.0,
    "swing": 2.0,
    "sea_view": 2.0,
}
## P9：白天户外窗口的休闲候选（每次决策加权随机，避免固定轮播；时长另有随机化）。
const OUTDOOR_POOL := [
    ["stroll", 3.0],
    ["swing", 2.0],
    ["sea_view", 2.0],
    ["idle", 1.0],
]
const LEISURE_KINDS := ["swing", "sea_view"]
## Ordered intent list per window; repeated entries are consumed in order so a
## long window (real-time mode) gets a believable little routine instead of
## re-playing the same action every decision.
const WINDOW_SEQUENCE := {
    "morning": ["idle", "stroll", "idle", "stroll"],
    "morning_out": ["stroll", "stroll", "stroll"],
    "lunch": ["eat", "sit", "idle"],
    "midday_rest": ["sit", "sit", "stroll", "sit"],
    "afternoon_out": ["stroll", "stroll", "stroll"],
    "dinner": ["eat", "sit", "idle"],
    "evening_rest": ["sit", "sit", "stroll", "sit"],
    "night": ["sleep"],
    "sleep": ["sleep"],
}

var seed := 7
var _rng := RandomNumberGenerator.new()
var _last_kind := ""
var _last_spot := ""
var _spot_free_at := {}
var _window_id := ""
var _window_kind := ""
var _step := 0
var _jumps := 0
var _chooses := 0
var _last_sim := 0.0
var _last_reason := ""


func _init(vseed: int = 7) -> void:
    seed = vseed
    _rng.seed = vseed


# ===========================================================================
# World-time windows (pure functions, easy to test)
# ===========================================================================
static func _sun_rise_set(events: Dictionary) -> Vector2:
    var rise := float(events.get("sunrise", 360.0))
    var setm := float(events.get("sunset", 1080.0))
    if rise < 0.0:
        rise = 360.0
    if setm < 0.0:
        setm = 1080.0
    return Vector2(rise, setm)


## Ordered window table in minutes of the local day.  Starts are monotonic;
## zero/negative segments (winter sunrise later than 08:30 etc.) are dropped.
static func window_table(events: Dictionary) -> Array:
    var rs := _sun_rise_set(events)
    var wake := clampf(rs.x + 15.0, 330.0, 450.0)
    var night := clampf(rs.y + 120.0, 1230.0, 1395.0)
    var raw := [
        ["night_before_wake", 0.0, wake, "sleep"],
        ["morning", wake, 510.0, "morning"],
        ["morning_out", 510.0, 690.0, "morning_out"],
        ["lunch", 690.0, 780.0, "lunch"],
        ["midday_rest", 780.0, 900.0, "midday_rest"],
        ["afternoon_out", 900.0, 1050.0, "afternoon_out"],
        ["dinner", 1050.0, 1140.0, "dinner"],
        ["evening_rest", 1140.0, night, "evening_rest"],
        ["night", night, 1440.0, "night"],
    ]
    var out: Array = []
    var prev := -1.0
    for w in raw:
        var a := maxf(float(w[1]), prev)
        var b := float(w[2])
        if b - a >= 1.0:
            out.append({"id": String(w[0]), "start": a, "end": b, "kind": String(w[3])})
            prev = b
    return out


## Window containing the given authoritative sim seconds.
static func window_for(sim_seconds: float, events: Dictionary) -> Dictionary:
    var table := window_table(events)
    var minute := fposmod(sim_seconds, 86400.0) / 60.0
    for w in table:
        if minute >= float(w["start"]) and minute < float(w["end"]):
            return w
    # fallback: last window (e.g. floating point edge at 24:00)
    if not table.is_empty():
        return table[table.size() - 1]
    return {"id": "night", "start": 0.0, "end": 1440.0, "kind": "sleep"}


## Milliseconds-scale phase label for debug/report.
static func phase_for(window: Dictionary) -> String:
    return String(window.get("kind", "sleep"))


# ===========================================================================
# Decision
# ===========================================================================
## Pick the next activity.  ctx keys:
##   sim_seconds: float   authoritative world seconds (caller clock)
##   sim_rate:    float   sim seconds per real second
##   sun_alt:     float   degrees
##   events:      Dictionary  IsleAstro.day_events(sim_seconds)
##   daylight:    bool
##   current_kind/current_spot/last_spot: String
## Returns {kind, duration_real, window_id, window_kind, reason, region_pref}
func choose(ctx: Dictionary) -> Dictionary:
    _chooses += 1
    var sim_now := float(ctx.get("sim_seconds", 0.0))
    var rate := maxf(float(ctx.get("sim_rate", 144.0)), 0.0001)
    var sun_alt := float(ctx.get("sun_alt", 30.0))
    var events: Dictionary = ctx.get("events", {})
    var w := window_for(sim_now, events)
    var wid := String(w["id"])
    var wkind := String(w["kind"])
    if wid != _window_id:
        _window_id = wid
        _window_kind = wkind
        _step = 0
    var kind := _next_kind(wkind, sun_alt)
    var win := w.duplicate()
    var mins := fposmod(sim_now, 86400.0) / 60.0
    var remain_min := float(win["end"]) - mins
    if remain_min <= 1.0:
        remain_min += 1440.0
    var remain_real := (remain_min * 60.0) / rate
    var mn := float(KIND_MIN_REAL.get(kind, 5.0))
    var mx := float(KIND_MAX_REAL.get(kind, 20.0))
    if kind == "sleep":
        # Sleep lasts until the window ends (possibly hours in real-time mode),
        # re-evaluated when the world window changes or the user jumps time.
        var sd := clampf(remain_real, 20.0, 86400.0)
        # P9 / P7-FINALIZE（C 报告 D7）：预读下一个窗口；若它仍是 sleep（00:00 的
        # night_before_wake），把后一段睡眠时长接到本次决策里，避免跨 00:00 时
        # “起床 → 走回床边 → 再躺下”的每日一次抖动。世界窗口切换本身不改写 _act.dur。
        var next_w := window_for(float(win["end"]) * 60.0 + 1.0, events)
        var probe_end := float(win["end"])
        var guard := 0
        while String(next_w.get("kind", "")) == "sleep" and guard < 4:
            var add_min := float(next_w["end"]) - float(next_w["start"])
            if add_min <= 0.0:
                add_min += 1440.0
            sd = minf(86400.0, sd + (add_min * 60.0) / rate)
            probe_end += add_min
            next_w = window_for(probe_end * 60.0 + 1.0, events)
            guard += 1
        _last_reason = "window %s -> sleep" % wid
        return {
            "kind": "sleep",
            "duration_real": sd,
            "window_id": wid,
            "window_kind": wkind,
            "reason": _last_reason,
            "region_pref": "attic",
        }
    var dur := clampf(remain_real * _rng.randf_range(0.45, 0.7), mn, mx)
    var region_pref := "any"
    if wkind == "morning":
        region_pref = "indoor" if sun_alt < 2.0 else "porch"
    elif wkind.ends_with("_out"):
        region_pref = "outdoor" if sun_alt > 1.0 else "indoor"
        if sun_alt <= 1.0:
            kind = "stroll"   # walk indoors instead of standing outside in the dark
    elif wkind == "midday_rest":
        region_pref = "outdoor" if sun_alt > 8.0 else "indoor"
    elif wkind == "evening_rest":
        region_pref = "indoor"
    elif wkind == "lunch" or wkind == "dinner":
        region_pref = "floor1"
    # P8 阶段 7：天气过滤（只改本次活动的 kind/区域偏好，不改变日程窗口与预约逻辑）。
    #   severe（雷暴/台风/风暴强）→ 一律室内，散步改原地待着；
    #   雨/雪/强风 → 户外停留改到有顶门廊，散步改坐；小雪且风弱时保留少量户外赏雪。
    var weather: Dictionary = ctx.get("weather", {})
    if not weather.is_empty():
        var wx_type := String(weather.get("type", "clear"))
        var wx_precip := String(weather.get("precip_type", "none"))
        var wx_pint := float(weather.get("precip_intensity", 0.0))
        var wx_wind := float(weather.get("wind_strength", 0.0))
        var wx_storm := float(weather.get("storm", 0.0))
        var wx_severe := wx_storm > 0.60 or wx_type == "typhoon" or wx_type == "thunder"
        var wx_wet := wx_precip != "none" and wx_pint > 0.25
        var wx_gusty := wx_wind > 0.72
        var wx_snow_calm := wx_precip == "snow" and wx_pint < 0.40 and wx_storm <= 0.60
        if wx_severe:
            # 已经在室内区域（餐桌/阁楼）的日程保持原区域，只把户外/门廊改成室内。
            if region_pref != "floor1" and region_pref != "attic":
                region_pref = "indoor"
            if kind == "stroll" or LEISURE_KINDS.has(kind):
                kind = "idle"
        elif (wx_wet or wx_gusty) and region_pref == "outdoor" and not wx_snow_calm:
            region_pref = "porch"
            if kind == "stroll" or LEISURE_KINDS.has(kind):
                kind = "sit"
    # P9：两项户外休闲只在“白天 + 真正能到户外”时成立（天黑/恶劣天气回退到坐着或待着）。
    if LEISURE_KINDS.has(kind) and (region_pref != "outdoor" or sun_alt <= 1.0):
        kind = "sit" if region_pref == "porch" else "idle"
    _last_reason = "window %s -> %s (%.1f real s, pref %s)" % [wid, kind, dur, region_pref]
    return {
        "kind": kind,
        "duration_real": dur,
        "window_id": wid,
        "window_kind": wkind,
        "reason": _last_reason,
        "region_pref": region_pref,
    }


## P9：白天户外窗口的休闲动作加权随机抽取（排除上一次 kind，避免固定轮播）。
func _pick_outdoor_kind() -> String:
    var usable: Array = []
    var total := 0.0
    for item in OUTDOOR_POOL:
        var key := String(item[0])
        if key == _last_kind:
            continue
        usable.append(item)
        total += float(item[1])
    if usable.is_empty() or total <= 0.0:
        return "idle"
    var r := _rng.randf() * total
    for item in usable:
        r -= float(item[1])
        if r <= 0.0:
            return String(item[0])
    return String(usable[usable.size() - 1][0])


func _next_kind(wkind: String, sun_alt: float) -> String:
    var seq: Array = WINDOW_SEQUENCE.get(wkind, ["idle"])
    # P9：morning_out / afternoon_out 不再按固定序列播放，改为每次决策加权随机
    # （stroll / swing / sea_view / idle），配合随机时长避免“固定轮播”。
    if wkind == "morning_out" or wkind == "afternoon_out":
        _step += 1
        return _pick_outdoor_kind()
    var kind := ""
    if _step < seq.size():
        kind = String(seq[_step])
        _step += 1
    else:
        # Continue the routine with a weighted draw that never repeats the last kind.
        var pool: Array = []
        var total := 0.0
        for k in seq:
            var key := String(k)
            if key == _last_kind:
                continue
            var sh := float(KIND_SHARE.get(key, 1.0))
            pool.append([key, sh])
            total += sh
        if pool.is_empty() or total <= 0.0:
            kind = _last_kind
        else:
            var r := _rng.randf() * total
            for item in pool:
                r -= float(item[1])
                if r <= 0.0:
                    kind = String(item[0])
                    break
            if kind == "":
                kind = String(pool[pool.size() - 1][0])
    if wkind == "night" or wkind == "sleep":
        kind = "sleep"
    if sun_alt > 25.0 and kind == "sit" and wkind == "evening_rest":
        kind = "stroll"   # very bright evening (summer), still allowed to walk outside
    return kind


## Called by the controller when an activity ends (spot variety + anti-loop).
func note_finished(kind: String, spot_id: String, sim_now: float) -> void:
    _last_kind = kind
    if spot_id != "":
        _last_spot = spot_id
        _spot_free_at[spot_id] = sim_now + SPOT_COOLDOWN_SIM


## Full spot preference score; the controller passes the graph spots and asks
## for the best candidate for a kind.  unavailable => skip.
func score_spot(spot: Dictionary, kind: String, ctx: Dictionary) -> float:
    var sid := String(spot.get("id", ""))
    var sk := String(spot.get("kind", ""))
    if sk != kind:
        return -1.0
    var sim_now := float(ctx.get("sim_seconds", 0.0))
    var free_at := float(_spot_free_at.get(sid, -1e20))
    if sim_now < free_at:
        return -0.01   # allowed only as last resort
    var score := 1.0
    if sid == _last_spot:
        score -= 0.6
    var pref := String(ctx.get("region_pref", "any"))
    var region := String(spot.get("region", ""))
    if pref != "any":
        if pref == "outdoor" and region == "outdoor":
            score += 0.8
        elif pref == "indoor" and region != "outdoor":
            score += 0.8
        elif pref == "porch" and region == "porch":
            score += 0.8
        elif pref == "floor1" and region == "floor1":
            score += 0.8
        elif pref == "attic" and region == "attic":
            score += 0.8
        else:
            score -= 0.3
    return score + _rng.randf_range(0.0, 0.25)


## The controller calls this when a forward/backward time jump is detected.
func note_jump(backward: bool) -> void:
    _jumps += 1
    _step = 0
    _window_id = ""
    if backward:
        _spot_free_at.clear()


func debug_state() -> Dictionary:
    return {
        "seed": seed,
        "window": _window_id,
        "window_kind": _window_kind,
        "step": _step,
        "last_kind": _last_kind,
        "last_spot": _last_spot,
        "chooses": _chooses,
        "jumps": _jumps,
        "cooldowns": _spot_free_at.size(),
    }
