@echo off
rem Survivor UI installer: double-click to open it. It installs the addon
rem into C:\Git\wenilla\benilla-config\AddOns (or another AddOns folder you
rem pick in its window). See installer\SurvivorUIInstaller.ps1.
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0installer\SurvivorUIInstaller.ps1"
