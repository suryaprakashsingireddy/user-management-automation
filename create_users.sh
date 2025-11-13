#!/usr/bin/env bash
# create_users.sh
# Purpose: Batch-create or update local Linux users from a simple input file.
# - Input format: username; group1,group2
# - Skips lines starting with #
# - Ignores whitespace
# - Creates missing groups
# - Creates home directory /home/username if missing
# - Sets ownership and permissions
# - Generates random 12-character passwords for NEW users and saves them in /var/secure/user_passwords.txt (mode 600)
# - Logs all actions to /var/log/user_management.log (mode 600)
#
# Run as root: sudo bash create_users.sh users.txt

set -o pipefail
# Don't set -e so script continues to process multiple users even if one fails

INPUT_FILE="${1:-users.txt}"
LOG_FILE="/var/log/user_management.log"
SECURE_DIR="/var/secure"
PW_FILE="$SECURE_DIR/user_passwords.txt"

# Timestamp helper
ts() { date +"%Y-%m-%d %H:%M:%S"; }

# Logging function (writes to log file and echoes to stdout)
log() {
  local level="$1"; shift
  local msg="$*"
  printf "%s [%s] %s\n" "$(ts)" "$level" "$msg" | tee -a "$LOG_FILE"
}

# Ensure running as root
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root. Use sudo." >&2
  exit 1
fi

# Create/prepare log and secure dir with strict permissions
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE" 2>/dev/null || { echo "ERROR: Cannot create $LOG_FILE"; exit 1; }
chmod 600 "$LOG_FILE" 2>/dev/null || log WARNING "Could not chmod $LOG_FILE"

mkdir -p "$SECURE_DIR"
touch "$PW_FILE" 2>/dev/null || true
chmod 600 "$PW_FILE" 2>/dev/null || log WARNING "Could not chmod $PW_FILE"

# Validate input file
if [[ ! -r "$INPUT_FILE" ]]; then
  log ERROR "Input file '$INPUT_FILE' not found or not readable."
  exit 1
fi

# Secure character set for password generation
generate_password() {
  # Use tr on /dev/urandom to produce a 12-char string containing letters, digits and selected symbols
  tr -dc 'A-Za-z0-9@%+=:,?._-' < /dev/urandom | head -c 12 || head -c 12 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 12
}

# Process file line by line
while IFS= read -r rawline || [[ -n "$rawline" ]]; do
  # Trim leading/trailing whitespace
  line="$(echo "$rawline" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

  # Skip blank lines
  [[ -z "$line" ]] && continue

  # Skip comments beginning with #
  [[ "${line:0:1}" == "#" ]] && { log INFO "Skipping comment: $line"; continue; }

  # Split username and groups by first ';'
  IFS=';' read -r user groups_str <<< "$line"
  user="$(echo "$user" | xargs)"                # trim whitespace

  if [[ -z "$user" ]]; then
    log ERROR "Malformed line (missing username): $line"
    continue
  fi

  # Normalize groups string (remove spaces) and create array
  groups_str="$(echo "${groups_str:-}" | tr -d '[:space:]')"
  IFS=',' read -r -a groups_arr <<< "$groups_str"

  log INFO "Processing user: $user"

  # If user exists: only ensure groups and home dir/permissions; DO NOT reset password
  if id "$user" &>/dev/null; then
    log INFO "User '$user' exists. Ensuring groups and home directory."

    # Ensure groups exist and add user to them
    extra_groups=()
    for g in "${groups_arr[@]}"; do
      [[ -z "$g" ]] && continue
      if ! getent group "$g" >/dev/null; then
        if groupadd "$g"; then
          log INFO "Created missing group: $g"
        else
          log ERROR "Failed to create group: $g"
          continue
        fi
      fi
      extra_groups+=("$g")
    done

    if (( ${#extra_groups[@]} )); then
      IFS=','; extra_csv="${extra_groups[*]}"; unset IFS
      if usermod -aG "$extra_csv" "$user"; then
        log INFO "Added $user to groups: $extra_csv"
      else
        log ERROR "Failed to add $user to groups: $extra_csv"
      fi
    fi

    # Ensure home directory exists and set permissions
    HOME_DIR="/home/$user"
    if [[ ! -d "$HOME_DIR" ]]; then
      if mkdir -p "$HOME_DIR"; then
        log INFO "Created missing home directory: $HOME_DIR"
      else
        log ERROR "Failed to create home directory: $HOME_DIR"
      fi
    fi
    chown -R "$user":"$user" "$HOME_DIR" 2>/dev/null || chown -R "$user":"$(id -gn $user)" "$HOME_DIR" 2>/dev/null || log ERROR "chown failed for $HOME_DIR"
    chmod 700 "$HOME_DIR" 2>/dev/null || log ERROR "chmod failed for $HOME_DIR"

    log INFO "Skipping password change for existing user '$user'."
    continue
  fi

  # For new user: ensure groups exist, then create user with -m to create home
  secondary_groups=()
  for g in "${groups_arr[@]}"; do
    [[ -z "$g" ]] && continue
    if ! getent group "$g" >/dev/null; then
      if groupadd "$g"; then
        log INFO "Created missing group: $g"
      else
        log ERROR "Failed to create group: $g"
        continue
      fi
    fi
    secondary_groups+=("$g")
  done

  secondary_csv=""
  if (( ${#secondary_groups[@]} )); then
    IFS=','; secondary_csv="${secondary_groups[*]}"; unset IFS
  fi

  # Create user
  if [[ -n "$secondary_csv" ]]; then
    if useradd -m -s /bin/bash -G "$secondary_csv" "$user"; then
      log INFO "Created user '$user' with groups: $secondary_csv"
    else
      log ERROR "Failed to create user '$user'"
      continue
    fi
  else
    if useradd -m -s /bin/bash "$user"; then
      log INFO "Created user '$user' (no extra groups)"
    else
      log ERROR "Failed to create user '$user'"
      continue
    fi
  fi

  # Ensure home exists and set ownership/permissions
  HOME_DIR="/home/$user"
  if [[ -d "$HOME_DIR" ]]; then
    chown -R "$user":"$user" "$HOME_DIR" 2>/dev/null || chown -R "$user":"$(id -gn $user)" "$HOME_DIR" 2>/dev/null || log ERROR "chown failed for $HOME_DIR"
    chmod 700 "$HOME_DIR" 2>/dev/null || log ERROR "chmod failed for $HOME_DIR"
  else
    log WARNING "Home directory $HOME_DIR missing after useradd"
  fi

  # Generate random password and set it
  password="$(generate_password)"
  if echo "$user:$password" | chpasswd; then
    log INFO "Password set for new user '$user'"
  else
    log ERROR "Failed to set password for user '$user'"
  fi

  # Append credentials to secure file
  if printf "%s:%s\n" "$user" "$password" >> "$PW_FILE"; then
    chmod 600 "$PW_FILE" 2>/dev/null || true
    log INFO "Saved credentials for $user to $PW_FILE"
  else
    log ERROR "Failed to write credentials for $user to $PW_FILE"
  fi

done < "$INPUT_FILE"

log INFO "Processing complete for '$INPUT_FILE'"
exit 0
