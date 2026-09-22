# G75IA — Protocole de diagnostic préalable d’une machine
_Date : 2026-09-22_

_Version : 1.0_
_Objectif : qualifier une machine avant toute installation Debian / OpenClaw_

## 0. Principe général

Le diagnostic doit être réalisé **avant toute modification du disque** et, si possible, depuis une **session Linux Live compatible**. Debian stable Live constitue l’environnement de référence, mais Ubuntu Live et les distributions apparentées peuvent également être utilisées.

Le protocole poursuit quatre objectifs :

1. Identifier précisément le matériel.
2. Vérifier l’état de santé de la machine.
3. Déterminer la meilleure stratégie d’installation Debian.
4. Évaluer le potentiel G75IA / OpenClaw / IA locale.

### Règle de sécurité principale

Le diagnostic pré-installation est **en lecture seule**.

Pendant cette phase :

- ne pas formater ;
- ne pas repartitionner ;
- ne pas monter en écriture les partitions Windows ;
- ne pas lancer de test destructif SMART ;
- ne pas mettre à jour le BIOS ;
- ne pas modifier Secure Boot ;
- ne pas écrire sur les disques internes sauf décision humaine explicite ;
- ne pas lancer de stress test lourd tant que les températures de base ne sont pas connues.

L’objectif est d’abord de comprendre la machine.

---

# PHASE 1 — Préparation

## 1.1 Matériel nécessaire

Prévoir :

- la machine à diagnostiquer ;
- son alimentation secteur ;
- une clé USB Linux Live compatible ;
- éventuellement un câble Ethernet ;
- éventuellement une seconde clé USB pour sauvegarder les rapports ;
- accès Internet facultatif mais utile.

## 1.2 Démarrer sur Linux Live

Utiliser de préférence une image Debian stable Live avec Xfce. Ubuntu LTS en mode « Try Ubuntu », Linux Mint, Pop!_OS et les autres dérivées Debian/Ubuntu sont également des environnements adaptés.

Fedora, openSUSE, Arch et leurs dérivées peuvent être utilisées à titre expérimental. Le script doit continuer si un outil manque, mais certaines données seront alors marquées `UNKNOWN`.

Le protocole ne prend pas en charge une exécution directe depuis Windows, macOS ou BSD.

Au démarrage :

- choisir le mode Live ;
- ne pas lancer l’installateur immédiatement ;
- vérifier que clavier, écran et réseau fonctionnent.

Si nécessaire pour un clavier français :

```bash
setxkbmap fr
```

## 1.3 Créer un répertoire de rapport

```bash
mkdir -p ~/g75ia-diagnostic
cd ~/g75ia-diagnostic
```

---

# PHASE 2 — Identification générale

## 2.1 Fabricant et modèle

```bash
sudo dmidecode -t system
```

Relever :

- fabricant ;
- nom du produit ;
- version ;
- numéro de série si utile ;
- UUID système.

Pour un rapport partageable, **masquer les numéros de série si le document sort de la machine**.

Commande synthétique :

```bash
sudo dmidecode -s system-manufacturer
sudo dmidecode -s system-product-name
sudo dmidecode -s system-version
```

## 2.2 Carte mère

```bash
sudo dmidecode -t baseboard
```

## 2.3 BIOS / UEFI

```bash
sudo dmidecode -t bios
```

Vérifier le mode de démarrage :

```bash
[ -d /sys/firmware/efi ] && echo "UEFI" || echo "Legacy BIOS"
```

Vérifier Secure Boot :

```bash
mokutil --sb-state 2>/dev/null || true
```

Ne rien modifier à ce stade.

---

# PHASE 3 — CPU

## 3.1 Identification

```bash
lscpu
```

Relever :

- modèle exact ;
- architecture ;
- sockets ;
- cœurs ;
- threads ;
- fréquences ;
- cache ;
- hyper-threading/SMT ;
- virtualisation ;
- flags CPU.

Commande courte :

```bash
grep -m1 "model name" /proc/cpuinfo
nproc
```

## 3.2 Capacités utiles pour IA locale

```bash
lscpu | grep -E 'avx|avx2|avx512|sse4|vmx|svm'
```

À noter :

- AVX : utile pour de nombreux runtimes ;
- AVX2 : améliore fortement les performances CPU ;
- AVX-512 : bonus éventuel sur certains CPU ;
- vmx / svm : virtualisation Intel / AMD.

---

# PHASE 4 — RAM

## 4.1 Quantité disponible

```bash
free -h
```

## 4.2 Barrettes et slots

```bash
sudo dmidecode -t memory
```

Relever :

- quantité totale ;
- nombre de slots ;
- slots occupés ;
- capacité de chaque barrette ;
- type DDR ;
- fréquence ;
- fabricant ;
- référence.

