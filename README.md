# F26_4440_S3_G4

## Course information

This repository belongs to Group 4 of Section 3 of CSIS 4440, Mobile Cybersecurity, at Douglas College during the Fall 2026 term. The repository name follows the format required for the course (Term#_4440_S#_G#), so F26 stands for Fall 2026, S3 is our section and G4 is our group number.

## Team

| Name | Student ID | Email |
|---|---|---|
| Daniel Anaya Murcia | 300403740 | anayamurciad@student.douglascollege.ca |
| Steven Anderson | 300414292 | andersons23@student.douglascollege.ca |

Instructor: kandhadaip@douglascollege.ca

## About the project

This is the group project for the course, and it focuses on the forensic analysis of Android apps that were not covered in class. Each member works on an individual part with one forensic tool and two apps, and both parts are connected by one shared scenario: a gaming account takeover. In the scenario, a user is tricked through a gaming community, loses access to their account, and then tries to hide what happened by deleting notes and browsing history. Each member looks for the evidence of the scenario in their own apps, and at the end we will combine our results into one shared timeline in UTC.

| Member | Tool(s) | Apps |
|---|---|---|
| Daniel Anaya Murcia | ALEAPP | Firefox for Android, Joplin |
| Steven Anderson | Objection + JADX, SQLite4N6 + Diffoscope | Steam Mobile, Discord |

## Project status

| Deliverable | Status |
|---|---|
| GitHub repository and README | Done (Oct 25) |
| Project proposal | Submitted (Oct 25), see ReportsAndDocuments |
| Progress report – Daniel | Submitted (Nov 15), see ReportsAndDocuments |
| Progress report – Steven | To be added by Steven |
| Integration (shared timeline) | Planned, after the individual parts |
| Final report | Due Dec 2 |
| Demo / presentation | Dec 4 |

## Daniel's part – ALEAPP on Firefox for Android and Joplin

I use ALEAPP, an open-source tool that parses Android app databases and builds an HTML report, to analyze Firefox for Android (web activity) and Joplin (notes). I run the scenario on a dedicated emulator, extract the app data at each stage, and check ALEAPP's results against my own SQL queries in DB Browser for SQLite, so I can see what the tool shows and what it misses.

**Environment.** Android 15 emulator (google_apis x86_64, root with adb root, timezone UTC), Joplin 3.7.10, Firefox for Android 160.0 (official APKs, hashes recorded), ALEAPP 2026.4.5 and DB Browser for SQLite in read-only mode. The details are in [setup_notes.md](Misc/Daniel/setup_notes.md).

**Method.** At each stage of the scenario I stop the apps, calculate the SHA-256 hash of the main databases on the device, copy the app folders with adb pull, and calculate the hash again on my PC. If both hashes match, the copy is verified. Then I run ALEAPP on the copy and check the results with SQL queries.

| Stage | What happened on the device | Status |
|---|---|---|
| ext1 | Browsing (Steam, Steam Community, Wikipedia) and three Joplin notes with fake credentials, one edited | Done, hashes match |
| ext2 | Saved a login in Firefox, closed two tabs, moved the "Discord login" note to the trash | Done, hashes match |
| ext3 | Empty the Joplin trash, clear the Firefox history, search the raw files for the deleted text | Next step |

**Main findings so far.**
- A Joplin note in the trash keeps its full text, including the password, and only gets a deleted time. Moving it to the trash also changes its updated time.
- Joplin's default welcome notes show when the app was opened for the first time.
- Firefox keeps a record of recently closed tabs.
- The saved Firefox login is stored in logins2.sqlite, a database that ALEAPP does not parse.
- Firefox for Android stores visit times in milliseconds, not in microseconds like desktop Firefox, so a query written for desktop Firefox gives wrong dates (1970).

**Files in Misc/Daniel.**

| File | Content |
|---|---|
| action_log.csv | Every action done on the device, with its UTC time |
| setup_notes.md | Test environment and tool versions |
| installed_apps.txt | Installed app versions |
| hashes/ | APK hashes and the device vs. PC hashes of each extraction |
| findings_ext1.md, findings_ext2.md | Results of each extraction |
| screenshots/ | ALEAPP report and DB Browser query screenshots |

The raw extractions, ALEAPP reports and APKs are kept outside the repository because of their size.

## Steven's part – Steam Mobile and Discord

*To be completed by Steven.* According to our proposal, Steven analyzes Steam Mobile with Objection and JADX, and Discord with SQLite4N6 and Diffoscope, using ADB and AndroidQF for acquisition, on a rooted Xiaomi Mi Note 2 and a rooted emulator. His files go in Misc/Steven.

## Repository structure

```
F26_4440_S3_G4/
├── README.md
├── .gitignore              (keeps APKs and raw extractions out of the repo)
├── ReportsAndDocuments/    (proposal, progress reports, final report)
└── Misc/
    ├── Daniel/             (Daniel's evidence and notes)
    ├── Steven/             (Steven's evidence and notes, to be added)
    └── Integration/        (shared timeline, planned)
```

We both work on the main branch, and each member only changes their own folder, so our work stays separate until the integration.
