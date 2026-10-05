# OBU cursor artwork

`cursor-chat.png` is copied byte-for-byte from
`open-codex-browser-use/apps/chrome-extension/images/cursor-chat.png`.
The upstream MIT license is retained as `OBU-LICENSE.txt`.

`BrowserUseCursorArtwork` uses the dimensions and neutral hotspot transform from
`apps/chrome-extension/content-cursor.js`: 24px container, 23×24px image,
(12, -2.5) image offset, +44° image rotation and -44° neutral container rotation.
The virtual display preview uses this image as a CALayer overlay. It does not
move the system cursor or insert the cursor into captured frames.
