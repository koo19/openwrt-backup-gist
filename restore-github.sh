#!/bin/sh

# ==============================================================================
# OpenWrt Gist Restore Script (v3 - Encryption)
#
# Changelog:
# - v3: Added chacha20 decryption support.
# - v2: Replaced bash-specific `select` with POSIX-compliant menu.
# ==============================================================================

[ -f ~/.profile ] && . ~/.profile

# --- Configuration ---
RESTORE_DIR="/tmp/restore_from_github"
mkdir -p "$RESTORE_DIR"

# --- Environment Variable Dependencies ---
GITHUB_PAT="${GITHUB_PAT:-}"
GIST_ID="${BACKUP_GIST_ID:-}"
ENCRYPTION_PASSWORD="${ENCRYPTION_PASSWORD:-}"

# --- Script Validation ---
if [ -z "$GITHUB_PAT" ] || [ -z "$GIST_ID" ]; then
    echo "--- GitHub Configuration Required ---"
    
    # Store newly entered values
    ENTERED_PAT=""
    ENTERED_GIST_ID=""

    if [ -z "$GITHUB_PAT" ]; then
        echo "GitHub Personal Access Token (GITHUB_PAT) is missing."
        printf "Please enter your PAT: "
        stty -echo
        read -r GITHUB_PAT
        stty echo
        printf "\n"
        ENTERED_PAT=$GITHUB_PAT
    fi

    if [ -z "$GIST_ID" ]; then
        echo "Backup Gist ID (BACKUP_GIST_ID) is missing."
        printf "Please enter your Gist ID: "
        read -r GIST_ID
        ENTERED_GIST_ID=$GIST_ID
    fi

    # If new values were entered, ask to save them
    if [ -n "$ENTERED_PAT" ] || [ -n "$ENTERED_GIST_ID" ]; then
        printf "Do you want to save these settings to ~/.profile for future use? (y/n) "
        read -r answer
        if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
            echo "" >> ~/.profile
            echo "# Added by restore-github.sh on $(date)" >> ~/.profile
            [ -n "$ENTERED_PAT" ] && echo "export GITHUB_PAT=\"$ENTERED_PAT\"" >> ~/.profile
            [ -n "$ENTERED_GIST_ID" ] && echo "export BACKUP_GIST_ID=\"$ENTERED_GIST_ID\"" >> ~/.profile
            echo "Configuration saved to ~/.profile."
            echo "Please run 'source ~/.profile' or re-login for the changes to take effect."
        fi
    fi
    echo "-------------------------------------"
fi

# Final check in case user entered empty strings
if [ -z "$GITHUB_PAT" ] || [ -z "$GIST_ID" ]; then
    echo "Error: GITHUB_PAT and GIST_ID must be set to continue."
    exit 1
fi

# Check for encryption password
if [ -z "$ENCRYPTION_PASSWORD" ]; then
    echo "--- Encryption Password Required ---"
    echo "An encryption password may be required to decrypt a backup."
    printf "Please enter your encryption password (will be hidden): "
    stty -echo
    read -r ENCRYPTION_PASSWORD
    stty echo
    printf "\n"
    
    if [ -n "$ENCRYPTION_PASSWORD" ]; then
        printf "Do you want to save this password to ~/.profile for future use? (y/n) "
        read -r answer
        if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
            if ! grep -q "# Added by restore-github.sh" ~/.profile 2>/dev/null; then
                 echo "" >> ~/.profile
                 echo "# Added by restore-github.sh on $(date)" >> ~/.profile
            fi
            echo "export ENCRYPTION_PASSWORD=\"$ENCRYPTION_PASSWORD\"" >> ~/.profile
            echo "Configuration saved to ~/.profile."
            echo "Please run 'source ~/.profile' or re-login for the changes to take effect."
        fi
    fi
    echo "-------------------------------------"
fi

# Note: We don't exit if password is empty, because the user might be restoring an unencrypted backup.

