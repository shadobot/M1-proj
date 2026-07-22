#!/bin/bash
################################################################################
# EXAMEN FINAL — Sécurité des systèmes d'exploitation (M1 Cybersécurité)
# Script d'AUTO-CORRECTION FINALE
#
# Rôle : vérifier directement sur la VM de l'étudiant, en fin d'épreuve,
#        chaque mesure de durcissement demandée dans le sujet, et calculer
#        une note automatique sur 18 points (les 2 points restants portent
#        sur le rapport écrit et sont notés manuellement par l'enseignant).
#
# Usage : sudo bash correction_final.sh
# Sortie : rapport lisible à l'écran + fichier /root/RAPPORT_CORRECTION_FINAL.txt
################################################################################

set -uo pipefail

REPORT="/root/RAPPORT_CORRECTION_FINAL.txt"
: > "$REPORT"

if [ "$EUID" -ne 0 ]; then
    echo "[ERREUR] Ce script doit être exécuté en root (sudo bash correction_final.sh)"
    exit 1
fi

SCORE=0
MAX=18

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

log() { echo -e "$1" | tee -a "$REPORT"; }

# points_earned points_max libelle
check() {
    local pts="$1" max="$2" label="$3" ok="$4"
    if [ "$ok" = "1" ]; then
        SCORE=$(echo "$SCORE + $pts" | bc)
        log "${GREEN}  [OK]${NC} +${pts}/${max} pt(s) — ${label}"
    else
        log "${RED}  [ÉCHEC]${NC} +0/${max} pt(s) — ${label}"
    fi
}

log "================================================================"
log " CORRECTION AUTOMATIQUE — EXAMEN FINAL SÉCURITÉ LINUX"
log " Machine : $(hostname)   Date : $(date)"
log "================================================================"

############################################################
# A. BOOT & CHIFFREMENT (4 pts)
############################################################
log ""
log "${YELLOW}=== A. Sécurité du boot et chiffrement (4 pts) ===${NC}"

# A1 - mot de passe GRUB (1.5)
ok=0
if [ -f /boot/grub/grub.cfg ] && grep -q "password_pbkdf2" /boot/grub/grub.cfg 2>/dev/null && grep -q "superusers" /boot/grub/grub.cfg 2>/dev/null; then
    ok=1
fi
check 1.5 1.5 "Mot de passe GRUB configuré (superusers + password_pbkdf2 dans grub.cfg)" "$ok"

# A2 - timeout réduit (0.5)
ok=0
TMO=$(grep -oP '^GRUB_TIMEOUT=\K[0-9]+' /etc/default/grub 2>/dev/null || echo 999)
if [ "$TMO" -le 5 ] 2>/dev/null; then ok=1; fi
check 0.5 0.5 "GRUB_TIMEOUT réduit à 5s ou moins (valeur trouvée: ${TMO})" "$ok"

# A3 - conteneur LUKS formaté et fonctionnel (1)
ok=0
if [ -f /root/exam_luks.img ] && cryptsetup isLuks /root/exam_luks.img 2>/dev/null; then
    ok=1
fi
check 1 1 "Conteneur /root/exam_luks.img formaté en LUKS (cryptsetup isLuks)" "$ok"

# A4 - backup de l'en-tête LUKS (1)
ok=0
if compgen -G "/root/*header*.bin" > /dev/null 2>&1 || compgen -G "/root/*luks*backup*" > /dev/null 2>&1; then
    ok=1
fi
check 1 1 "Sauvegarde de l'en-tête LUKS présente (cryptsetup luksHeaderBackup)" "$ok"

############################################################
# B. FIREWALL NFTABLES (3 pts)
############################################################
log ""
log "${YELLOW}=== B. Firewall nftables (3 pts) ===${NC}"

RULESET=$(nft list ruleset 2>/dev/null)

# B1 - policy drop en input (1)
ok=0
echo "$RULESET" | grep -A2 "hook input" | grep -q "policy drop" && ok=1
check 1 1 "Policy DROP appliquée sur la chaîne input" "$ok"

# B2 - established/related + lo accept (1)
ok=0
if echo "$RULESET" | grep -q "ct state established,related accept" && echo "$RULESET" | grep -q 'iif "lo" accept\|iif lo accept'; then
    ok=1
fi
check 1 1 "Règles ct state established,related + loopback (lo) présentes" "$ok"

# B3 - seul le port SSH configuré est ouvert (1)
ok=0
SSHPORT=$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}')
if [ -n "${SSHPORT:-}" ] && echo "$RULESET" | grep -q "tcp dport ${SSHPORT}"; then
    ok=1
fi
check 1 1 "Règle nftables autorisant le port SSH configuré (${SSHPORT:-non détecté})" "$ok"

############################################################
# C. DURCISSEMENT SSH (3 pts)
############################################################
log ""
log "${YELLOW}=== C. Durcissement SSH (3 pts) ===${NC}"

SSHD_T=$(sshd -T 2>/dev/null)

ok=0; echo "$SSHD_T" | grep -qi "^permitrootlogin no" && ok=1
check 0.5 0.5 "PermitRootLogin no" "$ok"

ok=0; echo "$SSHD_T" | grep -qi "^passwordauthentication no" && ok=1
check 0.5 0.5 "PasswordAuthentication no" "$ok"

ok=0; [ -n "${SSHPORT:-}" ] && [ "$SSHPORT" != "22" ] && ok=1
check 0.5 0.5 "Port SSH non standard (≠22) — port actuel: ${SSHPORT:-?}" "$ok"