## 4.3 Classification indicative G75IA

```text
4 Go     → très limité
8 Go     → minimum réaliste pour OpenClaw + Debian léger
16 Go    → confortable pour OpenClaw + petits modèles locaux
32 Go    → très bon pour petits/moyens modèles quantifiés
64 Go+   → potentiel IA locale nettement supérieur
```

---

# PHASE 5 — GPU

## 5.1 Détection

```bash
lspci -nnk | grep -EA3 'VGA|3D|Display'
```

Relever :

- GPU intégré ;
- GPU dédié ;
- pilote utilisé ;
- pilote disponible.

## 5.2 Vérification OpenGL

```bash
glxinfo -B
```

Relever :

- direct rendering ;
- renderer ;
- version OpenGL ;
- mémoire vidéo si affichée.

## 5.3 NVIDIA

```bash
nvidia-smi
```

Si la commande n’existe pas, cela peut simplement signifier que le pilote propriétaire n’est pas présent dans le Live.

## 5.4 AMD

Identifier précisément le modèle et le pilote actif. Le potentiel ROCm sera évalué après identification.

## 5.5 Intel

Noter le modèle exact afin d’évaluer ensuite OpenVINO, oneAPI et les éventuelles capacités NPU.

---

# PHASE 6 — Stockage

## 6.1 Inventaire

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,FSVER,LABEL,UUID,MOUNTPOINTS,MODEL
```

Puis :

```bash
sudo fdisk -l
```

Relever :

- nombre de disques ;
- SATA / NVMe / USB ;
- taille ;
- partitions ;
- systèmes de fichiers ;
- partitions EFI ;
- partitions Windows ;
- partitions Recovery ;
- espace non alloué.

## 6.2 SSD / HDD / NVMe

```bash
lsblk -d -o NAME,ROTA,TRAN,SIZE,MODEL
```

Interprétation :

```text
ROTA=1 → disque mécanique
ROTA=0 → SSD/NVMe
```

## 6.3 SMART SATA

```bash
sudo smartctl -a /dev/sda
```

Adapter le périphérique.

Relever :

- overall-health ;
- heures de fonctionnement ;
- power cycles ;
- secteurs réalloués ;
- secteurs instables ;
- erreurs non corrigibles ;
- CRC ;
- température ;
- usure SSD si disponible.

## 6.4 SMART NVMe

```bash
sudo smartctl -a /dev/nvme0
```

ou :

```bash
sudo nvme smart-log /dev/nvme0
```

Relever :

- percentage used ;
- media errors ;
- available spare ;
- critical warning ;
- température ;
- data units written ;
- power-on hours.

## 6.5 Tests interdits à cette étape

Ne pas lancer automatiquement :

```text
smartctl -t long
badblocks -w
fio avec écriture
hdparm --security-*
fsck en écriture
```

---

# PHASE 7 — Windows et dual boot

## 7.1 Identifier les partitions Windows

```bash
lsblk -f
```

ou :

```bash
sudo blkid
```

## 7.2 Ne pas monter Windows en écriture

Vérifier :

```bash
mount | grep -i ntfs
```

Si nécessaire :

```bash
sudo umount /dev/sdXN
```

## 7.3 Vérifier l’ESP

```bash
lsblk -f | grep -i vfat
```

En dual boot UEFI, l’ESP existante sera généralement réutilisée **sans formatage**.

## 7.4 Vérifications à faire sous Windows avant installation

- désactiver Fast Startup ;
- désactiver l’hibernation : `powercfg /h off` ;
- vérifier BitLocker ;
- sauvegarder les données importantes ;
- réduire la partition Windows depuis Windows si possible.

---

# PHASE 8 — TPM et chiffrement

## 8.1 TPM

```bash
ls /dev/tpm* 2>/dev/null
dmesg | grep -i tpm
```

Si disponible :

```bash
tpm2_getcap properties-fixed
```

## 8.2 BitLocker

La présence d’une partition NTFS ne suffit pas à conclure que BitLocker est actif.

La vérification finale doit être faite depuis Windows.

---

# PHASE 9 — Réseau

## 9.1 Interfaces

```bash
ip -brief link
ip -brief address
```

## 9.2 PCI réseau

```bash
lspci -nnk | grep -EA3 'Ethernet|Network'
```

## 9.3 USB réseau

```bash
lsusb
```

## 9.4 Wi-Fi

```bash
iw dev 2>/dev/null
```

ou :

```bash
nmcli device
```

## 9.5 Test Internet

```bash
ping -c 3 1.1.1.1
ping -c 3 debian.org
```

---

# PHASE 10 — Audio, Bluetooth, webcam et USB

## 10.1 Audio

```bash
aplay -l 2>/dev/null
lspci | grep -i audio
```

## 10.2 Bluetooth

```bash
lsusb | grep -i bluetooth
rfkill list
```

## 10.3 Webcam

```bash
ls /dev/video* 2>/dev/null
```

## 10.4 USB

```bash
lsusb
```

Tester physiquement au moins un port USB si la machine doit être utilisée comme station autonome.

---

# PHASE 11 — Écran et graphique

## 11.1 Résolution

```bash
xrandr
```

Relever :

- résolution native ;
- fréquence ;
- sorties.

## 11.2 Multi-GPU

```bash
lspci | grep -Ei 'VGA|3D|Display'
```

Ne pas reconfigurer Optimus ou les pilotes pendant ce diagnostic.

---

# PHASE 12 — Batterie et alimentation

## 12.1 Batterie

```bash
upower -e | grep BAT
```

Puis :

```bash
upower -i $(upower -e | grep BAT | head -1)
```

Relever :

- capacité actuelle ;
- capacité d’origine ;
- état ;
- cycles si disponibles.

## 12.2 Secteur

```bash
cat /sys/class/power_supply/AC*/online 2>/dev/null
```

---

# PHASE 13 — Températures et ventilation

## 13.1 Capteurs

```bash
sudo sensors-detect --auto
sensors
```

Relever au repos :

- CPU ;
- GPU ;
- SSD/NVMe ;
- ventilateurs si exposés.

## 13.2 Repos thermique

Laisser tourner la machine 5 à 10 minutes sans charge lourde avant de noter les valeurs.

## 13.3 Stress test

Ne lancer un stress test que si :

- le refroidissement paraît normal ;
- les ventilateurs fonctionnent ;
- les températures au repos sont correctes ;
- la machine est sur secteur.

Le stress lourd ne fait pas partie du premier diagnostic automatisé.

---

# PHASE 14 — Logs noyau

## 14.1 Erreurs générales

```bash
dmesg -T | grep -Ei 'error|fail|fault|warn|thermal|mce|edac|nvme|ata'
```

## 14.2 Firmware / PCI / ACPI

```bash
dmesg -T | grep -Ei 'firmware|pci|acpi'
```

## 14.3 CPU / mémoire

```bash
dmesg -T | grep -Ei 'mce|machine check|edac'
```

---

# PHASE 15 — Virtualisation

## 15.1 Support CPU

```bash
lscpu | grep -i virtualization
```

## 15.2 KVM

```bash
lsmod | grep kvm
```

La virtualisation pourra être utile pour Docker/Podman, VM et sandbox avancée.

---

# PHASE 16 — Évaluation IA locale

## Profil A — OpenClaw distant principalement

Typiquement :

```text
RAM ≤ 8 Go
CPU ancien
pas de GPU IA exploitable
```

Usage :

- OpenClaw ;
- modèles cloud ;
- petits outils locaux ;
- petit modèle local éventuel < 2B.

## Profil B — Petit modèle local

Typiquement :

```text
8–16 Go RAM
CPU AVX/AVX2
pas de GPU majeur
```

Usage :

- llama.cpp ;
- Qwen 0.5B–3B ;
- modèles quantifiés ;
- routage local ;
- tâches privées légères.

## Profil C — IA locale intermédiaire

Typiquement :

```text
16–32 Go RAM
CPU moderne AVX2
GPU 6–12 Go VRAM ou bon iGPU
```

Usage :

- modèles 3B–8B quantifiés ;
- embeddings ;
- vision légère ;
- transcription ;
- agents locaux plus autonomes.

## Profil D — Station IA locale forte

Typiquement :

```text
32–64 Go+ RAM
GPU récent avec VRAM importante
NVMe
CPU moderne
```

Usage :

- modèles plus lourds ;
- services locaux multiples ;
- RAG ;
- vision ;
- audio ;
- orchestration multi-modèles.

Cette classification est indicative.

---

# PHASE 17 — Évaluation Debian

À la fin du diagnostic, décider :

```text
Debian compatible : oui / non / avec réserves
```

Vérifier :

- UEFI ;
- clavier ;
- affichage ;
- Wi-Fi ;
- Ethernet ;
- audio ;
- veille/réveil si important ;
- GPU ;
- stockage ;
- température ;
- batterie ;
- périphériques essentiels.

---

# PHASE 18 — Décision de partitionnement

Aucune modification n’est effectuée à cette étape.

Le rapport doit proposer :

```text
A. Debian seul
B. Dual boot Windows + Debian
C. Debian sur second disque
D. Installation différée à cause d’un risque disque
E. Sauvegarde préalable obligatoire
```

Pour un dual boot, documenter :

- partition Windows actuelle ;
- espace utilisé ;
- espace libre ;
- espace à libérer ;
- ESP existante ;
- Recovery ;
- BitLocker éventuel ;
- réserve souhaitée.

---

# PHASE 19 — Rapport de diagnostic

Produire idéalement :

```text
machine-report.txt
machine-report.json
```

Le `.txt` est destiné à l’humain.

Le `.json` pourra être exploité par le futur bootstrap G75IA.

## Contenu minimal

```text
IDENTITE MACHINE
- fabricant
- modèle
- BIOS/UEFI
- Secure Boot

