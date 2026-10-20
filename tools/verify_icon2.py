
from PIL import Image, ImageChops
src=Image.open(r"D:/休闲小岛幻境/游戏工程/icon.ico").convert("RGBA")
for f in ["shell_small.png","shell_large.png"]:
    try:
        ex=Image.open(r"D:/休闲小岛幻境/开发产物/shots/"+f).convert("RGBA")
        ex2=ex.resize(src.size,Image.LANCZOS)
        d=ImageChops.difference(src,ex2).convert("L")
        print(f,ex.size,"meandiff",round(sum(d.getdata())/ (32*32),2),"max",max(d.getdata()))
    except Exception as e: print(f,"err",e)