ok=0
MAT=$(echo "$SSHD_T" | awk '/^maxauthtries /{print $2; exit}')
[ -n "${MAT:-}" ] && [ "$MAT" -le 3 ] 2>/dev/null && ok=1
check 0.5 0.5 "MaxAuthTries ≤ 3 (valeur: ${MAT:-?})" "$ok"

ok=0; echo "$SSHD_T" | grep -qi "^allowusers " && ok=1
check 0.5 0.5 "AllowUsers configuré (liste blanche)" "$ok"

ok=0; sshd -t 2>/dev/null && ok=1
check 0.5 0.5 "Configuration sshd syntaxiquement valide (sshd -t)" "$ok"

############################################################
# D. FAIL2BAN (2 pts)
############################################################
log ""
log "${YELLOW}=== D. Fail2ban (2 pts) ===${NC}"

ok=0
if command -v fail2ban-client >/dev/null 2>&1 && fail2ban-client status sshd >/dev/null 2>&1; then
    ok=1
fi
check 1 1 "Jail sshd Fail2ban active" "$ok"

ok=0
if [ -f /etc/fail2ban/jail.local ] && grep -q "bantime" /etc/fail2ban/jail.local && grep -q "findtime" /etc/fail2ban/jail.local && grep -q "maxretry" /etc/fail2ban/jail.local; then
    ok=1
fi
check 1 1 "bantime / findtime / maxretry configurés dans jail.local" "$ok"

############################################################
# E. JOURNALISATION (2 pts)
############################################################
log ""
log "${YELLOW}=== E. Journalisation (2 pts) ===${NC}"

ok=0
if grep -q "^Storage=persistent" /etc/systemd/journald.conf 2>/dev/null && [ -d /var/log/journal ] && [ -n "$(ls -A /var/log/journal 2>/dev/null)" ]; then
    ok=1
fi
check 1 1 "journald en stockage persistant (/var/log/journal non vide)" "$ok"

# E2 - règle auditd sur fichier sensible, déclenchée
ok=0
if command -v auditctl >/dev/null 2>&1 && auditctl -l 2>/dev/null | grep -qE "/etc/shadow|/etc/ssh/sshd_config"; then
    # on déclenche l'événement et on vérifie qu'il est bien tracé
    cat /etc/shadow > /dev/null 2>&1
    sleep 1
    if command -v ausearch >/dev/null 2>&1 && ausearch -ts recent -k shadow_access 2>/dev/null | grep -q "type=SYSCALL"; then
        ok=1
    elif ausearch -ts recent 2>/dev/null | grep -qE "shadow|sshd_config"; then
        ok=1
    fi
fi
check 1 1 "Règle auditd sur fichier sensible active et événement tracé" "$ok"

############################################################
# F. SAUVEGARDE 3-2-1 (2 pts)
############################################################
log ""
log "${YELLOW}=== F. Sauvegarde 3-2-1 (2 pts) ===${NC}"

ok=0
BACKUP_DIR=$(find /backup -maxdepth 2 -type d -iname "*rsync*" 2>/dev/null | head -1)
if [ -n "$BACKUP_DIR" ] && diff -rq /var/data_exam/ "$BACKUP_DIR" >/dev/null 2>&1; then
    ok=1
fi
check 1 1 "Sauvegarde rsync de /var/data_exam identique à la source" "$ok"

ok=0
ARCHIVE=$(find /backup -maxdepth 3 -iname "*.tar.gz" 2>/dev/null | head -1)
CHECKSUM=$(find /backup -maxdepth 3 -iname "*.sha256" 2>/dev/null | head -1)
if [ -n "$ARCHIVE" ] && [ -n "$CHECKSUM" ]; then
    if (cd "$(dirname "$CHECKSUM")" && sha256sum -c "$(basename "$CHECKSUM")" >/dev/null 2>&1); then
        ok=1
    fi
fi
check 1 1 "Archive tar.gz + checksum SHA256 valide" "$ok"

############################################################
# G. INTÉGRITÉ AIDE (2 pts)
############################################################
log ""
log "${YELLOW}=== G. Intégrité fichiers avec AIDE (2 pts) ===${NC}"

ok=0
[ -f /var/lib/aide/aide.db ] && ok=1
check 0.5 0.5 "Base de référence AIDE initialisée (aide.db)" "$ok"

ok=0
if command -v aide >/dev/null 2>&1 && [ -f /var/lib/aide/aide.db ]; then
    TESTFILE="/var/data_exam/__test_correction_aide.txt"
    echo "modification test correction $(date)" > "$TESTFILE"
    OUT=$(aide --check 2>/dev/null)
    if echo "$OUT" | grep -qi "added\|changed\|differences"; then
        ok=1
    fi
    rm -f "$TESTFILE"
fi
check 1.5 1.5 "AIDE détecte une modification injectée par le correcteur" "$ok"

############################################################
# TOTAL
############################################################
log ""
log "================================================================"
log " SCORE AUTOMATIQUE : ${SCORE} / ${MAX}"
log " (+ 2 points de rapport écrit noté manuellement par l'enseignant)"
log " NOTE FINALE ESTIMÉE : $(echo "$SCORE + 2" | bc) / 20 (rapport non inclus dans ce calcul)"
log "================================================================"
log ""
log "Rapport détaillé enregistré dans : ${REPORT}"
