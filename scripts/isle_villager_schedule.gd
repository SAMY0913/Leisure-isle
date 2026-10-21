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
}
const KIND_MAX_REAL := {
    "sleep": 7200.0,
    "eat": 26.0,
    "sit": 48.0,
    "stroll": 20.0,
    "idle": 14.0,
}
const KIND_SHARE := {
    "sleep": 4.0,
    "eat": 3.0,
    "sit": 2.0,
    "stroll": 3.0,
    "idle": 1.0,
}
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
    _last_reason = "window %s -> %s (%.1f real s, pref %s)" % [wid, kind, dur, region_pref]
    return {
        "kind": kind,
        "duration_real": dur,
        "window_id": wid,
        "window_kind": wkind,
        "reason": _last_reason,
        "region_pref": region_pref,
    }


func _next_kind(wkind: String, sun_alt: float) -> String:
    var seq: Array = WINDOW_SEQUENCE.get(wkind, ["idle"])
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