# 1. Get Gist file list from GitHub
echo "Fetching backup list from GitHub Gist..."
GIST_DATA=$(curl -s -H "Authorization: token ${GITHUB_PAT}" https://api.github.com/gists/${GIST_ID})

# Check for errors
if [ -z "$GIST_DATA" ] || echo "$GIST_DATA" | jsonfilter -e '@.message' > /dev/null; then
    echo "Error: Failed to fetch Gist data."
    echo "Response: $GIST_DATA"
    exit 1
fi

# 2. Parse file list and present to user
# The `sort -r` will put the latest timestamp first.
FILES=$(echo "$GIST_DATA" | jsonfilter -e '@.files.*.filename' | sort -r)

if [ -z "$FILES" ]; then
    echo "No backup files found in the Gist."
    exit 0
fi

echo "Please select a backup to restore:"

# Create an indexed list of files
i=1
echo "$FILES" | while read -r line; do
    echo "$i) $line"
    i=$((i+1))
done

NUM_FILES=$(echo "$FILES" | wc -l)
LATEST_FILE=$(echo "$FILES" | head -n 1)

# Prompt user for input
while true; do
    echo -n "Enter a number (1-$NUM_FILES) [default: 1, for latest: $LATEST_FILE]: "
    read -r choice

    if [ -z "$choice" ]; then
        choice=1
    fi

    # Validate input
    if ! echo "$choice" | grep -qE '^[0-9]+$' || [ "$choice" -lt 1 ] || [ "$choice" -gt "$NUM_FILES" ]; then
        echo "Invalid selection. Please enter a number between 1 and $NUM_FILES."
        continue
    fi

    FILENAME=$(echo "$FILES" | sed -n "${choice}p" | tr -d '\r')
    echo "You selected: $FILENAME"
    break
done

# 3. Download and process the selected file
echo "Downloading ${FILENAME}..."
RAW_URL=$(echo "$GIST_DATA" | jsonfilter -e "@.files['${FILENAME}'].raw_url" | tr -d '\r')

if [ -z "$RAW_URL" ]; then
    echo "Error: Could not find download URL for ${FILENAME}."
    exit 1
fi

ENCODED_CONTENT=$(curl -s -L "${RAW_URL}")

if [ $? -ne 0 ] || [ -z "$ENCODED_CONTENT" ]; then
    echo "Error: Download from ${RAW_URL} failed!"
    exit 1
fi

# Process the file (decrypt if necessary)
FINAL_PATH="${RESTORE_DIR}/${FILENAME}"
if echo "$FILENAME" | grep -q '.b64.enc$'; then
    if [ -z "$ENCRYPTION_PASSWORD" ]; then
        echo "Error: The selected file is encrypted, but no encryption password was provided."
        exit 1
    fi
    FINAL_PATH="${RESTORE_DIR}/${FILENAME%.b64.enc}"
    echo "Decrypting backup to ${FINAL_PATH}..."
    echo "${ENCODED_CONTENT}" | base64 -d | openssl enc -d -chacha20 -pbkdf2 -k "${ENCRYPTION_PASSWORD}" | base64 -d > "${FINAL_PATH}"
else
    echo "Decoding backup to ${FINAL_PATH}..."
    echo "${ENCODED_CONTENT}" | base64 -d > "${FINAL_PATH}"
fi

if [ $? -ne 0 ]; then
    echo "Error: Failed to process the backup file. If encrypted, check your password."
    exit 1
fi

# 4. Restore the backup
echo "Restoring from ${FINAL_PATH}..."
echo "THIS WILL OVERWRITE YOUR CURRENT SYSTEM CONFIGURATION."
echo "You have 5 seconds to cancel (Press Ctrl+C)..."
sleep 5

sysupgrade -r "${FINAL_PATH}"

if [ $? -ne 0 ]; then
    echo "Error: System restore failed. Please check the output above."
else
    echo "Restore successful!"
fi

# 5. Cleanup
# rm -f "${FINAL_PATH}"

echo "--- Restore Process Finished ---"
