
import os
from PIL import Image, ImageDraw
SH = r"D:\休闲小岛幻境\开发产物\shots"
TW, TH = 900, 562
groups = [
    ("sheet_a", ["03_house_front", "03_roof_close", "03_interior",
                 "03_stairs_close", "03_attic_window", "03_rocks_coast"]),
    ("sheet_b", ["03_flowers_close", "03_garden", "04_night_lights",
                 "04_boat_route", "04_lantern_close", "04_lighthouse_sweep"]),
    ("sheet_c", ["04_birds", "04_bird_perch", "04_splash",
                 "04_realtime_clock", "04_time_panel", "00_settings"]),
    ("sheet_d", ["01_sunrise", "01_noon", "01_sunset",
                 "01_golden", "01_night", "04_sky_up"]),
]
for name, items in groups:
    out = Image.new("RGB", (TW * 3, TH * 2), (24, 24, 28))
    d = ImageDraw.Draw(out)
    for i, it in enumerate(items):
        p = os.path.join(SH, it + ".png")
        try:
            im = Image.open(p).convert("RGB").resize((TW, TH), Image.LANCZOS)
        except Exception as e:
            print("missing", it, e)
            continue
        x = (i % 3) * TW
        y = (i // 3) * TH
        out.paste(im, (x, y))
        d.rectangle([x, y + TH - 26, x + TW, y + TH], fill=(0, 0, 0))
        d.text((x + 8, y + TH - 20), it, fill=(255, 255, 0))
    out.save(os.path.join(SH, name + ".png"))
    print("saved", name, out.size)
