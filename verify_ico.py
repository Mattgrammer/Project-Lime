from PIL import Image
import os

ico_path = r'c:\Users\Angelo Toenbreker\StudioProjects\LIME\windows\runner\resources\lime_logo.ico'

# Open and verify the ICO
img = Image.open(ico_path)
print(f"Format: {img.format}")
print(f"Size: {img.size}")
print(f"Mode: {img.mode}")

# Check all sizes in the ICO
ico = Image.open(ico_path)
print(f"ICO info: {ico.info}")

# Read raw bytes to check header
with open(ico_path, 'rb') as f:
    header = f.read(6)
    reserved = int.from_bytes(header[0:2], 'little')
    img_type = int.from_bytes(header[2:4], 'little')
    count = int.from_bytes(header[4:6], 'little')
    print(f"\nICO Header: reserved={reserved}, type={img_type}, count={count}")
    
    for i in range(count):
        entry = f.read(16)
        w = entry[0] if entry[0] != 0 else 256
        h = entry[1] if entry[1] != 0 else 256
        colors = entry[2]
        planes = int.from_bytes(entry[4:6], 'little')
        bpp = int.from_bytes(entry[6:8], 'little')
        size = int.from_bytes(entry[8:12], 'little')
        offset = int.from_bytes(entry[12:16], 'little')
        print(f"  Entry {i}: {w}x{h}, colors={colors}, planes={planes}, bpp={bpp}, dataSize={size}, offset={offset}")

print(f"\nTotal file size: {os.path.getsize(ico_path)} bytes")