CPU
- modèle
- cœurs/threads
- AVX/AVX2/AVX512
- virtualisation

RAM
- quantité
- type
- slots occupés/libres

GPU
- modèle(s)
- VRAM
- pilote
- potentiel CUDA/ROCm/OpenVINO

STOCKAGE
- modèle
- type
- taille
- SMART
- partitions
- Windows
- espace disponible

RESEAU
- Wi-Fi
- Ethernet
- Bluetooth

ENERGIE
- batterie
- alimentation

THERMIQUE
- températures repos
- ventilateurs

DEBIAN
- matériel fonctionnel
- anomalies
- firmwares manquants

POTENTIEL G75IA
- OpenClaw
- modèle local
- upgrades recommandés

SECURITE
- UEFI/Secure Boot
- TPM
- BitLocker potentiel
- contraintes dual boot

DECISION
- stratégie d’installation recommandée
```

---

# PHASE 20 — Sauvegarde du rapport

Avant installation, copier les rapports hors du disque interne.

Même anonymisé automatiquement, un rapport matériel peut révéler une cartographie technique imprévue. Avant toute transmission ou publication :

1. relire `summary.txt`, `machine-report.txt`, `machine-report.json` et les fichiers utiles de `raw/` ;
2. rechercher les noms d’utilisateur, noms de machine, adresses réseau, numéros de série, UUID, labels personnels, chemins privés, jetons et secrets ;
3. ne partager que les fichiers strictement nécessaires ;
4. ne jamais ajouter le dossier `reports/` à Git.

Exemple :

```bash
cp machine-report.* /media/user/USB/
sync
```

Ne jamais dépendre d’un rapport stocké uniquement dans la session Live.

---

# PHASE 21 — Critères d’arrêt

Arrêter le processus d’installation si l’un des cas suivants apparaît :

```text
SMART critique
secteurs réalloués/instables en forte progression
NVMe en état critique
températures anormalement élevées au repos
ventilateur absent ou bloqué
mémoire instable suspectée
Windows chiffré sans clé de récupération
partitionnement incompris
absence de sauvegarde des données importantes
firmware/UEFI instable
machine non alimentée correctement
```

---

# PHASE 22 — Séquence opérationnelle

```text
1. Démarrer une distribution Linux Live compatible
2. Vérifier clavier/écran
3. Identifier machine / BIOS / UEFI
4. Identifier CPU
5. Identifier RAM
6. Identifier GPU
7. Identifier stockage
8. Lire SMART
9. Cartographier les partitions
10. Identifier Windows / EFI / Recovery
11. Vérifier réseau
12. Vérifier audio / Bluetooth / webcam si nécessaire
13. Vérifier batterie
14. Lire températures
15. Lire logs noyau
16. Vérifier virtualisation
17. Évaluer potentiel IA locale
18. Évaluer compatibilité Debian
19. Choisir stratégie de partitionnement
20. Produire rapport TXT + JSON
21. Sauvegarder le rapport hors machine
22. Seulement ensuite : installation Debian
```

---

# PHASE 23 — Futur script `00-diagnostic.sh`

Ce protocole servira de spécification au futur script :

```text
00-diagnostic.sh
```

Le script devra :

- être non destructif ;
- fonctionner depuis Debian Live, Ubuntu Live et les environnements Linux Live compatibles ;
- détecter automatiquement les périphériques ;
- produire un rapport lisible ;
- produire un JSON structuré ;
- masquer les identifiants sensibles par défaut ;
- ne monter aucune partition Windows en écriture ;
- ne modifier aucun firmware ;
- ne modifier aucune partition ;
- ne lancer aucun stress test lourd automatiquement ;
- afficher les anomalies ;
- proposer un profil G75IA ;
- demander confirmation humaine avant toute étape hors lecture seule.

---

# PHASE 24 — Résultat attendu

À la fin du diagnostic, nous devons pouvoir répondre précisément à quatre questions :

```text
1. Cette machine est-elle saine ?
2. Debian peut-il y être installé proprement ?
3. Quelle stratégie de partitionnement est la plus sûre ?
4. Quel rôle IA cette machine peut-elle raisonnablement tenir ?
```

Le diagnostic devient ainsi le **point d’entrée standard de toute nouvelle machine G75IA**.
