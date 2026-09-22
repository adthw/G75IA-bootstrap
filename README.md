# G75IA Machine Diagnostic

Diagnostic matériel depuis un environnement Linux Live et préparation d’une machine avant installation de Debian et OpenClaw.

> **Statut du projet :** le protocole et la spécification sont définis. Le script `00-diagnostic.sh` est implémenté en version `0.2.0` et doit maintenant être validé sur plusieurs machines.

> **Sécurité :** ce script est exécuté avec des privilèges élevés. Téléchargez-le uniquement depuis ce dépôt, examinez les modifications avant mise à jour et n’exécutez jamais directement une branche ou une pull request inconnue avec `sudo`.

---

## À quoi sert ce projet ?

Avant d’installer Debian ou OpenClaw sur une machine, G75IA commence par **observer la machine sans la modifier**.

Le script `00-diagnostic.sh` permet, en une commande, de répondre à quatre questions :

1. La machine est-elle saine ?
2. Debian peut-il y être installé proprement ?
3. Quelle stratégie de partitionnement est la plus sûre ?
4. Quel niveau d’IA locale cette machine peut-elle raisonnablement faire tourner ?

Le diagnostic vise notamment :

- CPU et capacités AVX / AVX2 / virtualisation ;
- quantité et type de RAM ;
- GPU et pilote détecté ;
- disques SATA / SSD / NVMe ;
- état SMART des disques ;
- partitions Windows, EFI et Recovery ;
- réseau Ethernet / Wi-Fi / Bluetooth ;
- batterie ;
- températures et ventilateurs ;
- erreurs noyau importantes ;
- compatibilité Debian ;
- potentiel OpenClaw ;
- potentiel de modèles IA locaux.

---

# Utilisation rapide

## 1. Préparer une clé Linux Live

Créer une clé USB Linux Live. **Debian stable + Xfce** reste l’environnement de référence, mais ce n’est pas une obligation.

Environnements conseillés :

- Debian Live stable ;
- Ubuntu LTS en mode « Try Ubuntu » ;
- Linux Mint, Pop!_OS et autres dérivées Debian/Ubuntu ;
- Fedora, openSUSE ou Arch Live en mode de compatibilité probable, avec davantage d’informations susceptibles d’être `UNKNOWN` si certains outils manquent.

Le script exige un environnement **Linux avec Bash**. Il n’est pas prévu pour être exécuté directement depuis Windows, macOS ou un BSD.

Démarrer la machine à diagnostiquer sur cette clé.

Choisir :

```text
Live System
```

et **ne pas lancer l’installation Debian tout de suite**.

### Niveaux de compatibilité

| Environnement Live | Niveau actuel | Remarque |
| --- | --- | --- |
| Debian stable | Référence | Environnement prioritaire de développement et de test. |
| Ubuntu LTS et dérivées | Compatible attendu | Même famille d’outils GNU/Linux ; quelques commandes facultatives peuvent manquer. |
| Fedora, openSUSE, Arch et dérivées | Compatible probable | Le diagnostic continue, mais certaines sections peuvent apparaître `UNKNOWN`. |
| Windows, macOS, BSD | Non pris en charge | Le script dépend de Bash, `/proc`, `/sys` et d’outils Linux. |

Certaines sessions Live montent automatiquement des partitions internes. Le script ne monte rien lui-même et signale une partition NTFS déjà montée en écriture, mais il est préférable de démonter proprement les volumes internes avant le diagnostic si l’interface Live les a ouverts automatiquement.

---

## 2. Mettre le projet G75IA sur une clé USB

Le dépôt contiendra notamment :

```text
g75ia-bootstrap/
├── .gitignore
├── README.md
├── SECURITY.md
├── 00-diagnostic.sh
└── docs/
```

Il pourra être récupéré de deux façons.

### Avec Git

Depuis la session Linux Live :

```bash
git clone https://github.com/adthw/G75IA-bootstrap.git
cd G75IA-bootstrap
```

### Sans Git

Télécharger le dépôt ZIP depuis GitHub, le décompresser, puis ouvrir un terminal dans le dossier.

---

## 3. Rendre le script exécutable

Une seule fois :

```bash
chmod +x 00-diagnostic.sh
```

---

## 4. Lancer le diagnostic

Commande normale :

```bash
sudo ./00-diagnostic.sh
```

Le script demandera confirmation avant de commencer.

Exemple :

```text
G75IA MACHINE DIAGNOSTIC
------------------------
Mode : lecture seule
Aucune partition ne sera modifiée.
Aucun système de fichiers ne sera formaté.
Aucune partition Windows ne sera montée en écriture.
Aucun firmware ne sera modifié.

Continuer le diagnostic en lecture seule ? [O/n]
```

Répondre :

```text
O
```

ou simplement appuyer sur **Entrée** si `O` est la valeur par défaut.

---

