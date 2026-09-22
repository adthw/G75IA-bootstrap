# G75IA — Spécification technique du script automatisé `00-diagnostic.sh`
_Date : 2026-09-22_

_Version du document : 1.1 — alignée sur le script 0.2.0_
_Document complémentaire au « Protocole de diagnostic préalable d’une machine »_

---

## 1. Objet du document

Ce document décrit **la conception**, **le contenu** et **l’utilisation** du script `00-diagnostic.sh`.

Ce script constitue le point d’entrée automatisé du protocole G75IA pour toute nouvelle machine. Il ne doit ni installer Debian ni OpenClaw. Son rôle est de :

1. observer la machine ;
2. collecter les informations utiles ;
3. signaler les anomalies ;
4. produire un rapport humain ;
5. produire un rapport structuré exploitable par d’autres scripts ;
6. proposer un profil technique ;
7. ne modifier **aucun état important de la machine**.

Il doit pouvoir être exécuté depuis une **session Linux Live**, avant installation. Debian stable Live est l’environnement de référence ; Ubuntu LTS Live et les distributions apparentées sont des cibles compatibles attendues.

---

## 2. Principes de conception

### 2.1 Lecture seule par défaut

Le script est un outil d’observation. Il ne doit jamais :

```text
formater
partitionner
redimensionner
installer Debian
modifier le BIOS
modifier Secure Boot
écrire sur une partition Windows
activer/désactiver BitLocker
lancer un stress test lourd automatiquement
modifier les réglages CPU/GPU
installer un pilote propriétaire
mettre à jour un firmware
modifier les comptes utilisateurs
modifier UFW
modifier systemd
```

### 2.2 Tolérance aux environnements incomplets

Une session Linux Live peut ne pas contenir tous les outils. Le script doit donc détecter les commandes disponibles, marquer les données absentes `UNKNOWN`, continuer le diagnostic et ne jamais s’arrêter simplement parce qu’un outil manque.

Exemple :

```text
smartctl absent
→ stockage détecté
→ SMART marqué UNKNOWN
→ diagnostic continue
```

### 2.3 Ne jamais supposer un nom de périphérique

Le script ne doit jamais considérer que `/dev/sda` est obligatoirement le disque principal. Il doit découvrir automatiquement :

```text
/dev/sda
/dev/sdb
/dev/nvme0n1
/dev/mmcblk0
...
```

### 2.4 Séparer faits et interprétation

Le rapport doit distinguer :

```text
FACT
OK
WARN
CRITICAL
UNKNOWN
RECOMMENDATION
```

Exemple :

```text
FACT: RAM = <quantity>
FACT: CPU supports <instruction-set>
WARN: battery health below <threshold>
RECOMMENDATION: suitable for OpenClaw + small local LLM
```

### 2.5 Aucune décision irréversible automatique

Le script peut proposer « Dual boot plausible », « SSD à remplacer avant installation » ou « 16 Go RAM recommandés », mais il ne doit jamais lancer une action d’installation à partir de cette conclusion. La décision finale reste humaine.

---

## 3. Mode d’exécution

Depuis une session Linux Live compatible :

```bash
chmod +x 00-diagnostic.sh
sudo ./00-diagnostic.sh
```

`sudo` est recommandé parce que certaines informations nécessitent des privilèges de lecture : `dmidecode`, SMART, certains logs noyau, certaines informations firmware ou batterie.

Le script doit rester **non destructif même lorsqu’il est exécuté en root**.

Au lancement, il affiche :

```text
G75IA MACHINE DIAGNOSTIC
------------------------
Mode : lecture seule
Aucune partition ne sera modifiée.
Aucun système de fichiers ne sera formaté.
Aucune partition Windows ne sera montée en écriture.
Aucun firmware ne sera modifié.
```

Puis une seule confirmation générale :

```text
Continuer le diagnostic en lecture seule ? [O/n]
```

---

## 4. Arborescence du projet

Le futur kit pourra être organisé ainsi :

