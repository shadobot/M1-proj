#Requires -RunAsAdministrator
<#
################################################################################
 EXAMEN FINAL - Securite des systemes d'exploitation Windows (M1 Cybersecurite)
 Script d'AUTO-CORRECTION FINALE

 Role : verifier directement sur la VM de l'etudiant, en fin d'epreuve, chaque
        mesure de durcissement demandee, et calculer une note automatique sur
        18 points. Les 2 points restants (rapport ecrit) sont notes a la main.

 Usage : powershell -ExecutionPolicy Bypass -File .\correction_final.ps1
 Sortie : rapport a l'ecran + C:\Exam\RAPPORT_CORRECTION_FINAL.txt
################################################################################
#>

$ErrorActionPreference = "SilentlyContinue"
New-Item -ItemType Directory -Path "C:\Exam" -Force | Out-Null
$Report = "C:\Exam\RAPPORT_CORRECTION_FINAL.txt"
"" | Out-File $Report -Encoding utf8

$Score = 0.0
$Max   = 18.0

function Log($msg, $color = "White") {
    Write-Host $msg -ForegroundColor $color
    $msg | Out-File $Report -Append -Encoding utf8
}

function Check($pts, $max, $label, $ok) {
    if ($ok) {
        $script:Score += $pts
        Log ("  [OK]     +{0}/{1} pt(s) - {2}" -f $pts, $max, $label) "Green"
    } else {
        Log ("  [ECHEC]  +0/{0} pt(s) - {1}" -f $max, $label) "Red"
    }
}

Log "================================================================" "Yellow"
Log " CORRECTION AUTOMATIQUE - EXAMEN FINAL SECURITE WINDOWS" "Yellow"
Log (" Machine : {0}   Date : {1}" -f $env:COMPUTERNAME, (Get-Date)) "Yellow"
Log "================================================================" "Yellow"

############################################################
Log "`n=== A. Boot & BitLocker (3 pts) ===" "Cyan"
############################################################

# A1 - utilman.exe restaure (n'est plus une copie de cmd.exe)
$ok = $false
$utilman = "$env:SystemRoot\System32\utilman.exe"
$cmd     = "$env:SystemRoot\System32\cmd.exe"
if (Test-Path $utilman) {
    $hU = (Get-FileHash $utilman -Algorithm SHA256).Hash
    $hC = (Get-FileHash $cmd     -Algorithm SHA256).Hash
    if ($hU -ne $hC) { $ok = $true }
}
Check 1 1 "utilman.exe restaure (different de cmd.exe)" $ok

# A2 - BitLocker : protecteurs Password/PIN + RecoveryPassword presents
$ok = $false
$blv = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue
if ($blv) {
    $types = $blv.KeyProtector.KeyProtectorType
    $hasRecovery = $types -contains "RecoveryPassword"
    $hasPrimary  = ($types -contains "Password") -or ($types -contains "TpmPin") -or ($types -contains "Pin")
    if ($hasRecovery -and $hasPrimary) { $ok = $true }
}
Check 1 1 "BitLocker : protecteur principal + cle de recuperation configures" $ok

# A3 - BitLocker : chiffrement engage (protection On ou chiffrement en cours)
$ok = $false
if ($blv) {
    if ($blv.ProtectionStatus -eq "On" -or $blv.VolumeStatus -eq "EncryptionInProgress" -or $blv.VolumeStatus -eq "FullyEncrypted") {
        $ok = $true
    }
}
Check 1 1 ("BitLocker actif sur C: (statut: {0})" -f $blv.VolumeStatus) $ok

############################################################
Log "`n=== B. Protocoles reseau dangereux (4 pts) ===" "Cyan"
############################################################

# B1 - SMBv1 desactive
$ok = -not (Get-SmbServerConfiguration).EnableSMB1Protocol
Check 1 1 "SMBv1 desactive (EnableSMB1Protocol = False)" $ok

# B2 - LLMNR desactive
$llmnr = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -ErrorAction SilentlyContinue).EnableMulticast
Check 1 1 "LLMNR desactive (EnableMulticast = 0)" ($llmnr -eq 0)

# B3 - WDigest desactive
$wd = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest" -ErrorAction SilentlyContinue).UseLogonCredential
Check 1 1 "WDigest desactive (UseLogonCredential = 0)" ($wd -eq 0)

# B4 - NetBIOS desactive sur les interfaces
$ok = $false
$ifaces = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces" -ErrorAction SilentlyContinue
if ($ifaces) {
    $vals = $ifaces | ForEach-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).NetbiosOptions }
    $vals = $vals | Where-Object { $_ -ne $null }
    if ($vals.Count -gt 0 -and (($vals | Where-Object { $_ -ne 2 }).Count -eq 0)) { $ok = $true }
}
Check 1 1 "NetBIOS desactive (NetbiosOptions = 2 sur les interfaces)" $ok

