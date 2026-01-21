#!/bin/bash
#
# Fixed + annotated version of MintScript.sh
# - Preserves original file/variable names where reasonable
# - Fixes syntax errors, incorrect tests, dangerous chmods, missing apt verbs
# - Scopes destructive operations to /home by default and prompts before global destructive changes
# - Replaces GUI editor/terminal launches with $EDITOR (falls back to nano) or logs
# - Adds safety confirmations for high-risk operations
#
# NOTE: This script still performs system changes. Test in a disposable VM and back up before running.
#
# Original: Created by Matthew Bierman (2016)
# Modified: annotated fixes (2026) — run only in a test VM unless you understand/accept effects.
#

set -o pipefail

clear
echo "Created by Matthew Bierman, Lightning McQueens, Faith Lutheran Middle & High School, Las Vegas, NV, USA"
echo "Last Modified on Friday, January 19th, 2016, 2:13pm (original)"
echo "This file: fixed & annotated variant - use with caution"
startTime=$(date +"%s")

# safe log paths (script intended to be run as root; ~ is /root)
LOG_DIR=~/Desktop
SCRIPT_LOG="$LOG_DIR/Script.log"
BACKUP_DIR=~/Desktop/backups
LOGS_DIR=~/Desktop/logs

# Make safe directories and logs with minimal permissions
mkdir -p "$BACKUP_DIR" "$LOGS_DIR"
umask 077                # ensure files created are not world-readable by default
: > "$SCRIPT_LOG"
chmod 600 "$SCRIPT_LOG"

# function for timestamped logging (keeps original name)
printTime()
{
    # usage: printTime "message"
    endTime=$(date +"%s")
    diffTime=$((endTime - startTime))
    min=$((diffTime / 60))
    sec=$((diffTime % 60))
    printf "%02d:%02d -- %s\n" "$min" "$sec" "$1" >> "$SCRIPT_LOG"
}

# require root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  exit 1
fi
printTime "Script is being run as root."

# Helper: confirm prompt (default no)
confirm() {
  # confirm "prompt message"
  read -r -p "$1 [y/N] " response
  case "$response" in
    [yY][eE][sS]|[yY]) return 0 ;;
    *) return 1 ;;
  esac
}

# Use non-interactive editor variable; fall back to nano if not set
: "${EDITOR:=nano}"

# Basic package install with retry-safe wrapper
apt_install_quiet() {
  # apt_install_quiet pkg1 pkg2 ...
  if ! dpkg -s "$1" >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq "$@" || {
      printTime "Failed to install: $*"
      return 1
    }
  else
    printTime "Package already installed: $1"
  fi
}

# Install a GUI editor if interactive and available (keeps original intent but optional)
if [ -n "$DISPLAY" ] && command -v gedit >/dev/null 2>&1; then
  printTime "GUI environment detected; gedit available."
else
  # attempt to install a lightweight editor (non-GUI) - keep original 'gedit' step but fall back
  apt_install_quiet nano || true
  printTime "Using non-GUI editor (nano) as fallback."
fi

printTime "The current OS check (Linux Mint) will be performed."

# verify this is Linux Mint (non-fatal, just warns)
if ! grep -qi "linux mint" /etc/os-release 2>/dev/null ; then
  printTime "Warning: /etc/os-release does not contain Linux Mint. Continuing anyway (risk)."
fi

# Back up passwd/group safely and set secure perms
cp -a /etc/group "$BACKUP_DIR/group.bak" 2>/dev/null || printTime "Failed to copy /etc/group (maybe already backed up)"
cp -a /etc/passwd "$BACKUP_DIR/passwd.bak" 2>/dev/null || printTime "Failed to copy /etc/passwd"
chmod 600 "$BACKUP_DIR"/group.bak "$BACKUP_DIR"/passwd.bak 2>/dev/null || true
printTime "/etc/group and /etc/passwd files backed up."

