# OpenWrt Gist Backup

A set of shell scripts to securely back up and restore your OpenWrt configuration to a private GitHub Gist, with encryption.

## Features

- **Encrypted Backups:** Uses `chacha20` to encrypt your configuration before uploading.
- **Private Gist:** Backups are stored in a private GitHub Gist.
- **Easy Configuration:** Prompts for necessary credentials and can save them to your `~/.profile`.
- **Simple Restore:** Provides a menu to choose which backup to restore.

## Requirements

- `curl`: For making API requests to GitHub.
- `openssl`: For encryption and decryption.
- `jsonfilter`: For parsing JSON responses from the GitHub API. You can install it with `opkg install jsonfilter`.
- A GitHub Personal Access Token (PAT) with the `gist` scope.
- A private GitHub Gist to store your backups.

## Setup

1.  **Create a GitHub Personal Access Token (PAT):**
    - Go to your GitHub [Developer settings](https://github.com/settings/tokens).
    - Click "Generate new token".
    - Give it a name (e.g., "OpenWrt Backup").
    - Select the `gist` scope.
    - Click "Generate token" and copy the token.

2.  **Create a private GitHub Gist:**
    - Go to [gist.github.com](https://gist.github.com).
    - Create a new gist with a filename like `openwrt-backup-placeholder.txt` and some content.
    - **Important:** Create it as a "secret gist".
    - After creating the gist, copy the ID from the URL (the long string of characters after your username).

3.  **Configure the scripts:**
    The first time you run `backup-github.sh` or `restore-github.sh`, it will prompt you for:
    - Your GitHub PAT (`GITHUB_PAT`)
    - Your Gist ID (`BACKUP_GIST_ID`)
    - An encryption password (`ENCRYPTION_PASSWORD`)

    The script will offer to save these to your `~/.profile` for future use.

## Usage

### Backup

To back up your current OpenWrt configuration:

```sh
./backup-github.sh
```

### Restore

To restore a previous configuration:

```sh
./restore-github.sh
```

The script will fetch the list of backups from your Gist and present you with a menu to choose which one to restore.

## Security Note

Storing secrets like your GitHub PAT and encryption password in `~/.profile` is convenient but not the most secure method. Anyone with access to your router's shell will be able to read them. For a more secure setup, consider using a secrets management tool or entering the credentials manually each time.

## License

[Apache License 2.0](LICENSE)
