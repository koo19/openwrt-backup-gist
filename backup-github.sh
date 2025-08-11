#!/bin/sh

# ==============================================================================
# OpenWrt Gist Backup Script (v8 - Encryption)
#
# Changelog:
# - v8: Added chacha20 encryption for the backup file. (Reverted from ChaCha20-Poly1305 due to compatibility issues).
# - v7: Switched to a here-document for JSON generation as a final attempt.
# ==============================================================================

[ -f ~/.profile ] && . ~/.profile

# --- Configuration ---
BACKUP_DIR="/tmp/backup_to_github"
BACKUP_FILENAME="openwrt_config_$(date +%Y%m%d_%H%M%S 2>/dev/null | sed 's/://g').tar.gz"
[ -z "$(echo "$BACKUP_FILENAME" | grep '_')" ] && BACKUP_FILENAME="openwrt_config_$(date +%Y%m%d)_$(date +%H%M%S 2>/dev/null | sed 's/://g').tar.gz"

# Simplified description to avoid issues with command substitution in some shells
GIST_DESCRIPTION="OpenWrt Config Backup (Encrypted)"
GIST_PUBLIC="false"

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
            echo "# Added by backup-github.sh on $(date)" >> ~/.profile
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
    echo "An encryption password is required to protect your backup."
    printf "Please enter your encryption password (will be hidden): "
    stty -echo
    read -r ENCRYPTION_PASSWORD
    stty echo
    printf "\n"
    
    if [ -n "$ENCRYPTION_PASSWORD" ]; then
        printf "Do you want to save this password to ~/.profile for future use? (y/n) "
        read -r answer
        if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
            # Check if the header was already added by PAT/GIST ID block
            if ! grep -q "# Added by backup-github.sh" ~/.profile 2>/dev/null; then
                 echo "" >> ~/.profile
                 echo "# Added by backup-github.sh on $(date)" >> ~/.profile
            fi
            echo "export ENCRYPTION_PASSWORD=\"$ENCRYPTION_PASSWORD\"" >> ~/.profile
            echo "Configuration saved to ~/.profile."
            echo "Please run 'source ~/.profile' or re-login for the changes to take effect."
        fi
    fi
    echo "-------------------------------------"
fi

# Final check for password
if [ -z "$ENCRYPTION_PASSWORD" ]; then
    echo "Error: ENCRYPTION_PASSWORD must be set to continue."
    exit 1
fi

# --- Main Script Logic ---
echo "--- OpenWrt Configuration Backup Started ---"

# 1. Create Backup
echo "Creating backup to ${BACKUP_DIR}/${BACKUP_FILENAME}..."
mkdir -p "$BACKUP_DIR"
sysupgrade -b "${BACKUP_DIR}/${BACKUP_FILENAME}"
if [ $? -ne 0 ]; then
    echo "Error: OpenWrt backup creation failed!"
    exit 1
fi

# 2. Encrypt and Prepare Gist Payload
echo "Encrypting and preparing Gist payload..."
JSON_TEMP_FILE="${BACKUP_DIR}/gist_payload.json"

# Per user request, the backup file is base64 encoded, then encrypted with chacha20,
# and the result is base64 encoded again for safe transport in JSON.
# The reverse process is: base64 decode -> decrypt -> base64 decode.
ENCRYPTED_CONTENT=$(base64 -w 0 < "${BACKUP_DIR}/${BACKUP_FILENAME}" | openssl enc -e -chacha20 -salt -pbkdf2 -k "${ENCRYPTION_PASSWORD}" | base64 -w 0)

if [ $? -ne 0 ] || [ -z "$ENCRYPTED_CONTENT" ]; then
    echo "Error: Encryption failed!"
    exit 1
fi

cat << EOF > "${JSON_TEMP_FILE}"
{
  "description": "${GIST_DESCRIPTION}",
  "public": ${GIST_PUBLIC},
  "files": {
    "${BACKUP_FILENAME}.b64.enc": {
      "content": "${ENCRYPTED_CONTENT}"
    }
  }
}
EOF

# 3. Push to GitHub Gist using PATCH to update the existing Gist
echo "Pushing backup to GitHub Gist..."
RESPONSE=$(curl -s -X PATCH \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token ${GITHUB_PAT}" \
  -H "Content-Type: application/json" \
  --data-binary "@${JSON_TEMP_FILE}" \
  https://api.github.com/gists/${GIST_ID})

GIST_URL=$(echo "$RESPONSE" | jsonfilter -e '@.html_url')

if [ -z "$GIST_URL" ]; then
    echo "Error: Gist upload may have failed."
    echo "Full Response: ${RESPONSE}"
else
    echo "Backup successfully pushed!"
    echo "Gist URL: ${GIST_URL}"
fi

# 4. Cleanup
#rm -f "${BACKUP_DIR}/${BACKUP_FILENAME}"
#rm -f "${JSON_TEMP_FILE}"

echo "--- Backup Process Finished ---"