```text
g75ia-bootstrap/
├── 00-diagnostic.sh
├── lib/
│   ├── common.sh
│   ├── privacy.sh
│   ├── scoring.sh
│   └── json.sh
├── diagnostics/
│   ├── system.sh
│   ├── cpu.sh
│   ├── memory.sh
│   ├── gpu.sh
│   ├── storage.sh
│   ├── network.sh
│   ├── power.sh
│   ├── thermal.sh
│   ├── kernel.sh
│   └── ai-profile.sh
├── reports/
└── README.md
```

Pour la première version, tout peut rester dans un seul fichier `00-diagnostic.sh`. La modularisation viendra ensuite.

---

## 5. Architecture interne du script

Le script doit être organisé en fonctions :

```bash
main()
check_environment()
create_report_dir()
detect_system()
detect_firmware()
detect_cpu()
detect_memory()
detect_gpu()
detect_storage()
detect_windows()
detect_network()
detect_audio()
detect_bluetooth()
detect_battery()
detect_thermal()
detect_virtualization()
inspect_kernel_logs()
evaluate_ai_profile()
evaluate_debian_compatibility()
evaluate_installation_strategy()
generate_text_report()
generate_json_report()
generate_summary()
```

Le programme principal appelle les fonctions dans cet ordre.

### 5.1 Détection d’une commande

```bash
has_cmd() {
    command -v "$1" >/dev/null 2>&1
}
```

Utilisation :

```bash
if has_cmd smartctl; then
    ...
else
    mark_unknown "SMART" "smartctl absent"
fi
```

### 5.2 Exécution protégée

```bash
run_safe() {
    "$@" 2>>"$ERROR_LOG" || return 1
}
```

Le script principal ne doit pas utiliser `set -e` de manière aveugle. Une commande manquante ou un périphérique atypique ne doit pas interrompre tout le rapport.

---

## 6. Répertoire de rapport

Chaque exécution crée un dossier unique :

```text
reports/
└── 2026-09-22_113000_machine.a1B2c3/
    ├── machine-report.txt
    ├── machine-report.json
    ├── summary.txt
    ├── SHA256SUMS
    ├── raw/
    │   ├── lscpu.txt
    │   ├── dmidecode-system.txt
    │   ├── dmidecode-memory.txt
    │   ├── lsblk.txt
    │   ├── smart-sda.txt
    │   ├── smart-nvme0.txt
    │   ├── lspci.txt
    │   ├── dmesg-filtered.txt
    │   └── sensors.txt
    └── errors.log
```

Le suffixe aléatoire est créé atomiquement par `mktemp`. Il évite de réutiliser un ancien dossier ou de suivre un fichier préparé à l’avance lorsque le script est lancé avec `sudo`. Le dossier et ses fichiers sont privés grâce à `umask 077`.

Les sorties brutes servent à permettre une analyse humaine ultérieure.

---

## 7. Protection des données privées

Le rapport partageable ne doit pas contenir automatiquement :

```text
numéro de série complet
UUID machine
UUID partitions
adresse MAC
SSID Wi-Fi
IP publique
token
mot de passe
clé Wi-Fi
clé BitLocker
OAuth
secret OpenClaw
```

L’anonymisation est obligatoire dans toutes les sorties, y compris `raw/`. Aucun argument de ligne de commande ne permet de la désactiver. Les rapports ne sont jamais envoyés automatiquement sur le réseau.

Le filtrage couvre notamment les adresses MAC, IPv4 et IPv6, UUID, principaux numéros de série et WWN, chemins personnels sous `/home`, UID d’exécution et affectations usuelles de secrets. Il s’agit d’une défense en profondeur : l’utilisateur doit toujours relire un rapport avant de le partager.

Exemple de masquage :

```text
Serial Number: <identifier>
```

devient :

```text
Serial Number: [REDACTED]
```

---

## 8. Module SYSTEM

Collecter :

```bash
uname -srm
cat /etc/os-release
```

Depuis un environnement Linux Live, noter explicitement que le système observé est le Live et non le futur système installé.

La détection doit reconnaître au minimum les marqueurs usuels suivants lorsqu’ils sont présents :

```text
boot=live        Debian et dérivées utilisant live-boot
boot=casper      Ubuntu et dérivées
rd.live.image    Fedora et autres environnements dracut
archisobasedir=  Arch ISO
/run/live
/run/archiso
/rofs
/cdrom/casper
```

