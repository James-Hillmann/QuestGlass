@echo off
rem Double-click to update QuestGlass, then /reload in-game.
rem %~dp0 ends with a backslash, which would escape the closing quote; the . neutralizes it.
git -C "%~dp0." pull
pause
