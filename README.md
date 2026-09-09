# Switcher +

Native macOS window switcher. It runs as an accessory utility, accepts Option–Tab through an Accessibility-authorized event tap, lists real app windows, and focuses the selected window when Option is released.

Open `Switchr.xcodeproj` in Xcode, build, then grant Accessibility permission when prompted. Screen Recording is requested only when window previews are needed; without it, each card falls back to the app icon and window title.

Option–Tab includes minimized windows discovered through Accessibility. Hold Option and click a card to restore and focus that exact window, or release Option to commit the keyboard selection. Shift–Option–Tab goes backwards; Escape cancels. Long lists scroll horizontally without visible scrollbars and follow the keyboard selection. Cards adapt to the available width, with large previews, overlapping app icons, and a blue selection outline.

Use “Enable window previews” in the switcher to grant Screen Recording access, then reopen the switcher (restart the app if macOS requests it). Previews preserve the window's aspect ratio. While running with permission, the app refreshes visible-window thumbnails every eight seconds and keeps up to 100 images in memory only. Minimized windows use their last captured image when available. A window minimized before any successful capture, or content macOS cannot capture, may show its app icon instead. No images are written to disk or transmitted.

Validation: Release macOS build passed with code signing disabled. The production SwiftUI views were rendered with six and eighteen synthetic windows, including a portrait preview, to check aspect ratio, clipping, and hidden scrollbars. This is layout validation, not proof of live capture accuracy. Real Accessibility/Screen Recording grants, mouse selection while holding Option, restoration across apps/Spaces, and minimized-window captures still require an interactive macOS check.

Window discovery filters Accessibility floating/unknown helper windows and deduplicates repeated AX elements and Window Server IDs. Separate document windows remain separate, even with identical titles. Capture resolves windows by process and surface ID, with an unambiguous title/geometry fallback; minimized windows can reuse a matching cached surface. Uncaptured minimized windows still depend on macOS making a surface available.

Run the 11 matching/filter regression checks with `swiftc Switchr/Models/WindowInfo.swift Tests/WindowMatchingChecks.swift -o /tmp/switcher-window-checks && /tmp/switcher-window-checks`. Finder/Brave capture and ChatGPT helper filtering still require verification against those apps with the installed build's permissions.
