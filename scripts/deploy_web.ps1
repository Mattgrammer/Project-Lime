# LIME Web Deployment Script
Write-Host "--- Starting LIME Web Build ---" -ForegroundColor Cyan

# 1. Build the web app
flutter build web --release

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Flutter build failed." -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "--- Deployment to Firebase Hosting ---" -ForegroundColor Cyan

# 2. Deploy to Firebase
firebase deploy --only hosting

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Firebase deployment failed." -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "--- SUCCESS: LIME is now live! ---" -ForegroundColor Green
