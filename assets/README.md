# App Icon Assets

Put a 1024x1024 PNG at:

- `assets/AppIcon-1024.png`
- `assets/DonationQR.png` (optional, shown at top-right in app UI)
- `assets/DonationQRLight.png` (optional, light mode donation QR)
- `assets/DonationQRDark.png` (optional, dark mode donation QR)

Generate `.icns`:

```bash
cd /Users/liqi/Documents/Playground/NCMDockConverter
./scripts/make_icns.sh
```

Output:

- `assets/AppIcon.icns`

`./scripts/make_app.sh` will auto-embed `assets/AppIcon.icns` into the app bundle.
