"""
Generate a proper ICO from LIME logo using Pillow,
then patch the planes field to 1 (Inno Setup requirement).
"""
from PIL import Image
import struct
import shutil
import os

src = r'c:\Users\Angelo Toenbreker\StudioProjects\LIME\lib\pages\assets\LIME ASSETS\lime.png'
ico_out = r'c:\Users\Angelo Toenbreker\StudioProjects\LIME\windows\runner\resources\lime_logo.ico'
app_ico = r'c:\Users\Angelo Toenbreker\StudioProjects\LIME\windows\runner\resources\app_icon.ico'

sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]

img = Image.open(src).convert('RGBA')
print(f"Source: {img.size[0]}x{img.size[1]}")

# Save with Pillow first
img.save(ico_out, format='ICO', sizes=sizes)
print(f"Pillow ICO saved: {os.path.getsize(ico_out)} bytes")

# Now patch: set planes=1 for all directory entries
# ICO header is 6 bytes, each directory entry is 16 bytes
# planes is at byte offset 4-5 within each entry (so absolute offset 6 + i*16 + 4)
with open(ico_out, 'r+b') as f:
    header = f.read(6)
    count = struct.unpack_from('<H', header, 4)[0]
    print(f"Patching {count} entries: setting planes=1")
    
    for i in range(count):
        entry_offset = 6 + i * 16
        # Read current entry
        f.seek(entry_offset)
        entry = bytearray(f.read(16))
        
        old_planes = struct.unpack_from('<H', entry, 4)[0]
        # Set planes to 1
        struct.pack_into('<H', entry, 4, 1)
        
        # Write back
        f.seek(entry_offset)
        f.write(entry)
        
        w = entry[0] if entry[0] != 0 else 256
        h = entry[1] if entry[1] != 0 else 256
        print(f"  Entry {i}: {w}x{h} planes: {old_planes} -> 1")

print(f"Patched ICO: {os.path.getsize(ico_out)} bytes")

# Copy as app_icon.ico
shutil.copy2(ico_out, app_ico)
print(f"Copied to {app_ico}")

# Verify
from PIL import Image as Im2
v = Im2.open(ico_out)
print(f"Verify - Format: {v.format}, Size: {v.size}, Sizes: {v.info.get('sizes')}")
