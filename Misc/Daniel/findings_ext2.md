# Findings - Extraction 2 (ext2, after the first anti-forensic step)

## Integrity
The SHA-256 hashes of joplin.sqlite and places.sqlite on the device and on my PC were identical.

## Joplin - note moved to trash
- "Discord login" was moved to the trash at 2026-11-15 07:15:45 UTC. ALEAPP shows this time in the Deleted column.
- The note is still complete in joplin.sqlite: ALEAPP shows the full body, including the password "Discord_Pass123!". Moving a note to the trash only sets deleted_time; it does not remove the content.
- Moving the note to the trash also changed its updated_time to 07:15:45. Because of this, after a note is trashed, the Updated column no longer shows the last real edit.
- The other notes were not changed. "Steam account backup" still shows the edit at 04:55:07.

## Firefox - saved login and closed tabs
- ALEAPP now shows a "Recently Closed Tabs" section with example.com (07:14:35) and wikipedia.org (07:14:39). These times match my action log. This section did not appear in ext1 because no tab had been closed yet.
- The saved login for the-internet.herokuapp.com is stored in databases/logins2.sqlite (table loginsL). ALEAPP has no parser for this database, so the saved login only appears with manual analysis.
- The visits table grew from 21 to 29 rows (the login page, example.com and wikipedia.org).

## Timestamp format problem
My SQL query on moz_historyvisits returned dates in 1970. Firefox for Android stores visit_date in milliseconds, while desktop Firefox uses microseconds, and I had divided by 1,000,000. ALEAPP converts these times correctly. An examiner who uses a query written for desktop Firefox would get wrong dates.
