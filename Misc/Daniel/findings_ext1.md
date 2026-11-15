# Findings - Extraction 1 (ext1, after first test activity)

## Integrity
The SHA-256 hashes of joplin.sqlite and places.sqlite on the device and on my PC were identical, so the adb pull copy is a faithful copy of the original files.

## Joplin
- ALEAPP 2026.4.5 found 8 notes and 2 notebooks in joplin.sqlite.
- 5 of the notes are the default "Welcome!" notes. They were all created at 2026-11-13 04:23:36 UTC, which is when I opened Joplin for the first time. This means the welcome notes also show when the app was first used.
- The "Gaming" notebook was created at 04:40:24 UTC and holds my 3 test notes.
- "Steam account backup" was created at 04:40:33 UTC and has a later updated time (04:5x UTC), so the edit of the password is visible as a different updated time.
- My manual SQL query in DB Browser returned the same 8 notes and the same created/updated times as ALEAPP, so the Joplin parser was accurate for this data.

## Firefox
- ALEAPP found 19 entries in Web History, 1 search term, and 38 cookies.
- The visits to steampowered.com, steamcommunity.com and wikipedia.org were between 04:37:53 and 04:38:42 UTC, a few minutes before the Joplin notes, which matches the order in which I did the activity.
- One visit can create several entries. For example, http://steampowered.com, https://steampowered.com and https://store.steampowered.com all appear at 04:37:53 because of redirects.
- My SQL query on moz_historyvisits returned 21 rows, while the Web History report shows 19 entries. Web History shows one row per URL, while the visits table keeps every single visit, so the two numbers are different.
- Only one search term was recorded ("microsoft store").
- The cookies show where the user went even without the history. The steamcommunity.com cookie "timezoneName = UTC" also confirms the device timezone.
- The databases folder has logins2.sqlite, autofill.sqlite and moz_ads.sqlite. ALEAPP has no parser for any of them.

## Problem found
The times in my first action log were not taken from the device clock, so they do not match the database (they were about 1 hour off). I removed them. The real times above come from the databases. From ext2 on, I log the real UTC time from "adb shell date -u" at the moment of each action.