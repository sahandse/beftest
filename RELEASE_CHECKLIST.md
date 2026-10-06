# Release checklist — Befrest

Before release:
- GitHub Actions build is green.
- Test discovery on at least 2 Android devices.
- Test 1 MB, 100 MB, and 1+ GB files.
- Test multiple files.
- Test cancel.
- Test bad PIN and valid PIN.
- Test checksum mismatch handling.
- Test duplicate file names.
- Test app background/foreground behavior.
- Test Android 10, 12, 13, 14, 15+ where available.
- Finish HTTPS certificate fingerprint support.
- Finish Android Share Target and notifications.
- Create final launcher icon and splash.
- Configure release signing with GitHub Secrets.
- Produce signed APK and AAB.
- Only then tag v1.0.0.
