# The Daily Brief

A personal news page with daily updates on **Politics, Brazil, Tech, Cybersecurity and Gaming**.
It needs no installs: it uses only what ships with Windows (PowerShell + `curl.exe`).

## How it works

1. `update-news.ps1` reads `feeds.json`, downloads each RSS/Atom feed, and keeps stories from the
   last 3 days with duplicates removed. It writes them to `data/news.js`, plus a dated
   snapshot in `data/archive/`, which keeps the last 30 days.
2. `index.html` (with its script in `app.js`) loads `data/news.js` and shows a front page with each section, a tab for each
   category, search, an archive date picker, and light/dark mode. Open it straight from disk;
   it doesn't need a server.

## Publishing as a website (GitHub Pages)

`.github/workflows/update-news.yml` runs `update-news.ps1` on GitHub's servers every day at 10:00 UTC,
commits the new `data/` back to the repo (so the archive builds up), and deploys the site to GitHub Pages.
Only `index.html`, `app.js` and `data/` are published; the scripts and config stay in the repo.
It also deploys on every push to `main`, and you can run it by hand from the **Actions** tab.

One-time setup:

1. Create an empty repository on GitHub and push this folder to its `main` branch.
2. In the repository, open **Settings → Pages** and set **Source** to **GitHub Actions**.
3. Open **Actions → Update news and deploy → Run workflow**. The site appears at
   `https://<your-username>.github.io/<repo-name>/`.

To change the schedule, edit the `cron` line (times are in UTC). Once the site is live,
the local scheduled task below isn't needed.

## Usage (local)

| Task | How |
| --- | --- |
| Fetch news and open the page | Double-click `Update News.cmd` |
| Fetch only | `powershell -ExecutionPolicy Bypass -File .\update-news.ps1` |
| Refresh automatically every day | `powershell -ExecutionPolicy Bypass -File .\register-daily-task.ps1 -At 07:00` |
| Stop the daily refresh | `Unregister-ScheduledTask -TaskName "Daily Brief News Update" -Confirm:$false` |

## Customizing

Edit `feeds.json`:

- Add or remove feeds in any category (any RSS or Atom URL works).
- Add a new category. To give it a color, add `--c-<id>` to the CSS variables in
  `index.html`. Without one, it uses the accent color.
- Tune `maxAgeDays`, `maxPerCategory` and `maxPerSource`.

If a feed fails, the others still load, and the page footer lists the sources that failed.
