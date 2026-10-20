
import subprocess, os
from PIL import Image, ImageChops
src=Image.open(r"D:/休闲小岛幻境/游戏工程/icon.ico").convert("RGBA")
exes=[r"D:/休闲小岛幻境/发布/休闲小岛幻境.exe",r"D:/休闲小岛幻境/构建输出/休闲小岛幻境.exe",r"D:/休闲小岛幻境/发布/休闲小岛幻境.exe",r"D:/休闲小岛幻境/发布/休闲小岛幻境_图标版.exe"]
ps='''Add-Type -AssemblyName System.Drawing
$ico=[System.Drawing.Icon]::ExtractAssociatedIcon("%s")
$bmp=$ico.ToBitmap(); $bmp.Save("%s",[System.Drawing.Imaging.ImageFormat]::Png); $bmp.Width'''
for i,e in enumerate(exes):
    out=rf"D:/休闲小岛幻境/开发产物/shots/icon_check_{i}.png"
    r=subprocess.run(["powershell","-NoProfile","-Command",ps%(e.replace("/","\\"),out.replace("/","\\"))],capture_output=True,text=True)
    try:
        im=Image.open(out).convert("RGBA").resize(src.size,Image.LANCZOS)
        d=ImageChops.difference(src,im).convert("L")
        print(os.path.basename(e),"match" if max(d.getdata())==0 else "DIFF max="+str(max(d.getdata())))
    except Exception as ex: print(os.path.basename(e),"ERR",ex)
