<div align="center">

<img src="Kobold.koplugin/icons/kobold.svg" width="96" alt="Kobold Logo" />
<img src="images/kobold-white.svg" width="96" alt="Kobold Logo" />

# Kobold

**A home screen for KOReader with the calm, familiar look of your e-reader's original software.**
 
[![Release](https://img.shields.io/github/v/release/unitreign/kobold?label=version&color=black)](https://github.com/unitreign/kobold/releases/latest)
[![License: GPL v3](https://img.shields.io/badge/license-GPL--3.0-black)](LICENSE)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-support-ff5e5b?logo=ko-fi&logoColor=white)](https://ko-fi.com/unitreign)
[![Downloads](https://img.shields.io/github/downloads/unitreign/kobold/total?color=black)](https://github.com/unitreign/kobold/releases)

</div>

---

Kobold is a [KOReader](https://github.com/koreader/koreader) plugin that gives you a proper home screen. Your current books up front, your library a tap away, and everything else out of the way. Made out of love for the look of the stock reader software, rebuilt to run inside KOReader.

## Screenshots

<div align="center">

<img src="screenshots/home-2.0.png" width="420" />

*Kobold 2.0: your own toolbar and nav bar, with custom actions and live stats on Home*

| Home | My Books |
|:---:|:---:|
| <img src="screenshots/home.png" width="280" /> | <img src="screenshots/allbooks.png" width="280" /> |

| Authors | Series |
|:---:|:---:|
| <img src="screenshots/authors.png" width="280" /> | <img src="screenshots/series.png" width="280" /> |

</div>

## Features

- **Home** with the books you are reading, your library and a collection at a glance, plus your reading stats
- **My Books** with Books, Authors, Series and Collections tabs, in list or grid view
- **Filter and sort** your books by status, date added or title
- **Collections** that work like the stock reader: create, rename and manage them, add books with filter, sort and search, and keep a view per collection
- **Search** your books by title, author or series, with recent searches
- **Book menu and details page** with Read now, View Details, Add to collection, and the cover, synopsis and file details
- **Your reading row** on Home, remove books from it or bring older ones back with Show in Home
- **Quick settings** from the status bar, in the stock reader's style: brightness and natural light (with auto warmth), Wi-Fi, battery with time left, and a clock popup with the date and auto-sleep
- **Your own toolbar and nav bar**: add, remove and reorder items, and make custom actions with your own icon that run any KOReader action or plugin
- **Home widgets** you can set up: show a series or collection of your choice, change what Continue Reading and the reading stats say and do
- **Live text** on Home with tokens like `[time]`, `[streak]` or `[battery]`
- **Book actions** right from Kobold: mark as finished or unread, reset a book
- **Translatable**, with a template ready for other languages
- **Fast**, with covers and book info cached so screens open quickly

## Planned

### Next

- **Activity** tab with your current book, reading time, sessions and how many books you have finished

### Later

- **More languages** for Kobold's own text

## Requirements

- [KOReader](https://github.com/koreader/koreader), any reasonably recent build
- A Kobo, Kindle, or other device KOReader supports
- The Cover Browser plugin enabled (it ships with KOReader) for book covers

## Installation

1. Go to the [Releases](https://github.com/unitreign/kobold/releases/latest) page and download `Kobold.koplugin.zip`
2. Extract the zip and you should get a folder called `Kobold.koplugin`
3. Copy that folder into KOReader's plugins folder:
   - **Kobo:** `/mnt/onboard/.adds/koreader/plugins/`
   - **Kindle:** `extensions/koreader/plugins/`
   - Other devices: wherever your KOReader `plugins/` folder lives
4. Restart KOReader
5. Open Kobold from the file browser menu, or set it as your start screen under **Start with > Kobold Home**

## Uninstall

Delete the `Kobold.koplugin` folder from your plugins folder and restart KOReader.

## Release history

Commit messages were cleaned up on 2026-11-02. The code didn't change, but the release tags (v1.0 to v1.4) still point at the commits from before the cleanup, so they won't show up in `main`'s history. The releases and their downloads work as normal.

## License

Kobold is licensed under the **GNU General Public License v3.0**. See [LICENSE](LICENSE).

---

<div align="center">

If Kobold is useful to you, consider supporting development.

[![Support on Ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/unitreign)

</div>
