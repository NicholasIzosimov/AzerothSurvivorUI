# Survivor UI installer: a small window that puts the addon into the game's
# AddOns folder. Started by "Install Survivor UI.cmd" in the repository's
# root; it runs on the PowerShell that comes with Windows, nothing to install.
#
# The window: the AddOns folder (C:\Git\wenilla\benilla-config\AddOns until
# another is picked, then the last one used), how to install, and Install.
#   Copy  copies the SurvivorUI folder over whatever is there. Files the addon
#         no longer has are left alone, so a font dropped into
#         SurvivorUI\Fonts survives.
#   Link  makes AddOns\SurvivorUI a link (a junction) to this repository's
#         SurvivorUI folder: every git pull is in the game after /reload,
#         with nothing to copy.
# With "Pull the latest changes first" it runs git pull (fast-forward only:
# local changes are never overwritten) before installing.
#
# Without the window, for a shortcut or a script:
#   powershell -ExecutionPolicy Bypass -File SurvivorUIInstaller.ps1 -Quiet
#   ... -Quiet -Link -AddOns "D:\Path\To\AddOns" -NoPull

param(
	[switch]$Quiet,
	[switch]$Link,
	[switch]$NoPull,
	[string]$AddOns
)

$ErrorActionPreference = 'Stop'

# Anything that goes wrong outside the Install button says so in a message
# box: the launcher hides the console, so it would otherwise go unseen.
trap {
	$message = "Survivor UI installer: $($_.Exception.Message)"
	if ($Quiet) {
		Write-Host $message
	} else {
		try {
			Add-Type -AssemblyName System.Windows.Forms
			[void][Windows.Forms.MessageBox]::Show($message, 'Survivor UI')
		} catch {
			Write-Host $message
		}
	}
	exit 1
}

$DefaultAddOns = 'C:\Git\wenilla\benilla-config\AddOns'
$Repo = Split-Path -Parent $PSScriptRoot
$Source = Join-Path $Repo 'SurvivorUI'
$Remembered = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'SurvivorUI-Installer.txt'

##############################################################################
# The work, shared by the window and -Quiet. Each step reports through $Say.

$script:Say = { param($text) Write-Host $text }

function Say($text) {
	& $script:Say $text
}

