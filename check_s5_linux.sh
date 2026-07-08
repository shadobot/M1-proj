#!/bin/bash
# check_s5_linux.sh — Auto-correction S5 Linux /20
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'; BOLD='\033[1m'
SCORE=0; FEEDBACK=()
pass(){ SCORE=$((SCORE+$2)); FEEDBACK+=("${GREEN}[+$2pts]${NC} ✓ $1"); }
fail(){ FEEDBACK+=("${RED}[0/$2pts]${NC} ✗ $1 — $3"); }
info(){ FEEDBACK+=("${BLUE}[INFO]${NC}  $1"); }
[[ $EUID -ne 0 ]] && { echo -e "${RED}root requis${NC}"; exit 1; }

echo -e "\n${BOLD}=== AUTO-CORRECTION S5 LINUX ===${NC}\n"

# 1. Journal persistant (2 pts)
echo -e "${BLUE}[1]${NC} Journal persistant..."
if [[ -d /var/log/journal ]]; then
    pass "Répertoire /var/log/journal présent (stockage persistant)" 1
    DU=$(journalctl --disk-usage 2>/dev/null | grep -oE "[0-9]+\.[0-9]+ [KMGT]?B" | head -1)
    [[ -n "$DU" ]] && pass "Journal utilisé : $DU" 1 || fail "Journal vide ou non lisible" 1 "Vérifier journald.conf Storage=persistent"
else
    fail "/var/log/journal absent — journal volatile" 2 "mkdir -p /var/log/journal + restart journald"
fi

# 2. rsyslog fonctionnel + message test (2 pts)
echo -e "${BLUE}[2]${NC} rsyslog..."
if systemctl is-active rsyslog &>/dev/null; then
    pass "rsyslog actif" 1
    if grep -q "TP_S5_TEST\|TEST_S5" /var/log/auth.log 2>/dev/null || grep -q "TP_S5_TEST\|TEST_S5" /var/log/syslog 2>/dev/null; then
        pass "Message de test logger trouvé dans les logs" 1
    else
        fail "Message de test logger absent" 1 "logger -p auth.warning -t TP_S5_TEST 'test'"
    fi
else
    fail "rsyslog non actif" 2 "systemctl start rsyslog"
fi

# 3. auditd + règles (2 pts)
echo -e "${BLUE}[3]${NC} auditd..."
if systemctl is-active auditd &>/dev/null; then
    pass "auditd actif" 1
    if auditctl -l 2>/dev/null | grep -q "shadow\|ssh\|sudoers"; then
        pass "Règles d'audit sécurité configurées" 1
    else
        fail "Aucune règle d'audit détectée" 1 "Créer /etc/audit/rules.d/10-security.rules"
    fi
else
    fail "auditd non actif" 2 "apt install auditd && systemctl enable --now auditd"
fi

# 4. rsync fonctionnel (2 pts)
echo -e "${BLUE}[4]${NC} rsync sauvegarde..."
if [[ -d /backup/rsync_backup ]] && [[ "$(ls /backup/rsync_backup/ 2>/dev/null | wc -l)" -gt 0 ]]; then
    pass "Répertoire rsync_backup non vide ($(ls /backup/rsync_backup/ | wc -l) fichiers)" 2
else
    fail "rsync_backup absent ou vide" 2 "rsync -av /var/data_tp/ /backup/rsync_backup/"
fi

# 5. Archive tar + checksum (2 pts)
echo -e "${BLUE}[5]${NC} Sauvegarde tar..."
ARCHIVES=$(find /backup/archives -name "*.tar.gz" 2>/dev/null | wc -l)
CHECKSUMS=$(find /backup/archives -name "*.sha256" 2>/dev/null | wc -l)
if [[ "$ARCHIVES" -gt 0 ]]; then
    pass "$ARCHIVES archive(s) tar.gz créée(s)" 1
    if [[ "$CHECKSUMS" -gt 0 ]]; then
        pass "$CHECKSUMS fichier(s) checksum SHA256 présent(s)" 1
    else
        fail "Fichier checksum .sha256 absent" 1 "sha256sum archive.tar.gz > archive.sha256"
    fi
else
    fail "Aucune archive tar.gz dans /backup/archives/" 2 "tar -czf /backup/archives/backup_DATE.tar.gz /var/data_tp/"
fi

# 6. Cron de sauvegarde (2 pts)
echo -e "${BLUE}[6]${NC} Cron sauvegarde..."
if crontab -l 2>/dev/null | grep -q "backup\|tar\|rsync"; then
    pass "Tâche cron de sauvegarde configurée" 1
    info "  $(crontab -l | grep -E 'backup|tar|rsync' | head -1)"
else
    fail "Aucune tâche cron de sauvegarde" 1 "Ajouter une ligne cron avec backup_tp_s5.sh"
fi
if [[ -f /var/log/backup_tp.log ]] && grep -q "OK\|terminée\|Début" /var/log/backup_tp.log 2>/dev/null; then
    pass "Log de sauvegarde présent et contient une exécution réussie" 1
else
    fail "Log de sauvegarde absent ou sans exécution" 1 "Exécuter manuellement backup_tp_s5.sh"
fi

# 7. AIDE configuré et base initialisée (3 pts)
echo -e "${BLUE}[7]${NC} AIDE..."
if command -v aide &>/dev/null; then
    pass "AIDE installé" 1
    if [[ -f /var/lib/aide/aide.db ]]; then
        pass "Base AIDE aide.db présente" 1
        # Vérifier que AIDE détecte bien les changements
        AIDE_OUT=$(aide --check 2>/dev/null | head -30)
        AIDE_RC=$?
        if [[ $AIDE_RC -eq 1 ]] && echo "$AIDE_OUT" | grep -q "Changed\|Added\|Removed"; then
            pass "AIDE détecte des modifications (comportement attendu après simulation)" 1
        elif [[ $AIDE_RC -eq 0 ]]; then
            info "AIDE : aucune modification détectée (OK si la simulation n'a pas été faite)"
            SCORE=$((SCORE+1))
            FEEDBACK+=("${YELLOW}[+1/1pts]${NC} AIDE sans modification — acceptable")
        else
            fail "AIDE check retourne une erreur" 1 "Vérifier la configuration et rerun aide --init"
        fi
    else
        fail "Base AIDE non initialisée" 2 "aide --init && cp aide.db.new aide.db"
    fi
else
    fail "AIDE non installé" 3 "apt install aide"
fi

# 8. Collecte IR : répertoire incident (2 pts)
echo -e "${BLUE}[8]${NC} Collecte IR..."
INCIDENT_DIRS=$(find /tmp -maxdepth 1 -name "incident_*" -type d 2>/dev/null)
if [[ -n "$INCIDENT_DIRS" ]]; then
    INCIDENT_DIR=$(echo "$INCIDENT_DIRS" | head -1)
    FILE_COUNT=$(ls "$INCIDENT_DIR" 2>/dev/null | wc -l)
    if [[ "$FILE_COUNT" -ge 5 ]]; then
        pass "Répertoire de collecte IR ($FILE_COUNT fichiers) : $INCIDENT_DIR" 2
    else
        SCORE=$((SCORE+1)); FEEDBACK+=("${YELLOW}[+1/2pts]${NC} Collecte IR incomplète ($FILE_COUNT fichiers, min 5)")
    fi
else
    fail "Aucun répertoire incident_* dans /tmp" 2 "Exécuter la collecte volatiles du TP D.2"
fi

# Rapport
echo -e "\n${BOLD}=== RAPPORT S5 ===${NC}\n"
for l in "${FEEDBACK[@]}"; do echo -e "  $l"; done
PCT=$(( SCORE*100/20 ))
GC=$RED; [[ $PCT -ge 50 ]] && GC=$YELLOW; [[ $PCT -ge 75 ]] && GC=$GREEN
echo -e "\n  ${BOLD}NOTE : ${GC}${SCORE}/20${NC}  ($PCT%)\n"
