from PIL import Image
im = Image.open("D:/休闲小岛幻境/开发产物/shots/04_boat_route.png").convert("RGB")
im.crop((560, 330, 900, 700)).resize((1020, 1110), Image.LANCZOS).save("D:/休闲小岛幻境/开发产物/shots/_crop_sail.png")
for y in range(400, 560, 20):
    print(y, im.getpixel((705, y)))
