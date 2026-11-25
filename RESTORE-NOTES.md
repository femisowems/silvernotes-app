# Restoring the binary assets in this backup

This GitHub backup carries every text file as-is: all Swift sources,
Package.swift, build-app.sh, README. Binary assets — the app icon
(AppIcon.icns) and the icon source images — are stored as base64 text
(`*.b64`) because the backup channel is text-only. The raw binaries are
NOT in this repo; the `.b64` files are the byte-exact originals, encoded.
To restore one, decode it back to its real name:

    base64 -d -i AppIcon.icns.b64 -o AppIcon.icns
    base64 -d -i IconSource/AppIcon-master-1024.png.b64 -o IconSource/AppIcon-master-1024.png

Same pattern for every `.b64` file (iconset sizes, alternate icons,
size preview). After decoding, the tree matches the buildable project:
AppIcon.icns sits at the project root beside build-app.sh.