# Pourquoi faut-il utiliser `sudo` ?

Certaines informations matérielles ne sont lisibles qu’avec des droits administrateur :

- DMI / BIOS ;
- SMART des disques ;
- certains journaux noyau ;
- certaines informations de batterie ou de firmware.

Le script utilise donc `sudo`, mais **il reste volontairement non destructif**.

Il n’utilise pas ces droits pour modifier la machine.

---

# Ce que fait le script

Une exécution complète ressemblera à ceci :

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

Le script **observe**, collecte et analyse.

Il ne corrige rien automatiquement.

---

# Ce que le script ne fait jamais

Le diagnostic initial ne doit jamais :

- formater un disque ;
- créer ou supprimer une partition ;
- réduire Windows ;
- modifier une partition NTFS ;
- installer Debian ;
- installer OpenClaw ;
- modifier Secure Boot ;
- modifier le BIOS ;
- installer un pilote GPU ;
- lancer un stress test lourd automatiquement ;
- supprimer des fichiers ;
- réparer un système de fichiers ;
- modifier BitLocker.

Le principe G75IA est :

> **Observer d’abord, décider ensuite, modifier seulement après validation humaine.**

---

# Où sont enregistrés les résultats ?

Le script crée automatiquement un dossier :

```text
reports/
└── AAAA-MM-JJ_HHMMSS_machine.XXXXXX/
```

Exemple :

```text
reports/
└── 2026-09-22_113000_machine.a1B2c3/
    ├── machine-report.txt
    ├── machine-report.json
    ├── summary.txt
    ├── SHA256SUMS
    ├── errors.log
    └── raw/
```

---

# Les fichiers importants

## `summary.txt`

Le fichier le plus court.

Il indique immédiatement :

```text
Machine saine : oui
Debian : compatible
Windows : détecté
Disque : sain
RAM : 16 GiB
OpenClaw : adapté
Petit modèle local : adapté
Installation Debian : possible
Problème bloquant : aucun
```

C’est le fichier à lire en premier.

---

## `machine-report.txt`

Rapport détaillé destiné à un humain.

Il contient par exemple :

```text
CPU
RAM
GPU
stockage
SMART
partitions
réseau
batterie
températures
compatibilité Debian
profil IA
recommandation d’installation
```

C’est aussi le fichier le plus simple à envoyer à ChatGPT pour analyse.

---

## `machine-report.json`

Version structurée du diagnostic.

Elle servira plus tard au système G75IA pour automatiser une partie de la préparation.

Par exemple :

```text
00-diagnostic.sh
        ↓
machine-report.json
        ↓
validation humaine
        ↓
install.sh
```

Le fichier JSON **ne doit jamais déclencher seul un repartitionnement ou une installation**.

---

## `raw/`

Contient les sorties techniques détaillées :

```text
lscpu
dmidecode
lsblk
SMART
lspci
sensors
dmesg
...
```

Ces fichiers permettent de revenir aux données brutes si le résumé semble étrange.

Les sorties brutes sont elles aussi anonymisées. Elles peuvent néanmoins révéler une cartographie technique de la machine. Relisez toujours un rapport avant de le transmettre et ne l’ajoutez jamais au dépôt public.

---

# Comprendre les statuts

Le script utilise cinq statuts.

### `OK`

Tout semble normal.

```text
[OK] NVMe SMART healthy
```

### `WARN`

Quelque chose mérite attention mais n’interdit pas nécessairement l’installation.

```text
[WARN] Batterie : 58 % de capacité restante
```

### `CRITICAL`

Le script a détecté un problème suffisamment sérieux pour recommander l’arrêt.

```text
[CRITICAL] NVMe critical warning detected
```

Dans ce cas : **ne pas installer Debian avant analyse**.

### `UNKNOWN`

Impossible d’obtenir l’information.

```text
[UNKNOWN] SMART : smartctl absent
```

Cela ne signifie pas que le matériel est défectueux.

### `INFO`

Simple information.

```text
[INFO] Windows 11 détecté
```

---

# Si un outil manque

Le script doit continuer à fonctionner même si l’environnement Live ne contient pas certains outils.

Exemple :

```text
[UNKNOWN] SMART : smartctl absent
```

Il pourra proposer :

```bash
sudo apt update
sudo apt install smartmontools lm-sensors nvme-cli
```

Mais par défaut, **le diagnostic n’installe rien tout seul**.

---

# Windows est-il en danger ?

Non, si le script respecte cette spécification.

Le diagnostic :

- identifie les partitions Windows ;
- détecte NTFS ;
- détecte l’EFI ;
- détecte Recovery ;
- ne monte pas Windows en écriture ;
- ne réduit pas Windows ;
- ne modifie pas BitLocker.

Le redimensionnement éventuel de Windows sera décidé **plus tard**, après le diagnostic et sauvegarde des données importantes.

---

# Exemple de résultat final

