#!/bin/bash
# deploy_s5_linux.sh — Déploiement VM Debian séance S5
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info(){ echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok(){   echo -e "${GREEN}[OK]${NC}   $1"; }
[[ $EUID -ne 0 ]] && { echo -e "${RED}root requis${NC}"; exit 1; }

log_info "Déploiement S5 — Journalisation + Sauvegarde + AIDE + IR"

# Paquets
apt-get update -qq
for pkg in rsyslog auditd aide aide-common logrotate rsync tar cron; do
    dpkg -l "$pkg" &>/dev/null || apt-get install -y -qq "$pkg"
    log_ok "$pkg OK"
done

# Données de test pour TP sauvegarde
mkdir -p /var/data_tp
for i in {1..5}; do
    [[ ! -f "/var/data_tp/fichier_${i}.dat" ]] && \
        dd if=/dev/urandom bs=1k count=100 2>/dev/null | base64 > "/var/data_tp/fichier_${i}.dat"
done
log_ok "Données TP créées dans /var/data_tp/"

# Répertoires de sauvegarde
mkdir -p /backup/rsync_backup /backup/archives
log_ok "Répertoires backup créés"

# Journal persistant
mkdir -p /var/log/journal
systemd-tmpfiles --create --prefix /var/log/journal 2>/dev/null || true
log_ok "Journal systemd persistant configuré"

# Créer un utilisateur etudiant si absent
if ! id etudiant &>/dev/null; then
    useradd -m -s /bin/bash etudiant
    echo "etudiant:Etudiant@2024!" | chpasswd
    usermod -aG sudo etudiant
    log_ok "Utilisateur etudiant créé"
fi

# Guide TP
cat > /home/etudiant/GUIDE_TP_S5.txt << 'EOF'
=== GUIDE TP S5 — Journalisation + Sauvegarde + AIDE + IR ===

JOURNALD :
  journalctl -u ssh -p warning --since "1h ago"
  journalctl -b -p err
  journalctl --disk-usage

RSYSLOG :
  rsyslogd -N1                     # Valider config
  logger -p auth.warning -t TEST "message"
  grep "TEST" /var/log/auth.log

AUDITD :
  systemctl status auditd
  auditctl -s                       # Statut règles
  ausearch -k shadow_access         # Événements par clé
  aureport --login                  # Rapport connexions

RSYNC :
  rsync -av --dry-run SOURCE/ DEST/ # Test sans modifier
  rsync -av SOURCE/ DEST/           # Synchroniser

TAR :
  tar -czf /backup/backup_$(date +%Y%m%d).tar.gz /var/data_tp/
  sha256sum /backup/backup_*.tar.gz > backup.sha256
  sha256sum -c backup.sha256

AIDE :
  aide --init                        # Initialiser base
  cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
  aide --check                       # Vérifier intégrité

IR TRIAGE :
  who; w; last; ps aux; ss -tlnp
  find /tmp -newer /etc/passwd -ls
  awk -F: '$3==0' /etc/passwd       # Comptes UID 0
EOF
chown etudiant:etudiant /home/etudiant/GUIDE_TP_S5.txt

log_ok "Déploiement S5 terminé — Faire snapshot AVANT_TP_S5"
