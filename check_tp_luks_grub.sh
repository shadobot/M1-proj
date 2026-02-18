# Script de vérification (Linux) — note /20 (à exécuter sur la VM)

#!/usr/bin/env bash
score=0

# 1) root is on a mapper (encrypted)
findmnt -n / | awk '{print $2}' | grep -q "/dev/mapper/" && score=$((score+6))

# 2) crypttab contains cryptroot
grep -Eq '^\s*cryptroot\s+' /etc/crypttab && score=$((score+5))

# 3) grub password present (superusers or password_pbkdf2 in grub.cfg)
grep -q "password_pbkdf2" /boot/grub/grub.cfg && score=$((score+5))

# 4) crypt device exists at runtime
ls /dev/mapper/cryptroot >/dev/null 2>&1 && score=$((score+4))

echo "NOTE: $score/20"

