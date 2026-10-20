from pathlib import Path
import re
p = Path(r"D:/休闲小岛幻境/游戏工程/scripts/menu.gd")
lines = p.read_text(encoding="utf-8").splitlines()
out = []
for i,l in enumerate(lines,1):
    s = l.strip()
    if s.startswith("func ") or s.startswith("var ") or s.startswith("const ") or s.startswith("signal "):
        # strip comments / Chinese trailing
        s2 = re.sub(r"#.*$", "", s).strip()
        if s2:
            out.append("%5d %s" % (i, s2))
Path(r"D:/休闲小岛幻境/游戏工程/scripts/_menu_api_t1.txt").write_text("\n".join(out), encoding="utf-8")
print("lines=%d vars_funcs=%d" % (len(lines), len(out)))
