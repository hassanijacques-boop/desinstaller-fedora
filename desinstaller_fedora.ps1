# ============================================================
#  OUTIL DE DESINSTALLATION DE FEDORA  (version 3)
#  ------------------------------------------------------------
#  - Diagnostic complet : TOUS les disques, TOUS les types
#  - Reveille les disques endormis (hors ligne)
#  - Supprime UNIQUEMENT les partitions Linux (Fedora) confirmees
#  - Ne touche JAMAIS a Windows, C: ni a la partition de demarrage
#  - Repare le demarrage de Windows automatiquement
#  - Journal : C:\desinstall_fedora_log.txt
# ============================================================

# --- Elevation automatique en administrateur ---
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Demande des droits administrateur..."
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$ErrorActionPreference = 'Continue'
$log = 'C:\desinstall_fedora_log.txt'
try { Start-Transcript -Path $log -Force | Out-Null } catch {}

function Ecrire ($m) { Write-Host $m -ForegroundColor Cyan }
function Alerte ($m) { Write-Host $m -ForegroundColor Yellow }
function Erreur ($m) { Write-Host $m -ForegroundColor Red }
function Succes ($m) { Write-Host $m -ForegroundColor Green }

# GUID de partitions Linux (disques GPT)
$guidsLinux = @(
    '0FC63DAF-8483-4772-8E79-3D69D8477DE4',  # Linux filesystem (ext4, xfs, btrfs)
    '0657FD6D-A4AB-43C4-84E5-0933C84B4F4F',  # Linux swap
    'E6D6D379-F507-44C2-A23C-238F2A3DF928',  # Linux LVM
    'A19D880F-05FC-4D3B-A006-743F0F84911E',  # Linux RAID
    '933AC7E1-2EB4-4F13-B844-0E14E2AEF915',  # Linux /home
    '8DA63339-0007-60C0-C436-083AC8230908',  # Linux reserve
    '3B8F8425-20E0-4F3B-907F-1DD25A05F9D9',  # Linux /boot
    '4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709',  # Linux racine btrfs
    '4D21B016-B534-45C2-A9FB-5C16E091FD2D',  # Linux racine x86-64
    '44479540-F297-41B2-9AF7-D131D5F0458A',  # Linux racine x86
    '5DFBF5F4-2848-4BAC-AA5E-0D9A20B745A6',  # Linux /srv
    'BC13C2FF-59E6-4262-A352-B275FD6F7172'   # Linux /usr (Anaconda)
)
# Types de partitions Linux (disques MBR)
$typesLinuxMbr = @('0x82', '0x83', '0x8E', '0x8F')

function Est-Linux($p) {
    $t = "$($p.Type)"
    if ($t -eq '') { return $false }
    foreach ($g in $guidsLinux) {
        if (($t -eq $g) -or ($t -like "*$g*")) { return $true }
    }
    foreach ($x in $typesLinuxMbr) {
        if (($t -eq $x) -or ($t -like "*$x*")) { return $true }
    }
    return $false
}

# --- Diagnostic complet : tous les disques et leurs types ---
function Afficher-Disques {
    Ecrire ""
    Ecrire "DIAGNOSTIC COMPLET (tous les disques et compartiments) :"
    Ecrire "--------------------------------------------------------"
    foreach ($d in @(Get-Disk)) {
        $etat = if ($d.IsOffline) { "ENDORMI (hors ligne)" } else { "en ligne" }
        Ecrire ("  Disque {0} : {1} Go au total - {2} - style {3} - {4}" -f $d.Number, [math]::Round($d.Size / 1GB, 1), $d.FriendlyName, $d.PartitionStyle, $etat)
        foreach ($p in @(Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue)) {
            $gb = [math]::Round($p.Size / 1GB, 2)
            $lettre = ''
            if ($p.DriveLetter) { $lettre = " (lettre $($p.DriveLetter))" }
            Ecrire ("      * compartiment {0} : {1} Go - type {2}{3}" -f $p.PartitionNumber, $gb, $p.Type, $lettre)
        }
    }
    Ecrire ""
}

