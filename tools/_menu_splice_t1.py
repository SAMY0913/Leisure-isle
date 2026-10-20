from pathlib import Path
import re, io
base = Path(r"D:/休闲小岛幻境/游戏工程/scripts")
head = (base/"menu.gd").read_text(encoding="utf-8")
tail = (base/"_menu_tail_t1.tmp").read_text(encoding="utf-8")
lines = (base/"menu_orig_t1.gd").read_text(encoding="utf-8").splitlines()
tz_lines = lines[334:619]
tz = "\n".join(line.replace("\t","    ") for line in tz_lines)
marker = "//__TZ_BLOCK__"
report = []
report.append("marker_present=%s" % (marker in head))
head2 = head.replace(marker, tz)
report.append("marker_replaced=%s" % (marker not in head2))
out = head2.rstrip("\n") + "\n\n" + tail.rstrip("\n") + "\n"
report.append("final_chars=%d final_lines=%d" % (len(out), out.count(chr(10))+1))
report.append("tabs_left=%d" % out.count(chr(9)))
funcs = re.findall(r"^func (\w+)", out, re.M)
report.append("func_count=%d" % len(funcs))
dups = sorted({f for f in funcs if funcs.count(f) > 1})
report.append("duplicate_funcs=%s" % dups)
report.append("tz_funcs=%s" % [f for f in ["_build_timezone_picker","_build_fade","open_timezone_picker","close_timezone_picker"] if f in funcs])
report.append("tail_funcs_present=%s" % [f for f in ["open","close","_reverse_anim","_layout","_set_bar","get_settings","set_settings","_set_settings_visuals"] if f in funcs])
# classes/consts sanity
report.append("class_name_ok=%s" % ("class_name IsleMenu" in out))
out.encode("utf-8")
(base/"menu.gd").write_text(out, encoding="utf-8")
(base/"menusplice_report.txt").write_text("\n".join(report), encoding="utf-8")
print("\n".join(report))