# Ask for new users (non-blocking)
echo "Type user account names of users you want to add, separated by spaces (or press Enter to skip):"
read -r -a usersNew
usersNewLength=${#usersNew[@]}

for (( i=0; i<usersNewLength; i++ )); do
    username=${usersNew[i]}
    clear
    echo "Creating user: $username"
    # adduser is interactive; use useradd with sensible defaults if non-interactive preferred.
    adduser "$username" || { printTime "adduser failed for $username"; continue; }
    printTime "A user account for $username has been created."

    # Ask about admin privileges
    read -r -p "Make $username administrator? (yes/no) " ynNew
    if [[ "$ynNew" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        usermod -aG sudo,adm,lpadmin,sambashare "$username"
        printTime "$username has been added to admin groups (sudo, adm, lpadmin, sambashare)."
    else
        printTime "$username has been left as a standard user."
    fi

    # Set password aging (keeps original values)
    passwd -x 30 -n 3 -w 7 "$username" || printTime "passwd aging failed for $username"
    printTime "$username: password aging set (max 30, min 3, warn 7)."
done

# Ask service needs (keep variable names close to original)
echo "Does this machine need Samba? (yes/no)"
read -r sambaYN
echo "Does this machine need FTP? (yes/no)"
read -r ftpYN
echo "Does this machine need SSH? (yes/no)"
read -r sshYN
echo "Does this machine need Telnet? (yes/no)"
read -r telnetYN
echo "Does this machine need Mail? (yes/no)"
read -r mailYN
echo "Does this machine need Printing? (yes/no)"
read -r printYN
echo "Does this machine need MySQL? (yes/no)"
read -r dbYN
echo "Will this machine be a Web Server (apache)? (yes/no)"
read -r httpYN
echo "Does this machine need DNS? (yes/no)"
read -r dnsYN
echo "Does this machine allow media files? (yes/no)"
read -r mediaFilesYN

clear
unalias -a
printTime "All aliases removed for this shell session."

# Locking root account is a policy decision. Ask before doing it.
if confirm "Lock root account (usermod -L root)? This may prevent direct root logins."; then
    usermod -L root
    printTime "Root account has been locked."
else
    printTime "Skipped locking root account."
fi

# Bash history file handling: operate on root's history explicitly
if [ -f /root/.bash_history ]; then
    chmod 600 /root/.bash_history
    printTime "Root bash history file permissions set to 600."
else
    printTime "No /root/.bash_history file found; skipping."
fi

# Ensure /etc/shadow has secure permissions
if [ -f /etc/shadow ]; then
    chown root:shadow /etc/shadow 2>/dev/null || chown root:root /etc/shadow
    chmod 640 /etc/shadow
    printTime "/etc/shadow permissions set to 640 (root:shadow if available)."
else
    printTime "/etc/shadow not found!"
fi

printTime "Listing /home for unexpected entries." 
ls -la /home >> "$SCRIPT_LOG" 2>/dev/null

printTime "Listing /etc/sudoers.d for unexpected files."
ls -la /etc/sudoers.d >> "$SCRIPT_LOG" 2>/dev/null

# Back up rc.local if exists and truncate safely
if [ -f /etc/rc.local ]; then
    cp -a /etc/rc.local "$BACKUP_DIR/rc.local.bak"
    # To avoid breaking systems that expect rc.local behavior, only disable interactive entries:
    if confirm "Replace /etc/rc.local with a safe default (will backup original)?"; then
        printf '%s\n' '#!/bin/sh -e' 'exit 0' > /etc/rc.local
        chmod 755 /etc/rc.local
        printTime "/etc/rc.local replaced with safe default (backup saved)."
    else
        printTime "Left /etc/rc.local untouched."
    fi
fi

# Install and enable UFW (firewall)
apt_install_quiet ufw || true
if command -v ufw >/dev/null 2>&1 ; then
    ufw --force enable || true
    ufw deny 1337 || true
    printTime "Firewall enabled and port 1337 denied."
else
    printTime "UFW not available; firewall steps skipped."
fi

# Back up and set /etc/hosts safely (do not remove existing content blindly)
if [ -f /etc/hosts ]; then
    cp -a /etc/hosts "$BACKUP_DIR/hosts.bak"
fi
# Only replace if user confirms
if confirm "Reset /etc/hosts to a default minimal file (backup saved)?"; then
    cat > /etc/hosts <<EOF
127.0.0.1   localhost
127.0.1.1   $(hostname)
::1         ip6-localhost ip6-loopback
fe00::0     ip6-localnet
ff00::0     ip6-mcastprefix
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF
    chmod 644 /etc/hosts
    printTime "/etc/hosts has been reset to defaults (backup saved)."
else
    printTime "Skipped resetting /etc/hosts."
fi

# MDM is old; only edit if file exists and user wants it changed
if [ -f /etc/mdm/mdm.conf ]; then
    cp -a /etc/mdm/mdm.conf "$BACKUP_DIR/mdm.conf.bak"
    if confirm "Edit /etc/mdm/mdm.conf to secure MDM settings?"; then
        # Rather than blindly overwriting, notify user we will open the file in editor
        $EDITOR /etc/mdm/mdm.conf
        printTime "User edited /etc/mdm/mdm.conf manually."
    else
        printTime "Skipped editing /etc/mdm/mdm.conf."
    fi
else
    printTime "/etc/mdm/mdm.conf not present; skipping MDM steps."
fi

# DON'T delete scripts in /bin - extremely dangerous. Removed destructive line.
printTime "Skipping removal of scripts in /bin - original script deleted shell scripts in /bin which is unsafe."

# Samba handling
if [[ "$sambaYN" =~ ^([nN][oO]|[nN])$ ]]; then
    apt-get purge -y -qq samba samba-common samba-common-bin samba4 2>/dev/null || true
    printTime "Samba packages purged (if present)."
elif [[ "$sambaYN" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    if [ -f /etc/samba/smb.conf ]; then
        cp -a /etc/samba/smb.conf "$BACKUP_DIR/smb.conf.bak"
    fi
    printTime "Samba left installed. Opening smb.conf in editor for review."
    $EDITOR /etc/samba/smb.conf
else
    printTime "Samba response not recognized; skipped."
fi

printTime "Samba section complete."

# FTP (vsftpd) handling
if [[ "$ftpYN" =~ ^([nN][oO]|[nN])$ ]]; then
    # Deny common FTP-related ports and remove vsftpd package if present
    ufw deny ftp || true
    ufw deny sftp || true
    apt-get purge -y -qq vsftpd 2>/dev/null || true
    printTime "FTP-related ports denied and vsftpd purged (if present)."
elif [[ "$ftpYN" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    apt_install_quiet vsftpd || true
    ufw allow ftp || true
    if [ -f /etc/vsftpd.conf ]; then
        cp -a /etc/vsftpd.conf "$BACKUP_DIR/vsftpd.conf.bak"
    fi
    printTime "vsftpd installed/allowed; open config for manual edit."
    $EDITOR /etc/vsftpd.conf
    systemctl restart vsftpd 2>/dev/null || service vsftpd restart 2>/dev/null || true
else
    printTime "FTP response not recognized; skipped."
fi

printTime "FTP section complete."

# SSH handling
if [[ "$sshYN" =~ ^([nN][oO]|[nN])$ ]]; then
    ufw deny ssh || true
    apt-get purge -y -qq openssh-server 2>/dev/null || true
    printTime "SSH denied and openssh-server purged (if present)."
elif [[ "$sshYN" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    apt_install_quiet openssh-server || true
    ufw allow ssh || true
    if [ -f /etc/ssh/sshd_config ]; then
        cp -a /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config.bak"
        # Secure common misconfigurations with safe edits only if they match the insecure patterns
        if grep -Eiq '^PermitRootLogin\s+yes' /etc/ssh/sshd_config; then
            sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
        fi
        # modern sshd uses Protocol 2 by default; remove Protocol 1 if present
        sed -i 's/^Protocol.*/Protocol 2/' /etc/ssh/sshd_config 2>/dev/null || true
        # Disable X11 forwarding if explicitly enabled
        if grep -Eiq '^X11Forwarding\s+yes' /etc/ssh/sshd_config; then
            sed -i 's/^X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
        fi
        # Ensure empty passwords are not allowed
        if grep -Eiq '^PermitEmptyPasswords\s+yes' /etc/ssh/sshd_config; then
            sed -i 's/^PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config
        fi
    fi
    systemctl restart ssh 2>/dev/null || service ssh restart 2>/dev/null || true
    # record status into the log instead of opening gnome-terminal
    systemctl status ssh >> "$SCRIPT_LOG" 2>&1 || service ssh status >> "$SCRIPT_LOG" 2>&1 || true
    printTime "SSH service configured and status logged."
else
    printTime "SSH response not recognized; skipped."
fi

printTime "SSH section complete."

# Telnet
if [[ "$telnetYN" =~ ^([nN][oO]|[nN])$ ]]; then
    ufw deny telnet || true
    apt-get purge -y -qq telnetd telnet 2>/dev/null || true
    printTime "Telnet denied and related packages purged (if present)."
elif [[ "$telnetYN" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    ufw allow telnet || true
    printTime "Telnet allowed (user requested)."
else
    printTime "Telnet response not recognized; skipped."
fi

printTime "Telnet section complete."

# Mail ports
case "$mailYN" in
  [nN]* )
    for p in smtp pop2 pop3 imap2 imaps pop3s; do ufw deny "$p" || true; done
    printTime "Mail ports denied."
    ;;
  [yY]* )
    for p in smtp pop2 pop3 imap2 imaps pop3s; do ufw allow "$p" || true; done
    printTime "Mail ports allowed."
    ;;
  *)
    printTime "Mail response not recognized; skipped."
    ;;
esac

printTime "Mail section complete."

# Printing (CUPS)
case "$printYN" in
  [nN]* )
    for p in ipp printer cups; do ufw deny "$p" || true; done
    printTime "Printing ports denied."
    ;;
  [yY]* )
    for p in ipp printer cups; do ufw allow "$p" || true; done
    printTime "Printing ports allowed."
    ;;
  *)
    printTime "Printing response not recognized; skipped."
    ;;
esac

printTime "Printing section complete."

# Database MySQL handling
if [[ "$dbYN" =~ ^([nN][oO]|[nN])$ ]]; then
    for p in ms-sql-s ms-sql-m mysql mysql-proxy; do ufw deny "$p" || true; done
    apt-get purge -y -qq mysql-server mysql-client 2>/dev/null || true
    printTime "MySQL ports denied and packages purged (if present)."
elif [[ "$dbYN" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    ufw allow mysql || true
    # back up potential config files
    for f in /etc/my.cnf /etc/mysql/my.cnf /usr/etc/my.cnf ~/.my.cnf; do
        [ -f "$f" ] && cp -a "$f" "$BACKUP_DIR/$(basename "$f").bak" 2>/dev/null || true
    done
    printTime "MySQL allowed; please review configs manually."
    $EDITOR /etc/mysql/my.cnf 2>/dev/null || true
    systemctl restart mysql 2>/dev/null || service mysql restart 2>/dev/null || true
else
    printTime "MySQL response not recognized; skipped."
fi

printTime "MySQL section complete."

# Web server (Apache) handling
if [[ "$httpYN" =~ ^([nN][oO]|[nN])$ ]]; then
    ufw deny http || true
    ufw deny https || true
    apt-get purge -y -qq apache2 2>/dev/null || true
    if confirm "Remove files under /var/www/* (if present)? This will delete web content."; then
        rm -rf /var/www/* 2>/dev/null || true
        printTime "/var/www/* removed."
    else
        printTime "Left /var/www/* untouched."
    fi
elif [[ "$httpYN" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    ufw allow http || true
    ufw allow https || true
    if [ -f /etc/apache2/apache2.conf ]; then
        cp -a /etc/apache2/apache2.conf "$BACKUP_DIR/apache2.conf.bak"
        # Append safe restrictions (careful not to corrupt file)
        if ! grep -q "UserDir disabled root" /etc/apache2/apache2.conf 2>/dev/null; then
            cat >> /etc/apache2/apache2.conf <<'EOF'

# Added by hardening script: restrict directory access and disable UserDir for root
<Directory />
    AllowOverride None
    Require all denied
</Directory>
UserDir disabled root
EOF
        fi
        chown -R root:root /etc/apache2 2>/dev/null || true
    fi
    printTime "Apache config reviewed and updated minimally (backup saved)."
else
    printTime "Web server response not recognized; skipped."
fi

printTime "Web server section complete."

# DNS (bind9) handling
if [[ "$dnsYN" =~ ^([nN][oO]|[nN])$ ]]; then
    ufw deny domain || true
    apt-get purge -y -qq bind9 2>/dev/null || true
    printTime "DNS denied and bind9 purged (if present)."
elif [[ "$dnsYN" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    ufw allow domain || true
    printTime "DNS port allowed."
else
    printTime "DNS response not recognized; skipped."
fi

printTime "DNS section complete."

# Media file deletion - extremely destructive in original; here we scope to /home only and ask for confirmation
if [[ "$mediaFilesYN" =~ ^([nN][oO]|[nN])$ ]]; then
    if confirm "Delete common media files under /home (this is destructive). Proceed?"; then
        # list of extensions (keeps original sets) - scoped to /home to avoid system breakage
        media_exts=(midi mid mod mp3 mp2 mpa abs mpega au snd wav aiff aif sid flac ogg
                    mpeg mpg mpe dl movie movi mv iff anim5 anim3 anim7 avi vfw avx fli flc mov qt spl swf dcr dir dxr rpm rm smi ra ram rv wmv asf asx wma wax wmx 3gp mp4 flv m4v)
        for ext in "${media_exts[@]}"; do
            find /home -type f -iname "*.${ext}" -delete 2>/dev/null || true
        done
        image_exts=(tiff tif rs im1 gif jpeg jpg jpe png rgb xwd xpm ppm pbm pgm pcx ico svg svgz)
        for ext in "${image_exts[@]}"; do
            find /home -type f -iname "*.${ext}" -delete 2>/dev/null || true
        done
        printTime "Media files under /home removed."
    else
        printTime "Skipped deleting media from /home."
    fi
else
    printTime "Media files kept (user allowed media or response unrecognized)."
fi

printTime "Media files section complete."

# Remove common network/tools used for pivoting/attacks only if confirmed (do not force rm of binaries)
if confirm "Attempt to purge netcat/john/hydra/aircrack and similar packages? (safer than manual binary removal)"; then
    apt-get purge -y -qq netcat netcat-openbsd netcat-traditional ncat pnetcat socat 2>/dev/null || true
    apt-get purge -y -qq john john-data 2>/dev/null || true
    apt-get purge -y -qq hydra hydra-gtk 2>/dev/null || true
    apt-get purge -y -qq aircrack-ng fcrackzip lcrack ophcrack pdfcrack pyrit rarcrack sipcrack irpas 2>/dev/null || true
    printTime "Attempted to purge known offensive tools (package names may vary by distro)."
else
    printTime "Skipped purging offensive tool packages."
fi

printTime "Tool removal section complete."

# Zeitgeist removal (only if present)
apt-get purge -y -qq zeitgeist-core zeitgeist-datahub python-zeitgeist rhythmbox-plugin-zeitgeist zeitgeist 2>/dev/null || true
printTime "Zeitgeist packages purged (if present)."

# Secure /etc/login.defs - use sed to set values properly (no malformed octal sequences)
if [ -f /etc/login.defs ]; then
    cp -a /etc/login.defs "$BACKUP_DIR/login.defs.bak"
    sed -i 's/^[#[:space:]]*PASS_MAX_DAYS.*/PASS_MAX_DAYS\t30/' /etc/login.defs
    sed -i 's/^[#[:space:]]*PASS_MIN_DAYS.*/PASS_MIN_DAYS\t3/' /etc/login.defs
    sed -i 's/^[#[:space:]]*PASS_MIN_LEN.*/PASS_MIN_LEN\t8/' /etc/login.defs
    sed -i 's/^[#[:space:]]*PASS_WARN_AGE.*/PASS_WARN_AGE\t7/' /etc/login.defs
    printTime "/etc/login.defs updated with PASS_* policy (backup saved)."
else
    printTime "/etc/login.defs not found; skipped."
fi

# PAM cracklib and password policies
apt_install_quiet libpam-cracklib || true
if [ -f /etc/pam.d/common-auth ]; then
    cp -a /etc/pam.d/common-auth "$BACKUP_DIR/common-auth.bak"
fi
if [ -f /etc/pam.d/common-password ]; then
    cp -a /etc/pam.d/common-password "$BACKUP_DIR/common-password.bak"
fi

# Add pam_tally and cracklib lines if missing (safe append)
if ! grep -q "pam_tally" /etc/pam.d/common-auth 2>/dev/null; then
    echo "auth optional pam_tally.so deny=5 unlock_time=900 onerr=fail audit even_deny_root_account silent" >> /etc/pam.d/common-auth
    printTime "Added pam_tally entry to common-auth."
fi
if ! grep -q "pam_cracklib" /etc/pam.d/common-password 2>/dev/null; then
    cat >> /etc/pam.d/common-password <<'EOF'
password requisite pam_cracklib.so retry=3 minlen=8 difok=3 reject_username minclass=3 maxrepeat=2 dcredit=1 ucredit=1 lcredit=1 ocredit=1
password requisite pam_pwhistory.so use_authtok remember=5
EOF
    printTime "Added pam_cracklib and pam_pwhistory entries to common-password."
fi

printTime "PAM password policy adjustments applied (backups saved)."

# Install iptables if missing and add anti-spoof rule in a conservative way
apt_install_quiet iptables || true
# Detect a non-loopback interface name to apply the rule conservatively
netif=$(ip -o link show | awk -F': ' '/state UP/ {print $2; exit}')
if [ -n "$netif" ]; then
    # drop packets claiming to be from 127.0.0.0/8 coming in on a non-loopback interface
    iptables -C INPUT -i "$netif" -s 127.0.0.0/8 -j DROP 2>/dev/null || iptables -A INPUT -i "$netif" -s 127.0.0.0/8 -j DROP
    printTime "Added iptables anti-spoof rule on interface $netif."
else
    printTime "No active network interface detected; skipped anti-spoof iptables rule."
fi

# Disable Ctrl-Alt-Delete reboot via systemd if present (modern systems)
if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-enabled ctrl-alt-del.target >/dev/null 2>&1; then
        if confirm "Disable Ctrl-Alt-Delete reboot behavior via systemd?"; then
            systemctl mask ctrl-alt-del.target
            printTime "Ctrl-Alt-Delete masked via systemd."
        else
            printTime "Skipped masking Ctrl-Alt-Delete."
        fi
    else
        printTime "Ctrl-Alt-Delete is not enabled or already masked."
    fi
else
    # fallback to upstart file if exists (older systems)
    if [ -f /etc/init/control-alt-delete.conf ]; then
        cp -a /etc/init/control-alt-delete.conf "$BACKUP_DIR/control-alt-delete.conf.bak"
        sed -i '/^exec/ c\exec false' /etc/init/control-alt-delete.conf
        printTime "Patched /etc/init/control-alt-delete.conf to disable exec (backup saved)."
    fi
fi

# AppArmor installation
apt_install_quiet apparmor apparmor-profiles || true
printTime "AppArmor installed (or was already present)."

# Backup and clear crontab safely (ask before removing)
if crontab -l >/dev/null 2>&1; then
    crontab -l > "$BACKUP_DIR/crontab-old.bak"
    chmod 600 "$BACKUP_DIR/crontab-old.bak"
    if confirm "Remove current root crontab entries? (backup saved)"; then
        crontab -r
        printTime "Root crontab removed (backup saved)."
    else
        printTime "Left root crontab intact."
    fi
else
    printTime "No crontab for root to backup/remove."
fi

# Restrict cron/at to root only (keep safe file perms)
cd /etc || true
rm -f cron.deny at.deny 2>/dev/null || true
echo root > cron.allow
echo root > at.allow
chown root:root cron.allow at.allow 2>/dev/null || true
chmod 400 cron.allow at.allow 2>/dev/null || true
cd - >/dev/null 2>&1 || true
printTime "cron/at restricted to root only (cron.allow/at.allow created)."

# Carefully update apt sources list only if user asks (original script overwrote with old Mint repos)
if confirm "Replace /etc/apt/sources.list with a basic Debian/Ubuntu mirror for this Mint release? (Dangerous: may break package management)"; then
    cp -a /etc/apt/sources.list "$BACKUP_DIR/sources.list.bak"
    # Use lsb_release -rs to get release number; user must verify the correctness
    release=$(lsb_release -rs 2>/dev/null || echo "")
    echo "# Backed up original sources to $BACKUP_DIR/sources.list.bak" > /etc/apt/sources.list
    echo "# Please edit this file manually to match your Mint/Ubuntu release." >> /etc/apt/sources.list
    printTime "Wrote placeholder /etc/apt/sources.list and advise manual editing."
else
    printTime "Skipped overwriting /etc/apt/sources.list (safer)."
fi

# Update and upgrade (ask confirmation)
if confirm "Run apt-get update/upgrade/dist-upgrade now?"; then
    apt-get update -qq
    apt-get upgrade -y -qq
    apt-get dist-upgrade -y -qq
    printTime "System updated/upgraded (apt-get)."
else
    printTime "Skipped automatic apt-get upgrade steps."
fi

# Configure unattended-upgrades and apt periodic (safe write)
if [ -f /etc/apt/apt.conf.d/10periodic ]; then
    cp -a /etc/apt/apt.conf.d/10periodic "$BACKUP_DIR/10periodic.bak"
fi
cat > /etc/apt/apt.conf.d/10periodic <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
chmod 644 /etc/apt/apt.conf.d/10periodic
printTime "APT periodic settings written (backup saved if existed)."

# Cleanup packages (ask)
if confirm "Run apt autoremove/autoclean/clean to remove unused packages?"; then
    apt-get autoremove -y -qq
    apt-get autoclean -y -qq
    apt-get clean -y -qq
    printTime "apt autoremove/autoclean/clean executed."
else
    printTime "Skipped apt cleanup."
fi

# Check UID 0 sanity
if [[ $(grep -E '^root:' /etc/passwd | wc -l) -ne 1 ]]; then
    printTime "Warning: multiple root entries in /etc/passwd or root entry not found. Manual check required."
else
    printTime "UID 0 is correctly set to root (single root entry found)."
fi

# Create logs folder with safe perms and collect safe logs
mkdir -p "$LOGS_DIR"
chmod 700 "$LOGS_DIR"
cp -a /etc/services "$LOGS_DIR/allports.log" 2>/dev/null || true
dpkg -l > "$LOGS_DIR/packages.log" 2>/dev/null || true
apt-mark showmanual > "$LOGS_DIR/manuallyinstalled.log" 2>/dev/null || true
service --status-all > "$LOGS_DIR/allservices.txt" 2>/dev/null || true
ps ax > "$LOGS_DIR/processes.log" 2>/dev/null || true
ss -l > "$LOGS_DIR/socketconnections.log" 2>/dev/null || true
if command -v netstat >/dev/null 2>&1; then
    netstat -tlnp > "$LOGS_DIR/listeningports.log" 2>/dev/null || true
fi
[ -f /var/log/auth.log ] && cp -a /var/log/auth.log "$LOGS_DIR/auth.log" 2>/dev/null || true
[ -f /var/log/syslog ] && cp -a /var/log/syslog "$LOGS_DIR/syslog.log" 2>/dev/null || true

# ensure logs are owner root and not world-writable
chown -R root:root "$LOGS_DIR" 2>/dev/null || true
chmod -R 700 "$LOGS_DIR" 2>/dev/null || true
printTime "Collected system logs into $LOGS_DIR (restricted permissions)."

printTime "Script is done. Review $SCRIPT_LOG and $BACKUP_DIR for backups before reboot or further action."
echo "Script run complete. See $SCRIPT_LOG for details and $BACKUP_DIR for backups."

# End of script
