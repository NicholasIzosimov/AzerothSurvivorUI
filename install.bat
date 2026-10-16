@echo off
setlocal EnableExtensions

rem Survivor UI installer, for Windows. Double-click it, or run it from a
rem command prompt:
rem
rem   install.bat                    copies the addon into the AddOns folder below
rem   install.bat link               links the AddOns folder to this repository
rem                                  instead: every "git pull" (or edit) here is
rem                                  in the game after /reload, nothing to copy
rem   install.bat copy "D:\AddOns"   another AddOns folder (works with link too)
rem
rem In a git checkout it pulls the latest first (fast-forward only; local
rem changes are never overwritten).

set "ADDONS=C:\Git\wenilla\benilla-config\AddOns"
set "MODE=copy"
if /I "%~1"=="link" set "MODE=link"
if /I "%~1"=="copy" set "MODE=copy"
if not "%~2"=="" set "ADDONS=%~2"
if not "%~1"=="" if /I not "%~1"=="link" if /I not "%~1"=="copy" set "ADDONS=%~1"

set "REPO=%~dp0"
set "SOURCE=%REPO%SurvivorUI"
set "DEST=%ADDONS%\SurvivorUI"

if not exist "%SOURCE%\SurvivorUI.toc" (
	echo Cannot find "%SOURCE%\SurvivorUI.toc". Run this from the repository folder.
	goto fail
)
if not exist "%ADDONS%\" (
	echo The AddOns folder "%ADDONS%" does not exist.
	echo Give the right one: install.bat copy "D:\Path\To\AddOns"
	goto fail
)

where git >nul 2>nul
if errorlevel 1 goto nogit
if not exist "%REPO%.git" goto nogit
echo Pulling the latest changes...
git -C "%REPO%." pull --ff-only
if errorlevel 1 echo   Could not pull; installing the files as they are.
:nogit

rem Is there a link from an earlier "install.bat link"?
set "LINKED="
dir /AL /B "%ADDONS%" 2>nul | findstr /I /X "SurvivorUI" >nul
if not errorlevel 1 set "LINKED=1"

if "%MODE%"=="link" goto link

rem Copy: a link from before is removed first (only the link, never this
rem repository), then the files are copied over whatever is there. Files the
rem addon no longer has are left alone, so a font dropped into
rem SurvivorUI\Fonts survives.
if defined LINKED rmdir "%DEST%"
robocopy "%SOURCE%" "%DEST%" /E /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 (
	echo Copying failed.
	goto fail
)
echo Installed Survivor UI to "%DEST%".
echo In the game: /reload (or restart it if the addon is new).
goto done

:link
if defined LINKED (
	rmdir "%DEST%"
) else if exist "%DEST%\" (
	echo "%DEST%" is already there as a normal folder.
	choice /M "Replace it with a link to this repository"
	if errorlevel 2 goto done
	rmdir /S /Q "%DEST%"
)
mklink /J "%DEST%" "%SOURCE%" >nul
if errorlevel 1 (
	echo Could not make the link.
	goto fail
)
echo Linked "%DEST%" to "%SOURCE%".
echo Every git pull here is in the game after /reload.
goto done

:fail
echo.
echo Survivor UI was not installed.
if not defined NOPAUSE pause
exit /b 1

:done
if not defined NOPAUSE pause
exit /b 0
