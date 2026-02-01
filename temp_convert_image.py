import base64
import os

# Read the image
image_path = r'C:\Users\Angelo Toenbreker\.gemini\antigravity\brain\0271360e-3df0-4665-904c-b5e86e862c9f\uploaded_media_1769845437184.png'
output_path = r'C:\Users\Angelo Toenbreker\StudioProjects\LIME\lib\constants\demo_images.dart'

# Ensure directory exists
os.makedirs(os.path.dirname(output_path), exist_ok=True)

# Read and encode image
with open(image_path, 'rb') as img_file:
    img_data = img_file.read()
    b64_string = base64.b64encode(img_data).decode('utf-8')

# Write Dart file
with open(output_path, 'w') as dart_file:
    dart_file.write(f"const String billGatesBase64 = '''{b64_string}''';\n")

print(f"Created {output_path}")
print(f"Base64 length: {len(b64_string)}")