```text
G75IA MACHINE REPORT
====================

Machine
-------
Lenovo ThinkPad ...
UEFI: yes
Secure Boot: enabled

CPU
---
Intel Core i7 ...
6 cores / 12 threads
AVX2: yes

Memory
------
16 GiB DDR4

Storage
-------
Samsung NVMe 512 GB
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
CPU idle: 44 °C
NVMe: 38 °C

G75IA profile
-------------
OpenClaw: suitable
Local small model: suitable
Local 7B model: possible
GPU inference: to evaluate

Installation
------------
Suggested: Windows + Debian dual boot
Blocking issue: none
```

---

# Que faire après le diagnostic ?

Il ne faut pas lancer immédiatement l’installation.

La séquence G75IA prévue est :

```text
1. Diagnostic machine
        ↓
2. Analyse du rapport
        ↓
3. Validation humaine
        ↓
4. Sauvegarde si nécessaire
        ↓
5. Préparation Windows éventuelle
        ↓
6. Installation Debian
        ↓
7. Configuration Debian
        ↓
8. Installation OpenClaw
        ↓
9. Sécurisation OpenClaw
        ↓
10. Audit final
```

---

# Utilisation avec ChatGPT

Après le diagnostic, fournir simplement :

```text
machine-report.txt
```

et demander par exemple :

```text
Analyse ce rapport G75IA.
Dis-moi s’il existe un problème bloquant avant installation Debian,
propose le partitionnement le plus sûr et évalue le potentiel OpenClaw
et IA locale de cette machine.
```

Pour une analyse technique approfondie, ajouter éventuellement les fichiers `raw/` concernés.

---

# Utilisation prévue avec OpenClaw

À terme, OpenClaw pourra lire :

```text
machine-report.json
```

et préparer une proposition de configuration.

Mais il ne devra pas avoir l’autorité pour décider seul :

- du partitionnement ;
- de la suppression d’un système ;
- du chiffrement ;
- des droits root ;
- de l’exposition réseau.

Ces décisions restent sous contrôle humain.

---

# Options disponibles

La version `0.2.0` accepte :

```bash
sudo ./00-diagnostic.sh --quick
sudo ./00-diagnostic.sh --full
sudo ./00-diagnostic.sh --no-network
sudo ./00-diagnostic.sh --json-only
sudo ./00-diagnostic.sh --output /media/user/USB
sudo ./00-diagnostic.sh --yes
```

L’utilisation normale reste volontairement simple :

```bash
sudo ./00-diagnostic.sh
```

---

# Pour installer la machine d’un ami

La procédure courte sera :

```text
1. Préparer une clé Linux Live compatible.
2. Démarrer son ordinateur sur la clé.
3. Copier ou cloner le dépôt G75IA.
4. Ouvrir un terminal.
5. cd g75ia-bootstrap
6. chmod +x 00-diagnostic.sh
7. sudo ./00-diagnostic.sh
8. Attendre la fin.
9. Copier le dossier reports/ sur une clé.
10. Analyser le rapport.
11. Seulement ensuite décider de l’installation Debian.
```

Aucune connaissance Linux avancée ne devrait être nécessaire pour cette première phase.

---

# Philosophie G75IA

Le G75IA original est un ASUS G75VW ancien transformé progressivement en machine Debian + OpenClaw.

Mais ce projet n’est pas limité au G75.

L’objectif est de construire une méthode reproductible permettant de transformer des machines très différentes en systèmes IA locaux ou hybrides, sans sacrifier :

- la maîtrise humaine ;
- la sécurité ;
- la confidentialité ;
- la réversibilité ;
- la compréhension de la machine.

Le diagnostic est la première étape de cette méthode.

> **Comprendre la machine avant de lui demander quoi que ce soit.**

---

# Documents techniques du projet

Le dépôt devra également contenir :

```text
docs/
├── G75IA_Protocole_diagnostic_machine_2026-09-22.md
└── G75IA_Specification_script_00-diagnostic_2026-09-22.md
```

Le premier décrit **ce qu’il faut diagnostiquer**.

Le second décrit **comment `00-diagnostic.sh` doit être construit**.

Ce `README.md` explique simplement **comment l’utiliser**.

Les états de référence des machines réelles restent hors du dépôt public.

---

# État actuel

```text
[✓] Méthode de diagnostic définie
[✓] Protocole détaillé
[✓] Architecture du script définie
[✓] Format des rapports défini
[✓] Durcissement sécurité et confidentialité de 00-diagnostic.sh (v0.2.0)
[ ] Tests sur G75IA n°2
[ ] Test sur machine récente
[ ] Bootstrap Debian automatisé
[ ] Bootstrap OpenClaw automatisé
```

La prochaine étape du projet est donc très claire :

> **tester `00-diagnostic.sh` sur le G75IA n°2, comparer les résultats à l’état de référence, puis corriger les écarts éventuels.**