############################################################
Log "`n=== C. Services & Windows Defender (4 pts) ===" "Cyan"
############################################################

# C1 - Spooler desactive
$s = Get-Service Spooler -ErrorAction SilentlyContinue
Check 1 1 "Service Print Spooler arrete/desactive" ($s -and ($s.StartType -eq "Disabled" -or $s.Status -eq "Stopped"))

# C2 - RemoteRegistry desactive
$s = Get-Service RemoteRegistry -ErrorAction SilentlyContinue
Check 1 1 "Service RemoteRegistry arrete/desactive" ($s -and ($s.StartType -eq "Disabled" -or $s.Status -eq "Stopped"))

# C3 - Regles ASR configurees (>= 3)
$asr = (Get-MpPreference).AttackSurfaceReductionRules_Ids
$asrCount = if ($asr) { @($asr).Count } else { 0 }
Check 1 1 ("Au moins 3 regles ASR configurees (trouvees: {0})" -f $asrCount) ($asrCount -ge 3)

# C4 - Controlled Folder Access active
$cfa = (Get-MpPreference).EnableControlledFolderAccess
Check 1 1 "Controlled Folder Access active (protection ransomware)" ($cfa -eq 1)

############################################################
Log "`n=== D. Politique de comptes & Audit (3 pts) ===" "Cyan"
############################################################

$netacc = net accounts

# D1 - Longueur minimale mot de passe >= 12
$ok = $false
$line = $netacc | Select-String -Pattern "password length|longueur mini" | Select-Object -First 1
if ($line) {
    $num = ([regex]::Match($line.ToString(), "(\d+)")).Value
    if ($num -and [int]$num -ge 12) { $ok = $true }
}
Check 1 1 "Longueur minimale des mots de passe >= 12" $ok

# D2 - Seuil de verrouillage entre 1 et 5
$ok = $false
$line = $netacc | Select-String -Pattern "Lockout threshold|verrouillage" | Select-Object -First 1
if ($line) {
    $num = ([regex]::Match($line.ToString(), "(\d+)")).Value
    if ($num -and [int]$num -ge 1 -and [int]$num -le 5) { $ok = $true }
}
Check 1 1 "Seuil de verrouillage de compte entre 1 et 5 tentatives" $ok

# D3 - auditpol Logon en Success and Failure
$ok = $false
$ap = auditpol /get /subcategory:"Logon" 2>$null
if ($ap -match "Success and Failure" -or $ap -match "Succes et Echec" -or ($ap -match "Success" -and $ap -match "Failure")) { $ok = $true }
Check 1 1 "Audit des connexions (Logon) en Success + Failure" $ok

############################################################
Log "`n=== E. Journalisation & Sysmon (2 pts) ===" "Cyan"
############################################################

# E1 - Journal Security >= 1 Go
$ok = $false
$secLog = Get-WinEvent -ListLog Security -ErrorAction SilentlyContinue
if ($secLog -and $secLog.MaximumSizeInBytes -ge 1073741824) { $ok = $true }
Check 1 1 ("Journal Security >= 1 Go (taille: {0} octets)" -f $secLog.MaximumSizeInBytes) $ok

# E2 - Sysmon en cours d'execution
$sysmon = Get-Service -Name "Sysmon*" -ErrorAction SilentlyContinue
Check 1 1 "Service Sysmon installe et en cours d'execution" ($sysmon -and $sysmon.Status -eq "Running")

############################################################
Log "`n=== F. Collecte IR (2 pts) ===" "Cyan"
############################################################

# F1 - Repertoire incident avec >= 6 fichiers
$ok = $false
$irDir = Get-ChildItem "C:\Temp" -Directory -Filter "incident_*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($irDir) {
    $nb = (Get-ChildItem $irDir.FullName -File -ErrorAction SilentlyContinue).Count
    if ($nb -ge 6) { $ok = $true }
}
Check 1 1 "Repertoire de collecte IR (C:\Temp\incident_*) avec >= 6 fichiers" $ok

# F2 - Fichier de hashes present dans la collecte
$ok = $false
if ($irDir) {
    $hashFile = Get-ChildItem $irDir.FullName -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "hash" }
    if ($hashFile) { $ok = $true }
}
Check 1 1 "Empreintes SHA256 de la collecte generees (fichier de hashes)" $ok

############################################################
# TOTAL
############################################################
Log "`n================================================================" "Yellow"
Log (" SCORE AUTOMATIQUE : {0} / {1}" -f $Score, $Max) "Yellow"
Log " (+ 2 points de rapport ecrit notes manuellement par l'enseignant)"
Log (" NOTE FINALE ESTIMEE : {0} / 20 (rapport non inclus)" -f ($Score + 2)) "Yellow"
Log "================================================================" "Yellow"
Log ("`nRapport detaille enregistre dans : {0}" -f $Report)