# The version a .toc names ("2.5"), or $null.
function Get-AddonVersion($folder) {
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

function Test-Link($path) {
	if (-not (Test-Path -LiteralPath $path)) {
		return $false
	}
	$item = Get-Item -LiteralPath $path -Force
	return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

# Removes a link without touching what it points to: rmdir takes a junction
# away on its own, where a recursive delete could follow it into the repository.
function Remove-Link($path) {
	cmd /c rmdir "$path" | Out-Null
	if (Test-Path -LiteralPath $path) {
		throw "Could not remove the old link at $path."
	}
}

function Test-Git {
	return (Test-Path -LiteralPath (Join-Path $Repo '.git')) -and [bool](Get-Command git -ErrorAction SilentlyContinue)
}

function Invoke-Pull {
	if (-not (Test-Git)) {
		Say 'Not a git checkout (or git is not installed): installing the files as they are.'
		return
	}
	Say 'Pulling the latest changes...'
	# git reports progress on its error stream; that is not a failure here.
	$ErrorActionPreference = 'Continue'
	$output = & git -C $Repo pull --ff-only 2>&1
	foreach ($line in $output) {
		Say "  $line"
	}
	if ($LASTEXITCODE -ne 0) {
		Say 'Could not pull; installing the files as they are.'
	}
}

function Install-Addon($addOns, [bool]$link, [bool]$pull) {
	if (-not (Test-Path -LiteralPath (Join-Path $Source 'SurvivorUI.toc'))) {
		throw "Cannot find $Source\SurvivorUI.toc. Keep this installer inside the repository folder."
	}
	if (-not $addOns -or -not (Test-Path -LiteralPath $addOns -PathType Container)) {
		throw "The AddOns folder '$addOns' does not exist."
	}
	if ($pull) {
		Invoke-Pull
	}
	$dest = Join-Path $addOns 'SurvivorUI'
	$linked = Test-Link $dest

	if ($link) {
		if ($linked) {
			Remove-Link $dest
		} elseif (Test-Path -LiteralPath $dest) {
			if (-not (Confirm-Replace $dest)) {
				Say 'Left as it was.'
				return
			}
			Remove-Item -LiteralPath $dest -Recurse -Force
		}
		cmd /c mklink /J "$dest" "$Source" | Out-Null
		if (-not (Test-Link $dest)) {
			throw "Could not make the link at $dest."
		}
		Say "Linked $dest to $Source."
		Say 'Every git pull here is in the game after /reload.'
	} else {
		if ($linked) {
			Remove-Link $dest
		}
		if (-not (Test-Path -LiteralPath $dest)) {
			New-Item -ItemType Directory -Path $dest | Out-Null
		}
		Copy-Item -Path (Join-Path $Source '*') -Destination $dest -Recurse -Force
		Say "Installed Survivor UI $(Get-AddonVersion $Source) to $dest."
		Say 'In the game: /reload, or restart it if the addon is new.'
	}
}

# What is installed now, for the window's status line.
function Get-Installed($addOns) {
	$dest = Join-Path $addOns 'SurvivorUI'
	$version = Get-AddonVersion $dest
	if (-not $version) {
		return 'Not installed in this folder yet.'
	}
	if (Test-Link $dest) {
		return "Installed: $version, linked to this repository."
	}
	return "Installed: $version (copied). This repository has $(Get-AddonVersion $Source)."
}

##############################################################################
# Without the window.

if ($Quiet) {
	function Confirm-Replace($path) {
		Say "$path is a normal folder; replacing it with a link."
		return $true
	}
	if (-not $AddOns) {
		$AddOns = $DefaultAddOns
	}
	try {
		Install-Addon $AddOns $Link.IsPresent (-not $NoPull.IsPresent)
		exit 0
	} catch {
		Write-Host "Survivor UI was not installed: $($_.Exception.Message)"
		exit 1
	}
}

##############################################################################
# The window, in the addon's own colors: dark, flat, gold.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$Dark = [Drawing.Color]::FromArgb(13, 13, 18)
$Field = [Drawing.Color]::FromArgb(24, 24, 31)
$Gold = [Drawing.Color]::FromArgb(255, 209, 0)
$GoldEdge = [Drawing.Color]::FromArgb(158, 117, 56)
$Text = [Drawing.Color]::FromArgb(220, 220, 220)
$Muted = [Drawing.Color]::FromArgb(150, 150, 150)
$Font = New-Object Drawing.Font('Segoe UI', 9.5)

function Confirm-Replace($path) {
	$answer = [Windows.Forms.MessageBox]::Show(
		"$path is already there as a normal folder.`n`nReplace it with a link to this repository?",
		'Survivor UI', 'YesNo', 'Question')
	return $answer -eq 'Yes'
}

$form = New-Object Windows.Forms.Form
$form.Text = 'Survivor UI installer'
$form.ClientSize = New-Object Drawing.Size(560, 420)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.BackColor = $Dark
$form.ForeColor = $Text
$form.Font = $Font

function Add-Label($text, $x, $y, $color, $size) {
	$label = New-Object Windows.Forms.Label
	$label.Text = $text
	$label.Location = New-Object Drawing.Point($x, $y)
	$label.AutoSize = $true
	$label.ForeColor = $color
	if ($size) {
		$label.Font = New-Object Drawing.Font('Segoe UI', $size, [Drawing.FontStyle]::Bold)
	}
	$form.Controls.Add($label)
	return $label
}

function Style-Button($button) {
	$button.FlatStyle = 'Flat'
	$button.FlatAppearance.BorderColor = $GoldEdge
	$button.BackColor = [Drawing.Color]::FromArgb(52, 12, 10)
	$button.ForeColor = [Drawing.Color]::FromArgb(255, 214, 107)
	$button.Cursor = 'Hand'
}

Add-Label 'Survivor UI' 18 14 $Gold 16 | Out-Null
Add-Label "Version $(Get-AddonVersion $Source) in this repository" 20 48 $Muted | Out-Null

Add-Label 'AddOns folder' 20 84 $Text | Out-Null
$folder = New-Object Windows.Forms.TextBox
$folder.Location = New-Object Drawing.Point(20, 106)
$folder.Size = New-Object Drawing.Size(420, 26)
$folder.BackColor = $Field
$folder.ForeColor = $Text
$folder.BorderStyle = 'FixedSingle'
$folder.Text = $DefaultAddOns
if (Test-Path -LiteralPath $Remembered) {
	$last = (Get-Content -LiteralPath $Remembered -TotalCount 1)
	if ($last) {
		$folder.Text = $last.Trim()
	}
}
$form.Controls.Add($folder)

$browse = New-Object Windows.Forms.Button
$browse.Text = 'Browse...'
$browse.Location = New-Object Drawing.Point(450, 104)
$browse.Size = New-Object Drawing.Size(90, 28)
Style-Button $browse
$form.Controls.Add($browse)

$copyOption = New-Object Windows.Forms.RadioButton
$copyOption.Text = 'Copy the files'
$copyOption.Location = New-Object Drawing.Point(20, 146)
$copyOption.AutoSize = $true
$copyOption.Checked = $true
$form.Controls.Add($copyOption)

$linkOption = New-Object Windows.Forms.RadioButton
$linkOption.Text = 'Link to this repository (every git pull goes straight into the game)'
$linkOption.Location = New-Object Drawing.Point(20, 172)
$linkOption.AutoSize = $true
$form.Controls.Add($linkOption)

$pullOption = New-Object Windows.Forms.CheckBox
$pullOption.Text = 'Pull the latest changes first (git)'
$pullOption.Location = New-Object Drawing.Point(20, 204)
$pullOption.AutoSize = $true
$pullOption.Checked = Test-Git
$pullOption.Enabled = Test-Git
$form.Controls.Add($pullOption)

$install = New-Object Windows.Forms.Button
$install.Text = 'Install'
$install.Location = New-Object Drawing.Point(20, 238)
$install.Size = New-Object Drawing.Size(520, 36)
$install.Font = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold)
Style-Button $install
$form.Controls.Add($install)

$status = Add-Label '' 20 284 $Muted

$log = New-Object Windows.Forms.TextBox
$log.Location = New-Object Drawing.Point(20, 308)
$log.Size = New-Object Drawing.Size(520, 96)
$log.Multiline = $true
$log.ReadOnly = $true
$log.ScrollBars = 'Vertical'
$log.BackColor = $Field
$log.ForeColor = $Text
$log.BorderStyle = 'FixedSingle'
$form.Controls.Add($log)

$script:Say = {
	param($text)
	$log.AppendText("$text`r`n")
	[Windows.Forms.Application]::DoEvents()
}

function Update-Status {
	if (Test-Path -LiteralPath $folder.Text -PathType Container) {
		$status.Text = Get-Installed $folder.Text
		$status.ForeColor = $Muted
		if (Test-Link (Join-Path $folder.Text 'SurvivorUI')) {
			$linkOption.Checked = $true
		}
	} else {
		$status.Text = 'That folder does not exist.'
		$status.ForeColor = [Drawing.Color]::FromArgb(255, 110, 110)
	}
}

$browse.Add_Click({
	$dialog = New-Object Windows.Forms.FolderBrowserDialog
	$dialog.Description = 'The game''s AddOns folder'
	if (Test-Path -LiteralPath $folder.Text) {
		$dialog.SelectedPath = $folder.Text
	}
	if ($dialog.ShowDialog() -eq 'OK') {
		$folder.Text = $dialog.SelectedPath
	}
})

$folder.Add_TextChanged({ Update-Status })

$install.Add_Click({
	$install.Enabled = $false
	$log.Clear()
	try {
		Install-Addon $folder.Text $linkOption.Checked $pullOption.Checked
		Set-Content -LiteralPath $Remembered -Value $folder.Text
	} catch {
		Say "Not installed: $($_.Exception.Message)"
	}
	Update-Status
	$install.Enabled = $true
})

Update-Status
[void]$form.ShowDialog()
