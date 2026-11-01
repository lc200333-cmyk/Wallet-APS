# Wallet APS

Wallet APS is a local, offline password and private data manager for
Windows, Android, and Linux. It works with password-protected `.swl` vaults
and is compatible with SPB Wallet data, so your vault remains a file that you
control.

Project repository: [Wallet-APS](https://github.com/lc200333-cmyk/Wallet-APS).

## Download

The latest builds are available from GitHub Releases:

- [Windows setup.exe](../../releases/latest/download/Wallet-APS-Setup.exe)
- [Android APK](../../releases/latest/download/Wallet-APS-android.apk)
- [Linux deb amd64](../../releases/latest/download/Wallet-APS-linux-amd64.deb)

If a direct link does not work, open the [latest release](../../releases/latest).

## Features

- Create new password-protected `.swl` vaults or open existing SPB Wallet
  databases.
- Organize passwords, notes, payment details, and other private information in
  folders and cards.
- Use built-in card templates or create custom templates with your own fields
  and icons.
- Keep secret fields hidden until you reveal or copy them.
- Add notes and file attachments to cards.
- Search, filter, and sort cards and templates.
- Import and export cards and templates for moving selected data between
  vaults.
- Undo changes and restore deleted items from the session trash before closing
  the application.
- Create archive copies of important vaults before major changes.
- Use an interface adapted for desktop and mobile screens.

Wallet APS does not require an account or a cloud service. Your primary
vault stays on your device and can be used without an internet connection.

## Quick Start

1. Download the package for your platform:
   - On Windows, run `Wallet-APS-Setup.exe` and follow the installer.
   - On Android, install `Wallet-APS-android.apk`. Your device may ask you
     to allow installation from your browser or file manager.
   - On Debian or Ubuntu, install the downloaded package with:

     ```bash
     sudo apt install ./Wallet-APS-linux-amd64.deb
     ```

2. Start Wallet APS.
3. To create a vault, select **+**, choose its location and name, then enter and
   confirm a new password. To use an existing vault, select the folder button,
   choose a `.swl` file, and enter its password.
4. Select or create a folder, add a card, choose a template, and fill in the
   required fields.
5. Save the vault after making changes. You can also use the safe-close button,
   which saves pending changes before closing.
6. Create an archive copy and store it separately from the working vault.

## Important

The vault password is not stored by the application and cannot be recovered if
you forget it. Use a strong, unique password and keep it in a safe place.

Always keep a separate backup of important `.swl` files, especially before
imports, bulk edits, or deletions.