L’absence de ces marqueurs ne prouve pas que le système n’est pas Live ; elle impose seulement une revue manuelle.

Exemple JSON :

```json
{
  "live_environment": true,
  "kernel": "6.x",
  "architecture": "x86_64"
}
```

---

## 9. Module FIRMWARE

Commandes :

```bash
dmidecode -t system
dmidecode -t baseboard
dmidecode -t bios
```

Mode de boot :

```bash
test -d /sys/firmware/efi
```

Secure Boot :

```bash
mokutil --sb-state
```

TPM :

```bash
ls /dev/tpm*
```

Exemple JSON :

```json
{
  "firmware": {
    "boot_mode": "UEFI",
    "bios_vendor": "Example",
    "bios_version": "1.23",
    "secure_boot": "enabled",
    "tpm_present": true
  }
}
```

---

## 10. Module CPU

Commande principale :

```bash
lscpu
```

Extraire :

```text
model
architecture
cores
threads
sockets
avx
avx2
avx512
virtualization
```

Exemple JSON :

```json
{
  "cpu": {
    "model": "Intel Core i7 ...",
    "cores": 6,
    "threads": 12,
    "avx": true,
    "avx2": true,
    "avx512": false,
    "virtualization": "VT-x"
  }
}
```

---

## 11. Module RAM

Commandes :

```bash
free -b
dmidecode -t memory
```

Distinguer :

```text
RAM installée
RAM visible
slots physiques
slots utilisés
capacité maximale si firmware la fournit
```

Exemple JSON :

```json
{
  "memory": {
    "total_gib": 16,
    "slots_total": 2,
    "slots_used": 2,
    "type": "DDR4",
    "speed_mt_s": 3200
  }
}
```

---

## 12. Module GPU

Détection principale :

```bash
lspci -nnk
```

Chercher les classes `VGA`, `3D` et `Display`.

Le script doit supporter plusieurs GPU.

Si `nvidia-smi` fonctionne, récupérer VRAM, température, version du pilote et version CUDA annoncée. Son absence ne doit pas être interprétée comme une panne : le pilote propriétaire peut simplement être absent du Live.

Pour AMD et Intel, relever le modèle et le pilote actif afin d’évaluer ensuite ROCm, OpenVINO, oneAPI ou NPU éventuel.

---

## 13. Module stockage

Découvrir les disques avec la sortie JSON native de `lsblk` :

```bash
lsblk -J -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS,MODEL,SERIAL,ROTA,TRAN
```

Pour chaque disque physique :

```text
type
taille
modèle
transport
HDD/SSD/NVMe
partitions
```

Ne jamais supposer `/dev/sda`.

---

## 14. Module SMART

Pour chaque disque SATA :

```bash
smartctl -a -j /dev/sdX
```

Pour NVMe :

```bash
smartctl -a -j /dev/nvme0
```

ou :

```bash
nvme smart-log -o json /dev/nvme0
```

Le script conserve les valeurs brutes et produit un statut :

```text
OK
WARN
CRITICAL
UNKNOWN
```

Exemples :

```text
overall SMART failed          → CRITICAL
critical_warning NVMe != 0    → CRITICAL
media_errors > 0              → WARN/CRITICAL selon contexte
reallocated sectors > 0       → WARN
pending sectors > 0           → WARN
outil absent                  → UNKNOWN
```

---

## 15. Module partitions / Windows

À partir de `lsblk -J` et `blkid`, rechercher :

```text
NTFS
VFAT/EFI
Microsoft Reserved
Recovery
BitLocker éventuel
```

Le script ne doit jamais monter une partition Windows pour simplement l’identifier.

Il doit produire une carte logique des disques et partitions.

Exemple JSON :

```json
{
  "windows_candidate": true,
  "mounted": false,
  "read_only_policy": true
}
```

---

## 16. Module réseau

Collecter :

```bash
ip -j link
ip -j address
lspci -nnk
lsusb
nmcli device
rfkill list
```

Le rapport partageable masque les MAC.

Le script indique : Ethernet présent, Wi-Fi présent, Bluetooth présent, driver actif et interface connectée ou non.

---

