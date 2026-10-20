
from PIL import Image, ImageChops
import subprocess
src=Image.open(r"D:/休闲小岛幻境/游戏工程/icon.ico").convert("RGBA")
e=r"D:/休闲小岛幻境/发布/休闲小岛幻境.exe"; out=r"D:/休闲小岛幻境/开发产物/shots/icon_final.png"
ps='''Add-Type -AssemblyName System.Drawing;$i=[System.Drawing.Icon]::ExtractAssociatedIcon("%s");$b=$i.ToBitmap();$b.Save("%s",[System.Drawing.Imaging.ImageFormat]::Png)'''%(e.replace("/","\\\\"),out.replace("/","\\\\"))
subprocess.run(["powershell","-NoProfile","-Command",ps],capture_output=True,text=True)
im=Image.open(out).convert("RGBA").resize(src.size,Image.LANCZOS)
d=ImageChops.difference(src,im).convert("L")
print("final icon diff max",max(d.getdata()),"size",Image.open(out).size)