# --- Analyse : chercher les partitions Linux (sans les fantomes) ---
function Analyser {
    $toutes = @(Get-Partition -ErrorAction SilentlyContinue)
    $trouves = @()
    foreach ($p in $toutes) {
        if (($p.DiskNumber -eq $null) -or ($p.Size -le 0)) { continue }
        if (Est-Linux $p) {
            if ($p.IsSystem -or $p.IsBoot -or $p.IsActive) {
                Alerte ("  - Partition Linux protegee ignoree (disque {0}, part. {1}) : securite" -f $p.DiskNumber, $p.PartitionNumber)
            } else {
                $trouves += $p
            }
        }
    }
    return ,$trouves
}

# --- Suppression + reparation + recuperation d'espace ---
function Supprimer-Fedora($candidats) {
    Ecrire ""
    Ecrire "Partitions Fedora/Linux trouvees (a SUPPRIMER) :"
    Ecrire "------------------------------------------------"
    foreach ($c in $candidats) {
        $gb = [math]::Round($c.Size / 1GB, 1)
        $lettre = ''
        if ($c.DriveLetter) { $lettre = " (lettre $($c.DriveLetter) - sera retiree)" }
        Ecrire ("  - Disque {0}, compartiment n°{1} : {2} Go - type {3}{4}" -f $c.DiskNumber, $c.PartitionNumber, $gb, $c.Type, $lettre)
    }
    Ecrire ""
    Ecrire "Autres partitions (Windows, demarrage, ...) :"
    Ecrire "---------------------------------------------"
    $toutes = @(Get-Partition -ErrorAction SilentlyContinue)
    foreach ($p in $toutes) {
        if ($candidats -notcontains $p) {
            if (($p.DiskNumber -eq $null) -or ($p.Size -le 0)) { continue }
            $gb = [math]::Round($p.Size / 1GB, 1)
            $lettre = ''
            if ($p.DriveLetter) { $lettre = " (lettre $($p.DriveLetter))" }
            Ecrire ("  - Disque {0}, compartiment n°{1} : {2} Go - type {3}{4}" -f $p.DiskNumber, $p.PartitionNumber, $gb, $p.Type, $lettre)
        }
    }

    Ecrire ""
    Alerte "Verifie que la liste a SUPPRIMER correspond bien a Fedora"
    Alerte "(type commencant par Linux ou 0x8). Si quelque chose semble"
    Alerte "anormal, tape autre chose que OUI : l'outil ne fera rien."
    Ecrire ""
    $confirmation = Read-Host "Tape OUI (en majuscules) pour SUPPRIMER ces compartiments"
    if ($confirmation -ne 'OUI') {
        Erreur "Operation annulee. Aucune modification n'a ete faite."
        Read-Host "Appuie sur Entree pour fermer"
        exit 0
    }

    # --- Suppression ---
    Ecrire ""
    Ecrire "Suppression des compartiments Fedora..."
    $echecs = 0
    foreach ($c in $candidats) {
        # Retirer la lettre si une partition Linux en avait une
        if ($c.DriveLetter) {
            try {
                Remove-PartitionAccessPath -DiskNumber $c.DiskNumber -PartitionNumber $c.PartitionNumber -AccessPath ($c.DriveLetter.ToString() + ':\') -ErrorAction Stop
                Succes ("  - Lettre {0} retiree du compartiment {1}" -f $c.DriveLetter, $c.PartitionNumber)
            } catch {
                Alerte ("  - Impossible de retirer la lettre {0} (continue quand meme)" -f $c.DriveLetter)
            }
        }
        try {
            Remove-Partition -DiskNumber $c.DiskNumber -PartitionNumber $c.PartitionNumber -Confirm:$false -ErrorAction Stop
            Succes ("  - Supprime : disque {0}, compartiment n°{1}" -f $c.DiskNumber, $c.PartitionNumber)
        } catch {
            Erreur ("  - ECHEC disque {0}, compartiment n°{1} : {2}" -f $c.DiskNumber, $c.PartitionNumber, $_.Exception.Message)
            $echecs++
        }
    }
    if ($echecs -gt 0) {
        Erreur ""
        Erreur "Certaines partitions n'ont pas pu etre supprimees."
        Erreur "Relance l'outil apres redemarrage du PC."
    }

    # --- Reparation du demarrage ---
    Ecrire ""
    Ecrire "Reparation du demarrage Windows..."
    $firmware = (Get-CimInstance -ClassName Win32_ComputerSystem).FirmwareType
    $sys = $env:SystemDrive

    if ($firmware -eq 2) {
        Ecrire "  Mode detecte : UEFI"
        try {
            bcdedit /export C:\bcd_backup.bcd | Out-Null
            Succes "  - Sauvegarde du demarrage : C:\bcd_backup.bcd"
        } catch { Alerte "  - Sauvegarde du demarrage impossible (pas bloquant)" }

        $esp = $toutes | Where-Object { ($_.Type -eq 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b') -and (-not $_.DriveLetter) } | Select-Object -First 1
        if ($esp) {
            $lettresPrises = @(Get-Partition | Where-Object { $_.DriveLetter } | ForEach-Object { "$($_.DriveLetter)" })
            $lettre = $null
            foreach ($l in @('Z','Y','X','W','V','U','T','S','R','Q','P','N','M','L','K','J','H','G','F','E','D')) {
                if ($lettresPrises -notcontains $l) { $lettre = $l; break }
            }
            if ($lettre) {
                try {
                    Set-Partition -DiskNumber $esp.DiskNumber -PartitionNumber $esp.PartitionNumber -NewDriveLetter $lettre -ErrorAction Stop
                    $chemin = $lettre + ':\'
                    bcdboot "$sys\Windows" /s $chemin /f UEFI | Out-Null
                    Succes "  - Demarrage Windows reconstruit"
                    try { Remove-PartitionAccessPath -DiskNumber $esp.DiskNumber -PartitionNumber $esp.PartitionNumber -AccessPath $chemin -ErrorAction SilentlyContinue } catch {}
                } catch {
                    Erreur "  - Echec de la reparation : $($_.Exception.Message)"
                }
            } else {
                Erreur "  - Aucune lettre libre pour reparer le demarrage"
            }
        } else {
            Erreur "  - Partition de demarrage EFI introuvable"
        }
        try {
            bcdedit /set '{fwbootmgr}' displayorder '{bootmgr}' /addfirst | Out-Null
            Succes "  - Windows demarrera en priorite"
        } catch { Alerte "  - Reordonnancement du demarrage impossible (a faire dans le BIOS si besoin)" }
    } else {
        Ecrire "  Mode detecte : BIOS (ancien)"
        try {
            bootrec /fixmbr | Out-Null
            if ($LASTEXITCODE -eq 0) { Succes "  - Boot principal reecrit" } else { Erreur "  - Echec bootrec /fixmbr" }
        } catch { Erreur "  - Echec bootrec /fixmbr" }
        try {
            bootrec /fixboot | Out-Null
            if ($LASTEXITCODE -eq 0) { Succes "  - Boot de Windows reecrit" } else { Erreur "  - Echec bootrec /fixboot" }
        } catch { Erreur "  - Echec bootrec /fixboot" }
    }

    # --- Recuperation de l'espace libere ---
    Ecrire ""
    $reponse = Read-Host "Veux-tu recuperer l'espace libere pour Windows ? (OUI/NON)"
    if ($reponse -eq 'OUI') {
        Ecrire "Recuperation de l'espace..."
        $pC = Get-Partition -DriveLetter C
        try {
            $tailleMax = (Get-PartitionSupportedSize -DriveLetter C).SizeMax
            if ($tailleMax -gt $pC.Size) {
                Resize-Partition -DriveLetter C -Size $tailleMax -ErrorAction Stop
                $nouvelle = Get-Partition -DriveLetter C
                Succes ("  - C: agrandi : maintenant {0} Go" -f [math]::Round($nouvelle.Size / 1GB, 1))
            } else {
                Alerte "  - C: ne peut pas etre agrandi (l'espace libere est sur un autre disque)"
            }
        } catch {
            Erreur "  - Impossible d'agrandir C: : $($_.Exception.Message)"
        }
        foreach ($disque in @(Get-Disk)) {
            $tailleLibre = $disque.Size - $disque.AllocatedSize
            if ($tailleLibre -gt 5GB) {
                try {
                    $np = New-Partition -DiskNumber $disque.Number -UseMaximumSize -AssignDriveLetter -ErrorAction Stop
                    Format-Volume -Partition $np -FileSystem NTFS -Confirm:$false -ErrorAction Stop | Out-Null
                    Succes ("  - Nouveau compartiment cree : {0} Go (lettre {1})" -f [math]::Round($tailleLibre / 1GB, 1), $np.DriveLetter)
                } catch {
                    Erreur "  - Impossible de creer un nouveau compartiment : $($_.Exception.Message)"
                }
            }
        }
    }
}

# ============================================================
#  FLUX PRINCIPAL
# ============================================================

Ecrire "============================================================"
Ecrire "  OUTIL DE DESINSTALLATION DE FEDORA"
Ecrire "============================================================"
Ecrire ""
Ecrire "Cet outil va :"
Ecrire "  1. Afficher TOUS tes disques et leurs types"
Ecrire "  2. Reveiller le disque Fedora s'il est endormi"
Ecrire "  3. Te montrer les compartiments Fedora a supprimer"
Ecrire "  4. Les supprimer et reparer le demarrage de Windows"
Ecrire ""
Alerte "SECURITE : Windows (C:), la partition de demarrage et la"
Alerte "partition de recuperation ne seront JAMAIS touchees."
Alerte "Seules les partitions de type Linux (Fedora) sont visees."
Ecrire ""

# --- Verification de base : Windows doit etre sur C: ---
$partC = Get-Partition -DriveLetter C -ErrorAction SilentlyContinue
if (-not $partC) {
    Erreur "ERREUR : disque C: (Windows) introuvable."
    Erreur "Arret de l'outil pour des raisons de securite."
    Read-Host "Appuie sur Entree pour fermer"
    exit 1
}

# --- Diagnostic complet (toujours affiche) ---
Ecrire "Analyse des disques en cours..."
Afficher-Disques

# --- Reveiller les disques endormis ---
$offlines = @(Get-Disk | Where-Object { $_.IsOffline })
if ($offlines.Count -gt 0) {
    Ecrire ""
    Ecrire ("{0} disque(s) endormi(s) trouve(s) :" -f $offlines.Count)
    foreach ($d in $offlines) {
        Ecrire ("  - Disque {0} : {1}" -f $d.Number, $d.FriendlyName)
    }
    $rep = Read-Host "Veux-tu que je reveille ce(s) disque(s) pour les analyser ? (OUI/NON)"
    if ($rep -eq 'OUI') {
        foreach ($d in $offlines) {
            try {
                Set-Disk -Number $d.Number -IsOffline $false -ErrorAction Stop
                Succes ("  - Disque {0} reveille" -f $d.Number)
            } catch {
                Erreur ("  - Echec du reveil du disque {0} : {1}" -f $d.Number, $_.Exception.Message)
            }
        }
        Start-Sleep -Seconds 3
        Ecrire ""
        Ecrire "Re-analyse apres reveil..."
        Afficher-Disques
    } else {
        Alerte "Disques endormis ignores."
    }
}

# --- Analyse finale ---
$candidats = @(Analyser)

if ($candidats.Count -gt 0) {
    Supprimer-Fedora $candidats
} else {
    Erreur ""
    Erreur "============================================================"
    Erreur "  AUCUNE PARTITION FEDORA CONFIRMEE"
    Erreur "============================================================"
    Erreur ""
    Erreur "Le diagnostic complet est affiche ci-dessus."
    Erreur "Selectionne tout le texte (clic gauche, glisser) puis"
    Erreur "appuie sur Entree pour le copier, et envoie-le a"
    Erreur "l'assistant : il decidera quoi faire en toute securite."
    Erreur ""
    Erreur "Le journal est aussi dans : C:\desinstall_fedora_log.txt"
    Read-Host "Appuie sur Entree pour fermer"
    exit 1
}

# --- Fin ---
Ecrire ""
Succes "============================================================"
Succes "  TERMINE !"
Succes "============================================================"
Ecrire ""
Ecrire "Redemarre maintenant ton PC : Windows doit demarrer"
Ecrire "directement, sans le menu Fedora."
Ecrire ""
Ecrire "Si le PC affiche encore un menu au demarrage : choisis"
Ecrire "Windows. Pour enlever l'entree Fedora du menu, va dans"
Ecrire "le BIOS (F2/F10/Suppr) et mets Windows Boot Manager"
Ecrire "(ou le disque Windows) en premier."
Ecrire ""
Ecrire "Journal complet : C:\desinstall_fedora_log.txt"
Ecrire "Sauvegarde du demarrage : C:\bcd_backup.bcd"
Ecrire ""
try { Stop-Transcript | Out-Null } catch {}
Read-Host "Appuie sur Entree pour fermer"