## 17. Audio, webcam et USB

Commandes :

```bash
aplay -l
ls /dev/video*
lsusb
```

Ces éléments ne doivent pas bloquer l’installation s’ils sont absents, sauf besoin spécifique.

---

## 18. Batterie et alimentation

Sources :

```text
upower
/sys/class/power_supply
```

Extraire : présence, pourcentage, capacité d’origine, capacité actuelle, cycles, charge/décharge.

La santé peut être estimée si les données existent :

```text
energy-full / energy-full-design × 100
```

---

## 19. Module thermique

Utiliser :

```bash
sensors
```

et éventuellement `/sys/class/thermal`.

Le script collecte seulement l’état courant : CPU, GPU, SSD/NVMe, ventilateurs si disponibles.

Il ne déclenche **aucun stress test**.

Si aucune sonde n’est exposée : `UNKNOWN`, pas `FAIL`.

---

## 20. Logs noyau

Conserver `dmesg -T` dans les sorties brutes et filtrer :

```text
thermal
mce
edac
nvme
ata
firmware
acpi
gpu
nouveau
amdgpu
i915
error
fail
fault
```

Le résumé ne remonte que les événements potentiellement significatifs.

---

## 21. Virtualisation

Détecter :

```text
VT-x
AMD-V
KVM
IOMMU éventuel
```

Commandes :

```bash
lscpu
lsmod | grep kvm
dmesg | grep -Ei 'iommu|dmar'
```

---

## 22. Moteur de statut

Chaque contrôle renvoie :

```text
OK       → comportement attendu
WARN     → point à examiner mais pas nécessairement bloquant
CRITICAL → risque suffisant pour arrêter l’installation
UNKNOWN  → donnée non disponible
INFO     → observation sans jugement
```

Exemple :

```text
[OK]       UEFI détecté
[OK]       16 GiB RAM
[WARN]     Batterie à 58 % de capacité
[UNKNOWN]  SMART non disponible
[CRITICAL] NVMe critical_warning = 1
```

---

## 23. Profil G75IA

Le script produit des appréciations descriptives plutôt qu’un score artificiel :

```text
OpenClaw host           : suitable
Local small LLM         : suitable
Local 7B quantized      : possible
GPU acceleration        : uncertain
Windows dual boot       : possible
Immediate installation  : yes
```

Éviter les scores arbitraires du type `82/100`.

---

## 24. Évaluation IA locale

Le moteur combine RAM, CPU, AVX/AVX2, GPU, VRAM et stockage.

Exemple de logique indicative :

```bash
if RAM >= 32 GiB and VRAM >= 8 GiB:
    profile="local-ai-strong"
elif RAM >= 16 GiB and AVX2:
    profile="local-ai-medium"
elif RAM >= 8 GiB:
    profile="local-ai-light"
else:
    profile="cloud-oriented"
fi
```

La conclusion doit toujours être accompagnée des faits matériels.

---

## 25. Évaluation Debian

Le script ne garantit pas une compatibilité absolue. Il produit une matrice :

```text
boot        OK
display     OK
storage     OK
wifi        OK
ethernet    OK
audio       UNKNOWN
bluetooth   OK
suspend     NOT TESTED
```

Résultat global possible :

```text
compatible
compatible-with-reservations
manual-review
```

---

## 26. Proposition de stratégie d’installation

Le script peut proposer :

```text
Debian seul
Dual boot
Second disque
Installation à suspendre
Sauvegarde obligatoire avant continuation
```

Exemple :

```text
Detected:
- Windows 11
- EFI partition
- NVMe healthy
- 420 GiB free inside Windows partition

Suggested strategy:
Dual boot possible.
Shrink Windows from Windows itself.
Reuse existing EFI partition without formatting.
Human confirmation required.
```

---

## 27. Format `machine-report.txt`

Exemple :

