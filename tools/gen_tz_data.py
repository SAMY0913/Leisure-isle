#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""生成 scripts/isle_tz_data.gd：IANA 时区 UTC 偏移转换表（2016-01-01 ~ 2041-01-01）。

真值来自 Python zoneinfo（IANA tzdata），逐日粗扫 + 秒级二分定位真实转换点，
不手写任何偏移。运行：D:/python/python.exe tools/gen_tz_data.py
"""
from __future__ import annotations

import datetime as dt
import json
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "scripts" / "isle_tz_data.gd"

UTC = dt.timezone.utc
BASE_UNIX = int(dt.datetime(2016, 1, 1, tzinfo=UTC).timestamp())
END_UNIX = int(dt.datetime(2041, 1, 1, tzinfo=UTC).timestamp())
DAY = 86400

# 常用 IANA 时区（id, 中文城市名, 英文城市名；按大洲分组排序，城市名用于菜单显示）。
ZONES = [
    # ---- 亚洲 ----
    ("Asia/Shanghai", "上海", "Shanghai"),
    ("Asia/Hong_Kong", "香港", "Hong Kong"),
    ("Asia/Macau", "澳门", "Macau"),
    ("Asia/Taipei", "台北", "Taipei"),
    ("Asia/Tokyo", "东京", "Tokyo"),
    ("Asia/Seoul", "首尔", "Seoul"),
    ("Asia/Singapore", "新加坡", "Singapore"),
    ("Asia/Bangkok", "曼谷", "Bangkok"),
    ("Asia/Jakarta", "雅加达", "Jakarta"),
    ("Asia/Manila", "马尼拉", "Manila"),
    ("Asia/Kuala_Lumpur", "吉隆坡", "Kuala Lumpur"),
    ("Asia/Ho_Chi_Minh", "胡志明市", "Ho Chi Minh City"),
    ("Asia/Yangon", "仰光", "Yangon"),
    ("Asia/Dhaka", "达卡", "Dhaka"),
    ("Asia/Kathmandu", "加德满都", "Kathmandu"),
    ("Asia/Kolkata", "加尔各答", "Kolkata"),
    ("Asia/Colombo", "科伦坡", "Colombo"),
    ("Asia/Karachi", "卡拉奇", "Karachi"),
    ("Asia/Dubai", "迪拜", "Dubai"),
    ("Asia/Muscat", "马斯喀特", "Muscat"),
    ("Asia/Qatar", "多哈", "Doha"),
    ("Asia/Kuwait", "科威特城", "Kuwait City"),
    ("Asia/Riyadh", "利雅得", "Riyadh"),
    ("Asia/Tehran", "德黑兰", "Tehran"),
    ("Asia/Baghdad", "巴格达", "Baghdad"),
    ("Asia/Beirut", "贝鲁特", "Beirut"),
    ("Asia/Amman", "安曼", "Amman"),
    ("Asia/Jerusalem", "耶路撒冷", "Jerusalem"),
    ("Asia/Istanbul", "伊斯坦布尔", "Istanbul"),
    ("Asia/Tashkent", "塔什干", "Tashkent"),
    ("Asia/Almaty", "阿拉木图", "Almaty"),
    ("Asia/Bishkek", "比什凯克", "Bishkek"),
    ("Asia/Ulaanbaatar", "乌兰巴托", "Ulaanbaatar"),
    ("Asia/Kabul", "喀布尔", "Kabul"),
    ("Asia/Yekaterinburg", "叶卡捷琳堡", "Yekaterinburg"),
    ("Asia/Novosibirsk", "新西伯利亚", "Novosibirsk"),
    ("Asia/Vladivostok", "符拉迪沃斯托克", "Vladivostok"),
    ("Asia/Kamchatka", "彼得罗巴甫洛夫斯克", "Petropavlovsk-Kamchatsky"),
    # ---- 欧洲 ----
    ("Europe/London", "伦敦", "London"),
    ("Europe/Dublin", "都柏林", "Dublin"),
    ("Europe/Lisbon", "里斯本", "Lisbon"),
    ("Europe/Paris", "巴黎", "Paris"),
    ("Europe/Berlin", "柏林", "Berlin"),
    ("Europe/Madrid", "马德里", "Madrid"),
    ("Europe/Rome", "罗马", "Rome"),
    ("Europe/Amsterdam", "阿姆斯特丹", "Amsterdam"),
    ("Europe/Brussels", "布鲁塞尔", "Brussels"),
    ("Europe/Zurich", "苏黎世", "Zurich"),
    ("Europe/Vienna", "维也纳", "Vienna"),
    ("Europe/Stockholm", "斯德哥尔摩", "Stockholm"),
    ("Europe/Oslo", "奥斯陆", "Oslo"),
    ("Europe/Copenhagen", "哥本哈根", "Copenhagen"),
    ("Europe/Helsinki", "赫尔辛基", "Helsinki"),
    ("Europe/Tallinn", "塔林", "Tallinn"),
    ("Europe/Riga", "里加", "Riga"),
    ("Europe/Vilnius", "维尔纽斯", "Vilnius"),
    ("Europe/Warsaw", "华沙", "Warsaw"),
    ("Europe/Prague", "布拉格", "Prague"),
    ("Europe/Budapest", "布达佩斯", "Budapest"),
    ("Europe/Athens", "雅典", "Athens"),
    ("Europe/Bucharest", "布加勒斯特", "Bucharest"),
    ("Europe/Sofia", "索非亚", "Sofia"),
    ("Europe/Kyiv", "基辅", "Kyiv"),
    ("Europe/Moscow", "莫斯科", "Moscow"),
    ("Europe/Minsk", "明斯克", "Minsk"),
    ("Europe/Belgrade", "贝尔格莱德", "Belgrade"),
    ("Europe/Zagreb", "萨格勒布", "Zagreb"),
    ("Atlantic/Reykjavik", "雷克雅未克", "Reykjavik"),
    # ---- 美洲 ----
    ("America/New_York", "纽约", "New York"),
    ("America/Chicago", "芝加哥", "Chicago"),
    ("America/Denver", "丹佛", "Denver"),
    ("America/Los_Angeles", "洛杉矶", "Los Angeles"),
    ("America/Phoenix", "凤凰城", "Phoenix"),
    ("America/Anchorage", "安克雷奇", "Anchorage"),
    ("America/Vancouver", "温哥华", "Vancouver"),
    ("America/Edmonton", "埃德蒙顿", "Edmonton"),
    ("America/Winnipeg", "温尼伯", "Winnipeg"),
    ("America/Toronto", "多伦多", "Toronto"),
    ("America/Montreal", "蒙特利尔", "Montreal"),
    ("America/Nuuk", "努克", "Nuuk"),
    ("America/Halifax", "哈利法克斯", "Halifax"),
    ("America/St_Johns", "圣约翰斯", "St. John's"),
    ("America/Mexico_City", "墨西哥城", "Mexico City"),
    ("America/Havana", "哈瓦那", "Havana"),
    ("America/Guatemala", "危地马拉城", "Guatemala City"),
    ("America/Santo_Domingo", "圣多明各", "Santo Domingo"),
    ("America/Panama", "巴拿马城", "Panama City"),
    ("America/Bogota", "波哥大", "Bogota"),
    ("America/Lima", "利马", "Lima"),
    ("America/La_Paz", "拉巴斯", "La Paz"),
    ("America/Caracas", "加拉加斯", "Caracas"),
    ("America/Santiago", "圣地亚哥", "Santiago"),
    ("America/Argentina/Buenos_Aires", "布宜诺斯艾利斯", "Buenos Aires"),
    ("America/Asuncion", "亚松森", "Asuncion"),
    ("America/Montevideo", "蒙得维的亚", "Montevideo"),
    ("America/Sao_Paulo", "圣保罗", "Sao Paulo"),
    ("America/Manaus", "马瑙斯", "Manaus"),
    # ---- 大洋洲 ----
    ("Australia/Sydney", "悉尼", "Sydney"),
    ("Australia/Melbourne", "墨尔本", "Melbourne"),
    ("Australia/Brisbane", "布里斯班", "Brisbane"),
    ("Australia/Adelaide", "阿德莱德", "Adelaide"),
    ("Australia/Darwin", "达尔文", "Darwin"),
    ("Australia/Perth", "珀斯", "Perth"),
    ("Australia/Hobart", "霍巴特", "Hobart"),
    ("Australia/Lord_Howe", "豪勋爵岛", "Lord Howe Island"),
    ("Australia/Eucla", "尤克拉", "Eucla"),
    ("Pacific/Auckland", "奥克兰", "Auckland"),
    ("Pacific/Chatham", "查塔姆群岛", "Chatham Islands"),
    ("Pacific/Fiji", "苏瓦", "Suva"),
    ("Pacific/Noumea", "努美阿", "Noumea"),
    ("Pacific/Marquesas", "马克萨斯群岛", "Marquesas"),
    ("Pacific/Port_Moresby", "莫尔兹比港", "Port Moresby"),
    ("Pacific/Guam", "关岛", "Guam"),
    ("Pacific/Honolulu", "檀香山", "Honolulu"),
    ("Pacific/Tongatapu", "努库阿洛法", "Nukualofa"),
    ("Pacific/Kiritimati", "基里蒂马蒂", "Kiritimati"),
    # ---- 非洲 ----
    ("Africa/Cairo", "开罗", "Cairo"),
    ("Africa/Johannesburg", "约翰内斯堡", "Johannesburg"),
    ("Africa/Lagos", "拉各斯", "Lagos"),
    ("Africa/Nairobi", "内罗毕", "Nairobi"),
    ("Africa/Addis_Ababa", "亚的斯亚贝巴", "Addis Ababa"),
    ("Africa/Casablanca", "卡萨布兰卡", "Casablanca"),
    ("Africa/Algiers", "阿尔及尔", "Algiers"),
    ("Africa/Tunis", "突尼斯", "Tunis"),
    ("Africa/Dakar", "达喀尔", "Dakar"),
    ("Africa/Accra", "阿克拉", "Accra"),
    ("Africa/Kinshasa", "金沙萨", "Kinshasa"),
    ("Africa/Luanda", "罗安达", "Luanda"),
    ("Africa/Harare", "哈拉雷", "Harare"),
    ("Africa/Maputo", "马普托", "Maputo"),
    ("Africa/Windhoek", "温得和克", "Windhoek"),
    # ---- 其他 ----
    ("Indian/Maldives", "马累", "Male"),
    ("Indian/Mauritius", "路易港", "Port Louis"),
    ("UTC", "协调世界时", "UTC"),
]

REQUIRED = [
    "Asia/Shanghai", "Asia/Hong_Kong", "Asia/Tokyo", "Asia/Seoul",
    "Asia/Kolkata", "Asia/Kathmandu", "Europe/London", "America/New_York",
    "America/Santiago", "Australia/Sydney", "Australia/Eucla",
    "Pacific/Marquesas", "Pacific/Kiritimati", "America/Nuuk",
]


def utc_offset(zone: ZoneInfo, ts: int) -> int:
    local = dt.datetime.fromtimestamp(ts, tz=UTC).astimezone(zone)
    return int(local.utcoffset().total_seconds())


def transitions(zone: ZoneInfo):
    """返回 [(转换时刻unix, 新偏移秒), ...]；逐日粗扫 + 秒级二分。"""
    out = []
    prev_ts = BASE_UNIX
    prev_off = utc_offset(zone, prev_ts)
    while prev_ts < END_UNIX:
        next_ts = min(prev_ts + DAY, END_UNIX)
        next_off = utc_offset(zone, next_ts)
        if next_off != prev_off:
            lo, hi = prev_ts + 1, next_ts
            while lo < hi:
                mid = (lo + hi) // 2
                if utc_offset(zone, mid) == next_off:
                    hi = mid
                else:
                    lo = mid + 1
            out.append((lo, next_off))
            prev_off = next_off
        prev_ts = next_ts
    return out


def q(text: str) -> str:
    return json.dumps(text, ensure_ascii=False)


def main() -> int:
    ids = [z[0] for z in ZONES]
    assert len(ids) == len(set(ids)), "重复时区 id"
    assert len(ids) >= 130, "时区数量不足 130：%d" % len(ids)
    for need in REQUIRED:
        assert need in ids, "缺少必需时区 %s" % need

    data = {}
    total = 0
    for zid, _city, _en in ZONES:
        zone = ZoneInfo(zid)
        base_off = utc_offset(zone, BASE_UNIX)
        flat = [base_off]
        for ts, off in transitions(zone):
            flat.extend([ts, off])
        data[zid] = flat
        total += len(flat) // 2

    lines = []
    lines.append("class_name IsleTzData")
    lines.append("extends RefCounted")
    lines.append("## 自动生成：常用 IANA 时区 UTC 偏移转换表（2016-01 ~ 2041-01）。")
    lines.append("## 数据源：Python zoneinfo / IANA tzdata，由 tools/gen_tz_data.py 逐秒二分定真；请勿手改。")
    lines.append("## ZONE_TRANS 扁平格式：[基线偏移秒, 转换时刻unix秒, 新偏移秒, 转换时刻unix秒, 新偏移秒, ...]")
    lines.append("## 基线偏移 = BASE_UNIX（2016-01-01T00:00:00Z）时刻的 UTC 偏移秒；无夏令时的时区只有 1 项。")
    lines.append("")
    lines.append("const BASE_UNIX := %d" % BASE_UNIX)
    lines.append("const END_UNIX := %d" % END_UNIX)
    lines.append("")
    lines.append("## 按大洲分组的展示/搜索顺序。")
    lines.append("const ZONE_ORDER := [")
    for zid, _city, _en in ZONES:
        lines.append("\t%s," % q(zid))
    lines.append("]")
    lines.append("")
    lines.append("const ZONE_CITIES := {")
    for zid, city, city_en in ZONES:
        lines.append("\t%s: %s," % (q(zid), q(city)))
    lines.append("}")
    lines.append("")
    lines.append("## 英文城市名（时区选项标签用，形如 “上海 Shanghai · UTC+08:00”）。")
    lines.append("const ZONE_CITIES_EN := {")
    for zid, _city, city_en in ZONES:
        lines.append("\t%s: %s," % (q(zid), q(city_en)))
    lines.append("}")
    lines.append("")

    lines.append("const ZONE_TRANS := {")
    for zid, _city, _en in ZONES:
        flat = data[zid]
        if len(flat) == 1:
            lines.append("\t%s: [%d]," % (q(zid), flat[0]))
            continue
        lines.append("\t%s: [" % q(zid))
        # 扁平数组整体按 6 个数字一行输出：首项是基线偏移，其后是 (转换时刻, 新偏移) 对。
        vals = ["%d" % v for v in flat]
        for i in range(0, len(vals), 6):
            lines.append("\t\t%s," % ", ".join(vals[i:i + 6]))
        lines.append("\t],")
    lines.append("}")
    lines.append("")

    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("zones=%d transitions=%d bytes=%d -> %s" % (len(ids), total, OUT.stat().st_size, OUT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
