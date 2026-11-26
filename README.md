# WoW Forever Shortcut

A one-click desktop shortcut for **World of Warcraft: Forever**. It starts the game straight away,
without the Battle.net launcher window getting in the way, and can sign you back in when Battle.net
has logged you out.

Plain PowerShell scripts: you can read every line before you run it.

## Features

- **One click, game starts.** If Battle.net is closed, it starts in the tray; then Forever is
  launched right away. The launcher window does not pop up.
- **Optional auto sign-in.** When Battle.net has signed you out, the shortcut fills in your e-mail
  and presses **Continue**, then your password and presses **Log in**. If Battle.net still remembers
  your e-mail, only the password is entered. Leave the fields empty to skip this: the sign-in window
  is simply shown to you.
- **Safe fallbacks.** If the game has not started within 30 seconds (an update, an error, an
  authenticator prompt), the launcher is shown again so you can see what is going on.
- **Click again to restart** it if anything gets stuck.

## Install

1. Download the latest `WoW-Forever-Shortcut.zip` from [Releases](../../releases) and unzip it anywhere.
2. Run **`Install.vbs`**.
3. For auto sign-in, enter your Battle.net e-mail and password (optional).
4. Click **Install**. A **WoW Forever** shortcut appears on your desktop.

Windows may warn that the file came from the internet; that is normal for any downloaded script
(choose **Open** / **Run**).

After installing, the unzipped folder can be deleted. Run the installer again to change the saved
sign-in, or click **Remove** to delete the shortcut and everything it saved.

Requirements: Windows 10 or 11, Battle.net with WoW Forever installed.

## Security

- **Your password stays on your PC, encrypted** with Windows' own data protection (DPAPI). Only your
  Windows user account on that computer can decrypt it; the file is useless anywhere else.
- **It only types into the Battle.net sign-in window.** Every key is sent only while that window is
  the active one; if you click elsewhere, it stops. Your password cannot end up in a chat or another
  program.
- **Nothing is sent anywhere.** No network access of its own, no telemetry.
- **The log never contains your login or password.** It only records steps such as
  `page: password` or `password: type ok`.
- **Authenticator codes** are still entered by you.

## Is it safe for my Blizzard account?

The shortcut never touches the game: it does not read or change the game's memory, inject anything,
or modify game files. It uses Battle.net's own launch command (`Battle.net.exe --exec="launch WoWF"`)
and hides the launcher window, which is the same as pressing **Play** yourself. It is not affiliated
with or endorsed by Blizzard Entertainment; use it at your own discretion.

## How it works

| File | What it does |
| --- | --- |
| `Install.vbs` | Opens the installer window without a console. |
| `install.ps1` | Finds Battle.net and the game (for the icon), copies the files below to `%LOCALAPPDATA%\WoWForeverLaunch`, saves the optional sign-in encrypted, creates the desktop shortcut. |
| `files/WoW Forever.vbs` | What the shortcut runs: starts `launch.ps1` hidden. |
| `files/launch.ps1` | Starts Battle.net if needed, asks it to launch Forever until the game runs, hides the launcher's main window, and handles the sign-in window. |

The Battle.net sign-in page does not expose its fields to Windows accessibility, so the shortcut
recognises the page step by the position of its big blue button (and the "show password" eye icon),
then clicks the field just above it.

## Troubleshooting

What the shortcut did on its last run is written to `%LOCALAPPDATA%\WoWForeverLaunch\launch.log`.
If something does not work, open an [issue](../../issues) and attach that log (it contains no
login or password).

## Support

If this saves you some clicks every day, you can support the project on
**[Ko-fi](https://ko-fi.com/imyxjo)** ☕

[![Support me on Ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/imyxjo)

## License

[MIT](LICENSE)