```text
G75IA MACHINE REPORT
====================

Machine
-------
<manufacturer> <model>
UEFI: yes
Secure Boot: enabled

CPU
---
<CPU model>
<cores> cores / <threads> threads
AVX2: yes

Memory
------
<quantity> <memory type>
<used>/<total> slots used

Storage
-------
<storage type> <model>
SMART: OK

Operating systems
-----------------
Windows detected
EFI detected

Network
-------
Ethernet: OK
Wi-Fi: OK

Thermals
--------
CPU idle: <temperature>
Storage: <temperature>

G75IA profile
-------------
OpenClaw: suitable
Local small model: suitable
Local 7B: possible
GPU inference: to evaluate

Installation
------------
Suggested: Windows + Debian dual boot
Blocking issue: none
```

---

## 28. Format `machine-report.json`

Structure prévue :

```json
{
  "schema_version": "1.0",
  "generated_at": "2026-09-22T11:30:00+02:00",
  "diagnostic_mode": "read-only",
  "machine": {},
  "firmware": {},
  "cpu": {},
  "memory": {},
  "gpus": [],
  "storage": [],
  "partitions": [],
  "network": {},
  "audio": {},
  "bluetooth": {},
  "battery": {},
  "thermal": {},
  "virtualization": {},
  "kernel_findings": [],
  "statuses": [],
  "g75ia_profile": {},
  "installation_recommendation": {},
  "privacy": {
    "serials_redacted": true,
    "mac_addresses_redacted": true
  }
}
```

Le JSON doit rester valide même si certaines sections sont inconnues.

---

## 29. Dépendances

Le script détecte :

```text
bash
coreutils
util-linux
procps
iproute2
pciutils
usbutils
dmidecode
smartmontools
lm-sensors
network-manager
upower
mokutil
nvme-cli
jq
```

Minimum pratique : `bash`, `lsblk`, `lscpu`, `ip`.

Les autres outils sont optionnels. Le script continue sans eux.

Par défaut il **n’installe rien**. Il peut seulement afficher les outils manquants et les commandes suggérées pour enrichir le diagnostic.

---

## 30. Options prévues

Version initiale :

```bash
sudo ./00-diagnostic.sh
```

Évolutions possibles :

```bash
sudo ./00-diagnostic.sh --quick
sudo ./00-diagnostic.sh --full
sudo ./00-diagnostic.sh --json-only
sudo ./00-diagnostic.sh --no-network
sudo ./00-diagnostic.sh --output /media/user/USB
```

---

## 31. Codes de retour

Proposition :

```text
0  diagnostic terminé, aucun blocage critique
1  diagnostic terminé avec warnings
2  anomalie critique détectée
3  erreur interne du script
4  environnement insuffisant
```

Le rapport doit être généré même en présence de warnings ou d’un état critique.

---

## 32. Journal des erreurs

Toutes les erreurs de commande sont consignées dans `errors.log`.

Exemple :

```text
2026-09-22T11:32:04 smartctl /dev/nvme0 : command not found
```

Le rapport final pourra dire :

```text
SMART NVMe: UNKNOWN (outil absent)
```

---

## 33. Tests avant utilisation réelle

### 33.1 Sur une machine de référence interne

Comparer automatiquement les résultats avec une fiche de référence conservée hors du dépôt public. La fiche de test ne doit contenir aucun secret et ne doit jamais être ajoutée à Git.

### 33.2 Sur VM

Tester : absence de crash, JSON valide, périphériques absents, absence de batterie, disque virtuel.

### 33.3 Audit de non-destruction

```bash
grep -En 'mkfs|fdisk|parted|wipefs|dd .*of=/dev|rm -rf|mount .*rw' 00-diagnostic.sh
```

Toute commande potentiellement destructive doit être absente.

---

## 34. Vérification du JSON

Si `jq` est disponible :

```bash
jq empty machine-report.json
```

Le test doit réussir avant de déclarer le rapport terminé.

---

## 35. Empreinte du rapport

À la fin :

```bash
sha256sum machine-report.txt machine-report.json > SHA256SUMS
```

Cela permet de vérifier ultérieurement qu’un rapport n’a pas été modifié.

---

## 36. Utilisation avec ChatGPT / OpenClaw

Pour une analyse humaine ou conversationnelle :

```text
machine-report.txt
```

Pour automatiser :

```text
machine-report.json
```

Le JSON pourra être lu par un futur `install.sh`, mais celui-ci devra encore demander validation humaine avant partitionnement, installation, activation de services ou modification de sécurité.

