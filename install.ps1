# Installer of the "WoW Forever" desktop shortcut: copies the launch script to
# %LOCALAPPDATA%\WoWForeverLaunch, finds Battle.net and the game (for the icon), and keeps an
# optional sign-in encrypted for this Windows user (DPAPI). "Remove" removes all of it.
param([switch]$Test, [string]$TestDir = '', [string]$TestDesktop = '')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$src = Join-Path $PSScriptRoot 'files'
$dest = if ($TestDir) { $TestDir } else { Join-Path $env:LOCALAPPDATA 'WoWForeverLaunch' }
$desktop = if ($TestDesktop) { $TestDesktop } else { [Environment]::GetFolderPath('Desktop') }
$lnk = Join-Path $desktop 'WoW Forever.lnk'

function Find-Bnet {
    foreach ($key in @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Battle.net',
                       'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Battle.net')) {
        try {
            $loc = (Get-ItemProperty $key -ErrorAction Stop).InstallLocation
            if ($loc -and (Test-Path (Join-Path $loc 'Battle.net.exe'))) { return (Join-Path $loc 'Battle.net.exe') }
        } catch {}
    }
    foreach ($p in @("${env:ProgramFiles(x86)}\Battle.net\Battle.net.exe", "$env:ProgramFiles\Battle.net\Battle.net.exe")) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Find-WowExe {
    foreach ($d in Get-PSDrive -PSProvider FileSystem) {
        foreach ($rel in @('Games\World of Warcraft\_forever_', 'World of Warcraft\_forever_',
                           'Program Files (x86)\World of Warcraft\_forever_', 'Program Files\World of Warcraft\_forever_',
                           'Battle.net\World of Warcraft\_forever_')) {
            $p = Join-Path (Join-Path $d.Root $rel) 'Wow.exe'
            if (Test-Path $p) { return $p }
        }
    }
    return $null
}

function Install-Launcher($bnet, $user, $pass) {
    New-Item -ItemType Directory -Force $dest | Out-Null
    Copy-Item (Join-Path $src 'launch.ps1'), (Join-Path $src 'WoW Forever.vbs') $dest -Force
    Set-Content -Encoding UTF8 (Join-Path $dest 'config.txt') $bnet
    $credFile = Join-Path $dest 'login.dat'
    if ($user -and $pass) {
        $lines = @(
            (ConvertTo-SecureString $user -AsPlainText -Force | ConvertFrom-SecureString),
            ($pass | ConvertFrom-SecureString)
        )
        Set-Content -Encoding ASCII $credFile $lines
    } elseif (Test-Path $credFile) {
        Remove-Item -Force $credFile
    }
    $wow = Find-WowExe
    $sh = New-Object -ComObject WScript.Shell
    $s = $sh.CreateShortcut($lnk)
    $s.TargetPath = "$env:WINDIR\System32\wscript.exe"
    $s.Arguments = '"' + (Join-Path $dest 'WoW Forever.vbs') + '"'
    $s.WorkingDirectory = $dest
    $s.IconLocation = if ($wow) { "$wow,0" } else { "$bnet,0" }
    $s.Description = 'World of Warcraft: Forever'
    $s.Save()
    return $wow
}

function Uninstall-Launcher {
    if (Test-Path $lnk) { Remove-Item -Force $lnk }
    if ((Test-Path $dest) -and (Split-Path -Leaf $dest) -eq 'WoWForeverLaunch') { Remove-Item -Recurse -Force $dest }
}

# test run without the window
if ($Test) {
    $sec = ConvertTo-SecureString 'test-pass+(x)' -AsPlainText -Force
    $wow = Install-Launcher (Find-Bnet) 'test@example.com' $sec
    Write-Output "installed to $dest, icon from $wow"
    return
}

# --- the window ---
$form = New-Object Windows.Forms.Form
$form.Text = 'WoW Forever - shortcut'
$form.AutoScaleMode = 'Dpi'
$form.ClientSize = New-Object Drawing.Size(460, 360)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.Font = New-Object Drawing.Font('Segoe UI', 10)

# labels never reach over the input fields (a label on top of a field takes its clicks)
function Add-Label($text, $y, $h, $w = 428) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object Drawing.Point(16, $y)
    $l.Size = New-Object Drawing.Size($w, $h)
    $form.Controls.Add($l)
    $l.SendToBack()
}
Add-Label 'The "WoW Forever" desktop shortcut starts the game right away, without showing the Battle.net window.' 12 40
Add-Label 'Auto sign-in (optional). If the account is signed out, the shortcut types the login and password itself. Left empty, it just shows the sign-in window. The password is kept encrypted and can be read only under your Windows user account.' 58 100

Add-Label 'Login (e-mail):' 170 22 128
$user = New-Object Windows.Forms.TextBox
$user.Location = New-Object Drawing.Point(150, 168)
$user.Size = New-Object Drawing.Size(294, 26)
$form.Controls.Add($user)

Add-Label 'Password:' 206 22 128
$pass = New-Object Windows.Forms.TextBox
$pass.UseSystemPasswordChar = $true
$pass.Location = New-Object Drawing.Point(150, 204)
$pass.Size = New-Object Drawing.Size(294, 26)
$form.Controls.Add($pass)

$status = New-Object Windows.Forms.Label
$status.Location = New-Object Drawing.Point(16, 244)
$status.Size = New-Object Drawing.Size(428, 50)
$form.Controls.Add($status)

$install = New-Object Windows.Forms.Button
$install.Text = 'Install'
$install.Location = New-Object Drawing.Point(16, 308)
$install.Size = New-Object Drawing.Size(150, 36)
$form.Controls.Add($install)

$remove = New-Object Windows.Forms.Button
$remove.Text = 'Remove'
$remove.Location = New-Object Drawing.Point(176, 308)
$remove.Size = New-Object Drawing.Size(120, 36)
$form.Controls.Add($remove)

$install.Add_Click({
    try {
        $bnet = Find-Bnet
        if (-not $bnet) {
            $dlg = New-Object Windows.Forms.OpenFileDialog
            $dlg.Title = 'Where is Battle.net.exe?'
            $dlg.Filter = 'Battle.net.exe|Battle.net.exe'
            if ($dlg.ShowDialog() -ne 'OK') { $status.Text = 'Battle.net not found - nothing installed.'; return }
            $bnet = $dlg.FileName
        }
        $u = $user.Text.Trim()
        $sec = $null
        if ($u -and $pass.Text) {
            $sec = New-Object Security.SecureString
            foreach ($c in $pass.Text.ToCharArray()) { $sec.AppendChar($c) }
            $sec.MakeReadOnly()
        } elseif ($u -or $pass.Text) {
            $status.Text = 'Enter both the login and the password - or leave both empty.'
            return
        }
        $wow = Install-Launcher $bnet $u $sec
        $pass.Text = ''
        $status.Text = 'Done: the "WoW Forever" shortcut is on the desktop.' + $(if ($sec) { ' Auto sign-in is on.' } else { ' No auto sign-in.' }) +
            $(if (-not $wow) { ' Game not found - the icon is Battle.net''s.' } else { '' })
    } catch {
        $status.Text = 'Error: ' + $_.Exception.Message
    }
})

$remove.Add_Click({
    try {
        Uninstall-Launcher
        $status.Text = 'The shortcut and its files (with the saved sign-in) are removed.'
    } catch {
        $status.Text = 'Error: ' + $_.Exception.Message
    }
})

[void]$form.ShowDialog()
