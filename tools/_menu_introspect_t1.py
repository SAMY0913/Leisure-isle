from pathlib import Path
import re
base = Path(r"D:/休闲小岛幻境/游戏工程/scripts")
head = (base/"menu.gd").read_text(encoding="utf-8")
lines = (base/"menu_orig_t1.gd").read_text(encoding="utf-8").splitlines()
tz_lines = lines[334:619]
tz = "\n".join(line.replace("\t","    ") for line in tz_lines)
head_decl = re.findall(r"^var (_\w+)", head, re.M)
tz_vars = set(re.findall(r"\b(_(?:tz|timezone|popup)\w*)", tz))
print("HEAD declared tz-related:", [v for v in head_decl if "tz" in v or "popup" in v])
print("TZ block references:", sorted(tz_vars))
missing = [v for v in sorted(tz_vars) if v not in head_decl]
print("MISSING in head:", missing)
print("TZ func defs:", re.findall(r"^func (\w+)", tz, re.M))
print("TZ first lines:", "\n".join(tz_lines[:3]))
print("TZ last lines:", "\n".join(tz_lines[-3:]))
print("tz has tabs after convert:", "\t" in tz)
(base/"scripts_dummy.txt").write_text("", encoding="utf-8") if False else None