---

## 37. Relation avec le futur bootstrap

```text
00-diagnostic.sh
        ↓
machine-report.json
        ↓
validation humaine
        ↓
install.sh
        ↓
Debian configuré
        ↓
OpenClaw bootstrap
        ↓
08-audit.sh
```

Le diagnostic ne déclenche jamais directement l’installation.

---

## 38. Exemple d’exécution complète

```text
[1/15] Environnement ............... OK
[2/15] Firmware .................... OK
[3/15] CPU ......................... OK
[4/15] Mémoire ..................... OK
[5/15] GPU ......................... OK
[6/15] Stockage .................... OK
[7/15] SMART ....................... OK
[8/15] Windows / partitions ........ OK
[9/15] Réseau ...................... OK
[10/15] Batterie ................... WARN
[11/15] Thermique .................. OK
[12/15] Logs noyau ................. OK
[13/15] Virtualisation ............. OK
[14/15] Profil G75IA ............... DONE
[15/15] Rapports ................... DONE
```

Résumé :

```text
- Aucun problème bloquant détecté.
- Batterie : état à examiner.
- Système existant détecté.
- Stockage sain.
- RAM : capacité détectée.
- Jeu d’instructions CPU détecté.
- GPU détecté.

Profil G75IA:
OpenClaw                : recommandé
Petit modèle local      : recommandé
Modèle 7B quantifié     : à tester
Accélération GPU        : à confirmer après pilote NVIDIA

Installation:
Dual boot Debian possible.
Aucune modification n’a été effectuée.
```

---

## 39. Ce que la version 1.0 NE fera PAS

```text
benchmark CPU
benchmark GPU
stress Prime95
stress FurMark
Memtest long
benchmark disque en écriture
installation Debian
partitionnement
installation pilote NVIDIA
installation OpenClaw
mise à jour BIOS
modification Secure Boot
configuration réseau
réparation automatique
```

---

## 40. Première implémentation recommandée

Construire d’abord une seule version Bash :

```text
00-diagnostic.sh
```

avec des fonctions simples, aucune dépendance Python, JSON via `jq` si disponible, et fallback texte si `jq` manque.

Avantages : fonctionne dans un environnement Linux Live compatible, reste facilement auditable et copiable sur clé USB, sans runtime supplémentaire.

Une version Python pourra venir plus tard si le traitement du JSON ou du matériel devient trop complexe.

---

## 41. Critères de réussite

```text
[ ] fonctionne depuis Debian Live
[ ] fonctionne depuis Ubuntu LTS Live
[ ] continue proprement sur une distribution Linux Live non dérivée de Debian lorsque des outils manquent
[ ] ne modifie aucun disque
[ ] fonctionne sur SATA et NVMe
[ ] supporte plusieurs disques
[ ] supporte plusieurs GPU
[ ] continue si un outil manque
[ ] produit un TXT lisible
[ ] produit un JSON valide
[ ] masque les identifiants sensibles
[ ] détecte Windows sans le monter
[ ] récupère SMART quand disponible
[ ] récupère températures quand disponibles
[ ] produit OK/WARN/CRITICAL/UNKNOWN
[ ] propose un profil G75IA
[ ] propose une stratégie d’installation
[ ] laisse la décision finale à l’humain
[ ] produit une empreinte SHA-256
```

---

## 42. Résumé architectural

```text
                 ┌─────────────────┐
                 │   Linux Live    │
                 └────────┬────────┘
                          │
                 00-diagnostic.sh
                          │
         ┌────────────────┼────────────────┐
         │                │                │
      Matériel         Santé          Compatibilité
         │                │                │
         └────────────────┼────────────────┘
                          │
                 Analyse non destructive
                          │
             ┌────────────┴────────────┐
             │                         │
     machine-report.txt        machine-report.json
             │                         │
        lecture humaine          automatisation
             │                         │
             └────────────┬────────────┘
                          │
                  validation humaine
                          │
                          ▼
                 installation Debian
```

Principe central :

> **Observer d’abord, décider ensuite, modifier seulement après validation humaine.**

Ce document constitue la spécification technique de référence pour l’implémentation du futur `00-diagnostic.sh`.
