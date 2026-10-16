<# : Survivor UI Updater. Double-click this file to run it.
@echo off
set "SUI_SELF=%~f0"
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Invoke-Expression ([IO.File]::ReadAllText($env:SUI_SELF))"
exit /b
#>

# Survivor UI Updater: one window, one button. It downloads the latest Survivor
# UI from GitHub and brings the addon in the game's AddOns folder up to date,
# file by file: new files added, changed ones replaced, and the addon's old
# code files (.lua, .toc) that are gone removed. Anything else in the folder,
# a font you dropped in, is left alone, and so are your settings, which the
# game keeps in its WTF folder. No addon there yet: it installs it.
#
# It needs nothing installed: the top of this file starts the PowerShell that
# comes with Windows, which runs the rest.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Owner = 'NicholasIzosimov'
$Project = 'AzerothSurvivorUI'
$Branch = 'main'
if ($env:SUI_BRANCH) {
	$Branch = $env:SUI_BRANCH
}
$DefaultAddOns = 'C:\Git\wenilla\benilla-config\AddOns'
$Remembered = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'SurvivorUI-Updater.txt'

# GitHub asks for TLS 1.2, which older Windows PowerShell does not offer
# unless told to.
try {
	[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {
}

$script:Say = { param($text) Write-Host $text }

function Say($text) {
	& $script:Say $text
}

# The version a SurvivorUI.toc names ("2.5"), or $null without one.
function Get-Version($folder) {
	$toc = Join-Path $folder 'SurvivorUI.toc'
	if (-not (Test-Path -LiteralPath $toc)) {
		return $null
	}
	foreach ($line in Get-Content -LiteralPath $toc) {
		if ($line -match '^## Version:\s*(.+)$') {
			return $Matches[1].Trim()
		}
	}
	return '?'
}

# The latest version on GitHub, read off its SurvivorUI.toc; $null offline.
function Get-Latest {
	try {
		$url = "https://raw.githubusercontent.com/$Owner/$Project/$Branch/SurvivorUI/SurvivorUI.toc"
		$page = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
		if ($page.Content -match '(?m)^## Version:\s*(.+?)\s*$') {
			return $Matches[1]
		}
	} catch {
	}
	return $null
}

# A file's path inside a folder, from the folder's own full path as the disk
# gives it, so a path typed differently still lines up.
function Get-Relative($file, $root) {
	$full = (Get-Item -LiteralPath $root).FullName.TrimEnd('\', '/')
	return $file.FullName.Substring($full.Length).TrimStart('\', '/')
}

function Get-Hash($path) {
	return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}

# Downloads the latest addon and brings AddOns\SurvivorUI up to date.
function Update-Addon($addOns) {
	if (-not $addOns -or -not (Test-Path -LiteralPath $addOns -PathType Container)) {
		throw "Cannot find the AddOns folder '$addOns'. Pick it with Change..."
	}
	$dest = Join-Path $addOns 'SurvivorUI'
	$installed = Get-Version $dest
	$work = Join-Path ([IO.Path]::GetTempPath()) ('SurvivorUI-' + [guid]::NewGuid().ToString('N'))
	New-Item -ItemType Directory -Path $work | Out-Null
	try {
		Say 'Downloading the latest version...'
		$zip = Join-Path $work 'addon.zip'
		Invoke-WebRequest -Uri "https://github.com/$Owner/$Project/archive/refs/heads/$Branch.zip" -OutFile $zip -UseBasicParsing
		$unpacked = Join-Path $work 'files'
		Expand-Archive -LiteralPath $zip -DestinationPath $unpacked -Force
		$top = Get-ChildItem -LiteralPath $unpacked | Where-Object { $_.PSIsContainer } | Select-Object -First 1
		$source = Join-Path $top.FullName 'SurvivorUI'
		if (-not (Test-Path -LiteralPath (Join-Path $source 'SurvivorUI.toc'))) {
			throw 'The download holds no SurvivorUI folder.'
		}
		$latest = Get-Version $source

		$added, $changed, $removed = 0, 0, 0
		$restart = -not $installed
		$known = @{}
		foreach ($file in Get-ChildItem -LiteralPath $source -Recurse | Where-Object { -not $_.PSIsContainer }) {
			$relative = Get-Relative $file $source
			$known[$relative.ToLower()] = $true
			$target = Join-Path $dest $relative
			if (-not (Test-Path -LiteralPath $target)) {
				New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
				Copy-Item -LiteralPath $file.FullName -Destination $target -Force
				Say "  new      $relative"
				$added++
				$restart = $true
			} elseif ((Get-Hash $file.FullName) -ne (Get-Hash $target)) {
				Copy-Item -LiteralPath $file.FullName -Destination $target -Force
				Say "  updated  $relative"
				$changed++
				if ($file.Extension -eq '.toc') {
					$restart = $true
				}
			}
		}
		# The addon's own code that is gone from it; anything else stays.
		foreach ($file in Get-ChildItem -LiteralPath $dest -Recurse | Where-Object { -not $_.PSIsContainer }) {
			$relative = Get-Relative $file $dest
			if (($file.Extension -eq '.lua' -or $file.Extension -eq '.toc') -and -not $known[$relative.ToLower()]) {
				Remove-Item -LiteralPath $file.FullName -Force
				Say "  removed  $relative"
				$removed++
			}
		}

		if (-not $installed) {
			Say "Installed Survivor UI $latest."
		} elseif ($added + $changed + $removed -eq 0) {
			Say "Already up to date ($latest)."
			return
		} else {
			Say "Updated to $latest`: $changed changed, $added new, $removed removed."
		}
		if ($restart) {
			Say 'Restart the game to load it (a /reload is not enough for new files).'
		} else {
			Say 'In the game, type /reload.'
		}
	} finally {
		Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
	}
}

function Get-AddOns {
	if (Test-Path -LiteralPath $Remembered) {
		$last = Get-Content -LiteralPath $Remembered -TotalCount 1
		if ($last) {
			return $last.Trim()
		}
	}
	return $DefaultAddOns
}

##############################################################################
# The window, in the addon's own colors: dark, flat, gold.

function Show-Window {
	Add-Type -AssemblyName System.Windows.Forms
	Add-Type -AssemblyName System.Drawing
	[Windows.Forms.Application]::EnableVisualStyles()

	$dark = [Drawing.Color]::FromArgb(13, 13, 18)
	$field = [Drawing.Color]::FromArgb(24, 24, 31)
	$gold = [Drawing.Color]::FromArgb(255, 209, 0)
	$edge = [Drawing.Color]::FromArgb(158, 117, 56)
	$text = [Drawing.Color]::FromArgb(220, 220, 220)
	$muted = [Drawing.Color]::FromArgb(150, 150, 150)

	$form = New-Object Windows.Forms.Form
	$form.Text = 'Survivor UI Updater'
	$form.ClientSize = New-Object Drawing.Size(480, 330)
	$form.StartPosition = 'CenterScreen'
	$form.FormBorderStyle = 'FixedSingle'
	$form.MaximizeBox = $false
	$form.BackColor = $dark
	$form.ForeColor = $text
	$form.Font = New-Object Drawing.Font('Segoe UI', 9.5)

	$title = New-Object Windows.Forms.Label
	$title.Text = 'Survivor UI'
	$title.Font = New-Object Drawing.Font('Segoe UI', 18, [Drawing.FontStyle]::Bold)
	$title.ForeColor = $gold
	$title.Location = New-Object Drawing.Point(18, 12)
	$title.AutoSize = $true
	$form.Controls.Add($title)

	$versions = New-Object Windows.Forms.Label
	$versions.Location = New-Object Drawing.Point(21, 54)
	$versions.AutoSize = $true
	$versions.ForeColor = $muted
	$form.Controls.Add($versions)

	$folder = New-Object Windows.Forms.Label
	$folder.Location = New-Object Drawing.Point(21, 80)
	$folder.Size = New-Object Drawing.Size(350, 20)
	$folder.AutoEllipsis = $true
	$folder.ForeColor = $muted
	$folder.Text = Get-AddOns
	$form.Controls.Add($folder)

	$change = New-Object Windows.Forms.Button
	$change.Text = 'Change...'
	$change.Location = New-Object Drawing.Point(380, 76)
	$change.Size = New-Object Drawing.Size(80, 26)
	$form.Controls.Add($change)

	$go = New-Object Windows.Forms.Button
	$go.Location = New-Object Drawing.Point(20, 114)
	$go.Size = New-Object Drawing.Size(440, 48)
	$go.Font = New-Object Drawing.Font('Segoe UI', 14, [Drawing.FontStyle]::Bold)
	$form.Controls.Add($go)

	foreach ($button in @($change, $go)) {
		$button.FlatStyle = 'Flat'
		$button.FlatAppearance.BorderColor = $edge
		$button.BackColor = [Drawing.Color]::FromArgb(52, 12, 10)
		$button.ForeColor = [Drawing.Color]::FromArgb(255, 214, 107)
		$button.Cursor = 'Hand'
	}

	$log = New-Object Windows.Forms.TextBox
	$log.Location = New-Object Drawing.Point(20, 176)
	$log.Size = New-Object Drawing.Size(440, 136)
	$log.Multiline = $true
	$log.ReadOnly = $true
	$log.ScrollBars = 'Vertical'
	$log.BackColor = $field
	$log.ForeColor = $text
	$log.BorderStyle = 'FixedSingle'
	$form.Controls.Add($log)

	$script:Say = {
		param($line)
		$log.AppendText("$line`r`n")
		[Windows.Forms.Application]::DoEvents()
	}

	$script:latest = $null
	$refresh = {
		$installed = Get-Version (Join-Path $folder.Text 'SurvivorUI')
		$line = 'Installed: ' + $(if ($installed) { $installed } else { 'not yet' })
		$line += '      Latest: ' + $(if ($script:latest) { $script:latest } else { 'checking...' })
		$versions.Text = $line
		$go.Text = $(if ($installed) { 'Update' } else { 'Install' })
	}

	$change.Add_Click({
		$dialog = New-Object Windows.Forms.FolderBrowserDialog
		$dialog.Description = 'The game''s AddOns folder'
		if (Test-Path -LiteralPath $folder.Text) {
			$dialog.SelectedPath = $folder.Text
		}
		if ($dialog.ShowDialog() -eq 'OK') {
			$folder.Text = $dialog.SelectedPath
			Set-Content -LiteralPath $Remembered -Value $folder.Text
			& $refresh
		}
	})

	$go.Add_Click({
		$go.Enabled = $false
		$form.Cursor = 'WaitCursor'
		$log.Clear()
		try {
			Update-Addon $folder.Text
			Set-Content -LiteralPath $Remembered -Value $folder.Text
		} catch {
			Say "Nothing changed: $($_.Exception.Message)"
		}
		$form.Cursor = 'Default'
		$go.Enabled = $true
		& $refresh
	})

	$form.Add_Shown({
		& $refresh
		[Windows.Forms.Application]::DoEvents()
		$script:latest = Get-Latest
		if (-not $script:latest) {
			$script:latest = 'could not check (offline?)'
		}
		& $refresh
	})

	[void]$form.ShowDialog()
}

try {
	if ($env:SUI_NOWINDOW) {
		Update-Addon (Get-AddOns)
	} else {
		Show-Window
	}
} catch {
	$message = "Survivor UI Updater: $($_.Exception.Message)"
	try {
		Add-Type -AssemblyName System.Windows.Forms
		[void][Windows.Forms.MessageBox]::Show($message, 'Survivor UI')
	} catch {
		Write-Host $message
	}
}
