# Windows Deployment Guide 🪟

To ensure the LIME Windows application works correctly on other machines, follow these steps for a portable release.

## 1. Build the Release
Run the following command in your terminal:
```powershell
flutter build windows --release
```

## 2. Locate the Release Folder
Navigate to the following directory:
`build/windows/runner/Release/`

## 3. Distribution (Portable)
Do **not** just copy the `.exe` file. You must copy the **entire content** of the `Release` folder to the target machine. This folder includes:
- `LIME.exe` (The main application)
- `flutter_windows.dll` (Required Flutter engine)
- Various `.dll` files for plugins (e.g., `window_manager.dll`)
- `data/` folder (Contains your assets and app code)

## 4. Prerequisite: Visual C++ Redistributable
The target PC **must** have the Visual C++ Redistributable 2015–2022 installed.
- **Download**: [vc_redist.x64.exe](https://aka.ms/vs/17/release/vc_redist.x64.exe)
- *Note: A copy is also provided in the project root for your convenience.*

## 5. Troubleshooting
If the app fails to start:
1. Open a Command Prompt or PowerShell window.
2. Drag `LIME.exe` into the window and press Enter.
3. Check for any error messages or missing DLL warnings.
