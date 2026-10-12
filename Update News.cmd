@echo off
rem Double-click to fetch the latest news and open the page.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update-news.ps1"
start "" "%~dp0index.html"
