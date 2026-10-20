
from PIL import Image, ImageDraw, ImageFont
import os
shots = [
 ("00_menu.png","标题界面 · 电影画幅 2.39:1"),
 ("00_settings.png","设置面板 · 全部定量项为可拖动滑条"),
 ("00_settings_drag.png","拖动音量滑条 · 把手与数值实时变化"),
 ("01_noon.png","正午 12:20 · 全岛"),
 ("01_sunset.png","日落 17:46 · 全岛"),
 ("01_night.png","深夜 22:40 · 月光与暖灯"),
 ("02_noon_sky.png","正午抬头 · 白天云层"),
 ("02_sunset_sky.png","日落天空 · 柔云与光晕"),
 ("02_night_sky.png","夜间星空 · 银河与月"),
 ("03_house_front.png","房屋正立面 · 半木结构/拱门/窗"),
 ("03_roof_close.png","屋顶近景 · 瓦片/屋脊/烟囱"),
 ("03_windmill_close.png","风车近景 · 叶轮与塔身留出间隙"),
 ("03_garden.png","花园/菜地/栅栏/秋千"),
 ("03_interior.png","开门后可见真实室内"),
 ("04_night_lights.png","夜间局部照明 · 灯具与落地光"),
 ("04_time_panel.png","可折叠 24h 时间轴 · 拖动改时刻"),
 ("04_sky_up.png","抬头看星空/银河/云"),
 ("05_quality_low.png","画质 低 · 无 MSAA/简化云水草"),
 ("05_quality_high.png","画质 高 · MSAA/云反射/满草"),
]
base = r"D:/休闲小岛幻境/开发产物/shots"
cols, tw = 3, 620
th = int(tw*900/1440)
cap = 34
font = ImageFont.truetype(r"D:/休闲小岛幻境/游戏工程/fonts/simhei.ttf", 19)
rows = (len(shots)+cols-1)//cols
pad = 10
W = cols*tw + (cols+1)*pad
H = rows*(th+cap) + (rows+1)*pad
sheet = Image.new("RGB",(W,H),(18,20,24))
d = ImageDraw.Draw(sheet)
for i,(fn,label) in enumerate(shots):
    im = Image.open(os.path.join(base,fn)).convert("RGB").resize((tw,th), Image.LANCZOS)
    c,r = i%cols, i//cols
    x = pad + c*(tw+pad); y = pad + r*(th+cap+pad)
    sheet.paste(im,(x,y))
    d.text((x+4,y+th+7), label, font=font, fill=(232,226,214))
sheet.save(os.path.join(base,"contact_sheet_02.png"), optimize=True)
print(sheet.size, os.path.getsize(os.path.join(base,"contact_sheet_02.png")))
