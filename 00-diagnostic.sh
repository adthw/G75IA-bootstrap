#!/usr/bin/env bash
# G75IA 00-diagnostic.sh
# Diagnostic non destructif d'une machine avant installation Debian / OpenClaw.
# Version 0.2.0 - 2026-09-22
#
# Principe : observer d'abord, décider ensuite, modifier seulement après validation humaine.
#
# Ce script NE partitionne PAS, NE formate PAS, NE monte PAS Windows en écriture,
# NE modifie PAS le BIOS/UEFI, Secure Boot, BitLocker, les pilotes ou le firmware.

set -u
set -o pipefail
umask 077
export LC_ALL=C
export PATH='/usr/sbin:/usr/bin:/sbin:/bin'

VERSION="0.2.0"
MODE="full"
NO_NETWORK=0
JSON_ONLY=0
ASSUME_YES=0
OUTPUT_BASE="./reports"

SCRIPT_NAME="$(basename "$0")"
START_TS="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"
STAMP="$(date '+%Y-%m-%d_%H%M%S')"

WARN_COUNT=0
CRIT_COUNT=0
UNKNOWN_COUNT=0
INTERNAL_ERROR=0

STATUS_LINES=()
KERNEL_FINDINGS=()

usage() {
  cat <<EOF
G75IA Machine Diagnostic ${VERSION}

Usage:
  sudo ./${SCRIPT_NAME} [options]

Options:
  --quick              Diagnostic essentiel (moins de sorties brutes)
  --full               Diagnostic complet non destructif (défaut)
  --no-network         Ne lance aucun test réseau externe
  --json-only          Génère le JSON et les données techniques, minimise l'affichage
  --output DIR         Dossier parent des rapports (défaut: ./reports)
  --yes                Ne demande pas la confirmation initiale
  -h, --help           Affiche cette aide

Exemple:
  sudo ./${SCRIPT_NAME} --output /media/user/USB

Codes de retour:
  0  diagnostic terminé sans anomalie bloquante ni warning
  1  diagnostic terminé avec un ou plusieurs warnings
  2  anomalie critique détectée
  3  erreur interne du script
  4  environnement insuffisant / usage incorrect
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick) MODE="quick"; shift ;;
    --full) MODE="full"; shift ;;
    --no-network) NO_NETWORK=1; shift ;;
    --json-only) JSON_ONLY=1; shift ;;
    --output)
      [[ $# -ge 2 ]] || { echo "Erreur: --output attend un dossier." >&2; exit 4; }
      OUTPUT_BASE="$2"; shift 2 ;;
    --yes) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Option inconnue: $1" >&2; usage; exit 4 ;;
  esac
done

has_cmd() { command -v "$1" >/dev/null 2>&1; }

sanitize_name() {
  printf '%s' "$1" | tr '[:space:]/' '__' | tr -cd '[:alnum:]_.-'
}

json_escape() {
  local s="${1-}"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

bool_json() {
  [[ "${1:-0}" == "1" ]] && printf 'true' || printf 'false'
}

redact_stream() {
  # Les rapports sont toujours anonymisés. Il n'existe volontairement aucun
  # commutateur permettant de désactiver cette protection.
  sed -E \
    -e 's/([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}/[MAC-REDACTED]/g' \
    -e 's/\b(wlx|enx)[[:xdigit:]]{12}\b/[INTERFACE-REDACTED]/Ig' \
    -e 's/[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}/[UUID-REDACTED]/g' \
    -e 's/([[:space:]=:]|^)([0-9]{1,3}\.){3}[0-9]{1,3}([/[:space:],]|$)/\1[IPV4-REDACTED]\3/g' \
    -e 's/([[:xdigit:]]{0,4}:){2,}[[:xdigit:]:]{0,4}/[IPV6-REDACTED]/g' \
    -e 's#/home/[^/[:space:]]+#/home/[USER-REDACTED]#g' \
    -e 's#/run/media/[^/[:space:]]+#/run/media/[USER-REDACTED]#g' \
    -e 's#/media/[^/[:space:]]+#/media/[USER-REDACTED]#g' \
    -e 's#/run/user/[0-9]+#/run/user/[UID-REDACTED]#g' \
    -e 's/^([[:space:]]*(Serial Number|Serial|Machine ID|Machine-ID|UUID|WWN|LU WWN Device Id|EUI|NGUID|Asset Tag)[[:space:]]*[:=][[:space:]]*).*/\1[REDACTED]/I' \
    -e 's/^([[:space:]]*(ID_SERIAL|ID_SERIAL_SHORT|ID_WWN|ID_FS_UUID|ID_PART_ENTRY_UUID)=).*/\1[REDACTED]/I' \
    -e 's/((token|secret|password|passwd|api[_-]?key)[[:space:]]*[:=][[:space:]]*)[^[:space:]]+/\1[REDACTED]/Ig'
}

print_line() {
  [[ "$JSON_ONLY" -eq 1 ]] || printf '%s\n' "$*"
}

status_add() {
  local level="$1" key="$2" message="$3"
  STATUS_LINES+=("${level}|${key}|${message}")
  case "$level" in
    WARN) WARN_COUNT=$((WARN_COUNT+1)) ;;
    CRITICAL) CRIT_COUNT=$((CRIT_COUNT+1)) ;;
    UNKNOWN) UNKNOWN_COUNT=$((UNKNOWN_COUNT+1)) ;;
  esac
  print_line "[$level] $message"
}

safe_raw() {
  local name="$1"; shift
  local tmp
  local out="${RAW_DIR}/${name}.txt"

  tmp="$(mktemp -p "$RAW_DIR" ".${name}.XXXXXX")" || {
    printf 'Impossible de créer un fichier temporaire privé dans %s\n' "$RAW_DIR" >&2
    INTERNAL_ERROR=1
    return 1
  }
  if "$@" >"$tmp" 2>>"$ERROR_LOG"; then
    redact_stream < "$tmp" > "$out"
    rm -f "$tmp"
    return 0
  else
    local rc=$?
    redact_stream < "$tmp" > "$out"
    rm -f "$tmp"
    printf '%s command_failed rc=%s cmd=%q\n' "$(date -Iseconds 2>/dev/null || date)" "$rc" "$*" >> "$ERROR_LOG"
    return "$rc"
  fi
}

read_first() {
  local path="$1"
  [[ -r "$path" ]] && head -n1 "$path" 2>/dev/null || true
}

to_gib_from_kib() {
  awk -v k="${1:-0}" 'BEGIN { printf "%.1f", k/1024/1024 }'
}

to_celsius_millideg() {
  awk -v m="${1:-0}" 'BEGIN { printf "%.1f", m/1000 }'
}

# --- Répertoire de travail ----------------------------------------------------

if [[ -e "$OUTPUT_BASE" && ! -d "$OUTPUT_BASE" ]]; then
  echo "Le chemin de sortie existe mais n'est pas un dossier: $OUTPUT_BASE" >&2
  exit 4
fi
if [[ -L "$OUTPUT_BASE" ]]; then
  echo "Refus d'utiliser un lien symbolique comme dossier de sortie: $OUTPUT_BASE" >&2
  exit 4
fi
mkdir -p -- "$OUTPUT_BASE" 2>/dev/null || {
  echo "Impossible de créer le dossier de sortie: $OUTPUT_BASE" >&2
  exit 4
}

# mktemp évite toute réutilisation d'un ancien dossier ou écrasement via lien
# symbolique lorsque le script fonctionne avec les privilèges root.
REPORT_DIR="$(mktemp -d -p "$OUTPUT_BASE" "${STAMP}_machine.XXXXXX")" || {
  echo "Impossible de créer un dossier de rapport privé dans: $OUTPUT_BASE" >&2
  exit 4
}
RAW_DIR="${REPORT_DIR}/raw"
ERROR_LOG="${REPORT_DIR}/errors.log"
TXT_REPORT="${REPORT_DIR}/machine-report.txt"
JSON_REPORT="${REPORT_DIR}/machine-report.json"
SUMMARY_REPORT="${REPORT_DIR}/summary.txt"
CHECKSUMS="${REPORT_DIR}/SHA256SUMS"

mkdir -- "$RAW_DIR" 2>/dev/null || {
  echo "Impossible de créer: $REPORT_DIR" >&2
  exit 4
}
: > "$ERROR_LOG"

# --- En-tête / consentement --------------------------------------------------

if [[ "$JSON_ONLY" -eq 0 ]]; then
  cat <<EOF
G75IA MACHINE DIAGNOSTIC ${VERSION}
-----------------------------------
Mode : ${MODE}
Politique : lecture seule

Aucune partition ne sera créée, supprimée ou redimensionnée.
Aucun système de fichiers ne sera formaté.
Aucune partition Windows ne sera montée en écriture.
Aucun firmware, BIOS/UEFI, Secure Boot ou BitLocker ne sera modifié.
Aucun stress test lourd ne sera lancé.

Rapport : ${REPORT_DIR}
EOF
fi

if [[ "$ASSUME_YES" -eq 0 ]]; then
  printf '\nContinuer le diagnostic en lecture seule ? [O/n] '
  read -r answer
  case "${answer:-O}" in
    O|o|Y|y|yes|YES|oui|OUI) ;;
    *) echo "Diagnostic annulé."; exit 0 ;;
  esac
fi

if [[ "$EUID" -ne 0 ]]; then
  status_add "WARN" "privileges" "Le script n'est pas exécuté en root : certaines informations seront indisponibles. Utiliser sudo pour un diagnostic complet."
fi

# --- Variables globales de résultat -----------------------------------------

LIVE_ENV=0
KERNEL="$(uname -r 2>/dev/null || echo unknown)"
ARCH="$(uname -m 2>/dev/null || echo unknown)"
OS_PRETTY="unknown"

MANUFACTURER="unknown"
PRODUCT="unknown"
BOARD="unknown"
BIOS_VENDOR="unknown"
BIOS_VERSION="unknown"
BIOS_DATE="unknown"
BOOT_MODE="unknown"
SECURE_BOOT="unknown"
TPM_PRESENT=0

CPU_MODEL="unknown"
CPU_CORES="unknown"
CPU_THREADS="unknown"
CPU_SOCKETS="unknown"
CPU_AVX=0
CPU_AVX2=0
CPU_AVX512=0
CPU_VIRT="unknown"

MEM_GIB="unknown"
MEM_SLOTS_TOTAL="unknown"
MEM_SLOTS_USED="unknown"
MEM_TYPE="unknown"
MEM_SPEED="unknown"

GPU_COUNT=0
GPU_SUMMARY="unknown"
GPU_ACCEL="unknown"

DISK_COUNT=0
DISK_SUMMARY="unknown"
SMART_STATUS="UNKNOWN"
WINDOWS_DETECTED=0
EFI_DETECTED=0

ETHERNET_PRESENT=0
WIFI_PRESENT=0
BLUETOOTH_PRESENT=0
NETWORK_TEST="not-tested"

BATTERY_PRESENT=0
BATTERY_HEALTH="unknown"

THERMAL_SUMMARY="unknown"

KVM_PRESENT=0
IOMMU_PRESENT=0

DEBIAN_COMPAT="manual-review"
AI_PROFILE="unknown"
INSTALL_STRATEGY="manual-review"
BLOCKING_ISSUE="none"

# --- 1/15 Environnement ------------------------------------------------------

print_line ""
print_line "[1/15] Environnement"

if [[ -r /etc/os-release ]]; then
  OS_PRETTY="$(awk -F= '$1=="PRETTY_NAME"{gsub(/^"|"$/,"",$2); print $2}' /etc/os-release)"
fi

if grep -qiE '(^|[[:space:]])(boot=live|boot=casper|rd\.live\.image|archisobasedir=)' /proc/cmdline 2>/dev/null \
  || [[ -d /run/live ]] \
  || [[ -d /run/archiso ]] \
  || [[ -d /rofs ]] \
  || [[ -d /cdrom/casper ]]; then
  LIVE_ENV=1
fi

safe_raw "uname" uname -srm || true
safe_raw "os-release" cat /etc/os-release || true

status_add "INFO" "environment" "Système observé: ${OS_PRETTY}; kernel ${KERNEL}; architecture ${ARCH}."
[[ "$LIVE_ENV" -eq 1 ]] && status_add "INFO" "live" "Session Live détectée."

# --- 2/15 Firmware -----------------------------------------------------------

print_line ""
print_line "[2/15] Firmware / machine"

if has_cmd dmidecode; then
  safe_raw "dmidecode-system" dmidecode -t system || true
  safe_raw "dmidecode-baseboard" dmidecode -t baseboard || true
  safe_raw "dmidecode-bios" dmidecode -t bios || true

  MANUFACTURER="$(dmidecode -s system-manufacturer 2>/dev/null | head -n1 | xargs || true)"
  PRODUCT="$(dmidecode -s system-product-name 2>/dev/null | head -n1 | xargs || true)"
  BOARD="$(dmidecode -s baseboard-product-name 2>/dev/null | head -n1 | xargs || true)"
  BIOS_VENDOR="$(dmidecode -s bios-vendor 2>/dev/null | head -n1 | xargs || true)"
  BIOS_VERSION="$(dmidecode -s bios-version 2>/dev/null | head -n1 | xargs || true)"
  BIOS_DATE="$(dmidecode -s bios-release-date 2>/dev/null | head -n1 | xargs || true)"
else
  status_add "UNKNOWN" "dmidecode" "dmidecode absent : identification DMI partielle."
fi

[[ -d /sys/firmware/efi ]] && BOOT_MODE="UEFI" || BOOT_MODE="Legacy BIOS"

if has_cmd mokutil; then
  sb="$(mokutil --sb-state 2>/dev/null || true)"
  case "$sb" in
    *enabled*) SECURE_BOOT="enabled" ;;
    *disabled*) SECURE_BOOT="disabled" ;;
    *) SECURE_BOOT="unknown" ;;
  esac
else
  SECURE_BOOT="unknown"
fi

compgen -G '/dev/tpm*' >/dev/null 2>&1 && TPM_PRESENT=1 || true

status_add "OK" "boot_mode" "Mode de démarrage: ${BOOT_MODE}."
status_add "INFO" "machine" "Machine: ${MANUFACTURER:-unknown} ${PRODUCT:-unknown}; BIOS ${BIOS_VERSION:-unknown}."

# --- 3/15 CPU ---------------------------------------------------------------

print_line ""
print_line "[3/15] CPU"

safe_raw "lscpu" lscpu || true

CPU_MODEL="$(lscpu 2>/dev/null | awk -F: '/Model name/{sub(/^[ \t]+/,"",$2); print $2; exit}')"
CPU_SOCKETS="$(lscpu 2>/dev/null | awk -F: '/Socket\(s\)/{gsub(/[ \t]/,"",$2); print $2; exit}')"
CPU_THREADS="$(nproc 2>/dev/null || true)"
CPU_CORES="$(lscpu 2>/dev/null | awk -F: '
  /Core\(s\) per socket/{gsub(/[ \t]/,"",$2); c=$2}
  /Socket\(s\)/{gsub(/[ \t]/,"",$2); s=$2}
  END{if(c!=""&&s!="") print c*s}')"

FLAGS="$(grep -m1 -E '^flags|^Features' /proc/cpuinfo 2>/dev/null || true)"
grep -qw avx <<<"$FLAGS" && CPU_AVX=1 || true
grep -qw avx2 <<<"$FLAGS" && CPU_AVX2=1 || true
grep -qwo 'avx512[^ ]*' <<<"$FLAGS" && CPU_AVX512=1 || true

CPU_VIRT="$(lscpu 2>/dev/null | awk -F: '/Virtualization:/{sub(/^[ \t]+/,"",$2); print $2; exit}')"
[[ -n "$CPU_VIRT" ]] || CPU_VIRT="unknown"

status_add "INFO" "cpu" "CPU: ${CPU_MODEL:-unknown}; ${CPU_CORES:-?} cœurs / ${CPU_THREADS:-?} threads; AVX2=$( [[ "$CPU_AVX2" -eq 1 ]] && echo oui || echo non )."

# --- 4/15 RAM ---------------------------------------------------------------

print_line ""
print_line "[4/15] Mémoire"

safe_raw "free" free -h || true

MEM_KIB="$(awk '/MemTotal:/{print $2}' /proc/meminfo 2>/dev/null || echo 0)"
MEM_GIB="$(to_gib_from_kib "$MEM_KIB")"

if has_cmd dmidecode; then
  safe_raw "dmidecode-memory" dmidecode -t memory || true
  # Nombre de blocs "Memory Device" et modules réellement présents.
  MEM_SLOTS_TOTAL="$(dmidecode -t memory 2>/dev/null | awk '
    /^Memory Device$/ {n++}
    END{print n+0}')"
  MEM_SLOTS_USED="$(dmidecode -t memory 2>/dev/null | awk '
    /^Memory Device$/ {in_dev=1; next}
    in_dev && /^[ \t]+Size:/ {
      if ($0 !~ /No Module Installed/ && $0 !~ /Unknown/ && $0 !~ /Not Installed/) used++;
      in_dev=0
    }
    END{print used+0}')"
  MEM_TYPE="$(dmidecode -t memory 2>/dev/null | awk -F: '/^[ \t]+Type:/{gsub(/^[ \t]+/,"",$2); if($2 !~ /Unknown/ && $2 !~ /Other/){print $2; exit}}')"
  MEM_SPEED="$(dmidecode -t memory 2>/dev/null | awk -F: '/Configured Memory Speed:|Speed:/{gsub(/^[ \t]+/,"",$2); if($2 !~ /Unknown/){print $2; exit}}')"
fi

status_add "INFO" "memory" "RAM visible: ${MEM_GIB} GiB; slots utilisés ${MEM_SLOTS_USED}/${MEM_SLOTS_TOTAL}; type ${MEM_TYPE:-unknown}."

# --- 5/15 GPU ---------------------------------------------------------------

print_line ""
print_line "[5/15] GPU"

if has_cmd lspci; then
  safe_raw "lspci-nnk" lspci -nnk || true
  GPU_LINES="$(lspci 2>/dev/null | grep -Ei 'VGA compatible controller|3D controller|Display controller' || true)"
  GPU_COUNT="$(grep -c . <<<"$GPU_LINES" 2>/dev/null || echo 0)"
  GPU_SUMMARY="$(printf '%s' "$GPU_LINES" | paste -sd ';' - | cut -c1-800)"
  [[ -n "$GPU_SUMMARY" ]] || GPU_SUMMARY="unknown"
else
  status_add "UNKNOWN" "lspci" "lspci absent : GPU non identifié précisément."
fi

if has_cmd glxinfo && [[ -n "${DISPLAY:-}" ]]; then
  safe_raw "glxinfo-B" glxinfo -B || true
  if glxinfo -B 2>/dev/null | grep -qi 'direct rendering: Yes'; then
    GPU_ACCEL="yes"
  fi
fi

if has_cmd nvidia-smi; then
  safe_raw "nvidia-smi" nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader || true
fi

status_add "INFO" "gpu" "GPU détecté(s): ${GPU_COUNT}; accélération graphique Live: ${GPU_ACCEL}."

# --- 6/15 Stockage ----------------------------------------------------------

print_line ""
print_line "[6/15] Stockage"

safe_raw "lsblk" lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,FSVER,MODEL,ROTA,TRAN || true
safe_raw "lsblk-disks" lsblk -d -o NAME,PATH,SIZE,TYPE,ROTA,TRAN,MODEL || true

if has_cmd fdisk && [[ "$MODE" == "full" ]]; then
  safe_raw "fdisk-l" fdisk -l || true
fi

DISK_COUNT="$(lsblk -dn -o TYPE 2>/dev/null | grep -c '^disk$' || echo 0)"
DISK_SUMMARY="$(lsblk -dn -o NAME,SIZE,ROTA,TRAN,MODEL 2>/dev/null | paste -sd ';' - | cut -c1-1200)"
[[ -n "$DISK_SUMMARY" ]] || DISK_SUMMARY="unknown"

status_add "INFO" "storage" "Disques physiques détectés: ${DISK_COUNT}."

# --- 7/15 SMART -------------------------------------------------------------

print_line ""
print_line "[7/15] SMART"

if has_cmd smartctl; then
  SMART_STATUS="OK"
  while read -r devname devtype; do
    [[ "$devtype" == "disk" ]] || continue
    dev="/dev/${devname}"
    safe_name="$(sanitize_name "$devname")"
    # Lecture uniquement. -a n'ordonne aucun self-test.
    safe_raw "smart-${safe_name}" smartctl -a "$dev" || true

    smart_txt="$(smartctl -a "$dev" 2>/dev/null || true)"
    if grep -qiE 'SMART overall-health.*FAILED|SMART Health Status:.*BAD|Critical Warning:[[:space:]]*(0x)?[1-9a-fA-F]' <<<"$smart_txt"; then
      SMART_STATUS="CRITICAL"
      status_add "CRITICAL" "smart_${safe_name}" "SMART signale un état critique sur ${dev}."
    elif grep -qiE 'SMART overall-health.*PASSED|SMART Health Status:.*OK|Critical Warning:[[:space:]]*(0x)?0+' <<<"$smart_txt"; then
      status_add "OK" "smart_${safe_name}" "SMART lisible et sans échec global détecté sur ${dev}."
    else
      [[ "$SMART_STATUS" == "CRITICAL" ]] || SMART_STATUS="UNKNOWN"
      status_add "UNKNOWN" "smart_${safe_name}" "SMART de ${dev} non interprétable automatiquement ; voir raw/."
    fi

    # Quelques attributs SATA usuels : si >0, avertissement conservateur.
    for attr in Reallocated_Sector_Ct Current_Pending_Sector Offline_Uncorrectable; do
      val="$(awk -v a="$attr" '$2==a{print $10; exit}' <<<"$smart_txt")"
      if [[ "$val" =~ ^[0-9]+$ ]] && (( val > 0 )); then
        status_add "WARN" "smart_${safe_name}_${attr}" "${dev}: ${attr}=${val}."
        [[ "$SMART_STATUS" == "OK" ]] && SMART_STATUS="WARN"
      fi
    done
  done < <(lsblk -dn -o NAME,TYPE 2>/dev/null)
else
  SMART_STATUS="UNKNOWN"
  status_add "UNKNOWN" "smart" "smartctl absent : état SMART non vérifié."
fi

# --- 8/15 Windows / partitions ---------------------------------------------

print_line ""
print_line "[8/15] Windows / partitions"

safe_raw "lsblk-filesystems" lsblk -o NAME,FSTYPE,FSVER,SIZE || true
if has_cmd blkid && [[ "$MODE" == "full" ]]; then
  safe_raw "blkid-types" blkid -s TYPE || true
fi

FSTYPES="$(lsblk -rno FSTYPE 2>/dev/null || true)"
grep -qiE '^ntfs$|^BitLocker$' <<<"$FSTYPES" && WINDOWS_DETECTED=1 || true

# ESP par type GPT standard ou montage EFI.
if lsblk -rno PARTTYPE 2>/dev/null | grep -qi 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b'; then
  EFI_DETECTED=1
elif lsblk -rno FSTYPE,MOUNTPOINTS 2>/dev/null | grep -qiE '^vfat[[:space:]].*(/boot/efi|/efi)'; then
  EFI_DETECTED=1
fi

if [[ "$WINDOWS_DETECTED" -eq 1 ]]; then
  status_add "INFO" "windows" "Partition NTFS/BitLocker détectée : Windows ou volume Microsoft probable."
else
  status_add "INFO" "windows" "Aucune partition Windows évidente détectée."
fi
[[ "$EFI_DETECTED" -eq 1 ]] && status_add "OK" "efi" "Partition système EFI détectée." || status_add "INFO" "efi" "ESP non détectée automatiquement."

# Signale seulement les NTFS actuellement montées ; ne les démonte ni ne remonte.
NTFS_MOUNTS="$(findmnt -rn -t ntfs,ntfs3,fuseblk -o SOURCE,TARGET,OPTIONS 2>/dev/null || true)"
if [[ -n "$NTFS_MOUNTS" ]]; then
  safe_raw "mounted-ntfs" bash -c 'findmnt -rn -t ntfs,ntfs3,fuseblk -o SOURCE,TARGET,OPTIONS' || true
  if grep -qE '(^|,)rw(,|$)' <<<"$(awk '{print $3}' <<<"$NTFS_MOUNTS")"; then
    status_add "WARN" "windows_mount" "Une partition NTFS semble actuellement montée en écriture par l'environnement Live. Le script ne la modifie pas."
  else
    status_add "INFO" "windows_mount" "Une partition NTFS est montée, sans écriture détectée dans les options examinées."
  fi
fi

# --- 9/15 Réseau ------------------------------------------------------------

print_line ""
print_line "[9/15] Réseau"

has_cmd ip && safe_raw "ip-link" ip -brief link || true
has_cmd ip && safe_raw "ip-address" ip -brief address || true

if has_cmd lspci; then
  NETPCI="$(lspci 2>/dev/null | grep -Ei 'Ethernet controller|Network controller' || true)"
  grep -qi 'Ethernet controller' <<<"$NETPCI" && ETHERNET_PRESENT=1 || true
  grep -qi 'Network controller' <<<"$NETPCI" && WIFI_PRESENT=1 || true
fi

if has_cmd nmcli; then
  safe_raw "nmcli-device" nmcli device || true
fi
if has_cmd rfkill; then
  safe_raw "rfkill" rfkill list || true
  rfkill list 2>/dev/null | grep -qi bluetooth && BLUETOOTH_PRESENT=1 || true
fi
if has_cmd lsusb; then
  safe_raw "lsusb" lsusb || true
  lsusb 2>/dev/null | grep -qi bluetooth && BLUETOOTH_PRESENT=1 || true
fi

if [[ "$NO_NETWORK" -eq 0 ]]; then
  if has_cmd ping; then
    if ping -c 2 -W 2 1.1.1.1 >/dev/null 2>>"$ERROR_LOG"; then
      if ping -c 2 -W 2 debian.org >/dev/null 2>>"$ERROR_LOG"; then
        NETWORK_TEST="internet+dns-ok"
        status_add "OK" "network" "Connectivité IP et DNS fonctionnelles."
      else
        NETWORK_TEST="ip-ok-dns-failed"
        status_add "WARN" "network_dns" "Connectivité IP présente mais résolution DNS non confirmée."
      fi
    else
      NETWORK_TEST="offline-or-blocked"
      status_add "INFO" "network" "Accès Internet non confirmé (cela ne bloque pas le diagnostic matériel)."
    fi
  else
    NETWORK_TEST="unknown"
    status_add "UNKNOWN" "network" "ping absent : test Internet non effectué."
  fi
else
  NETWORK_TEST="disabled"
  status_add "INFO" "network" "Tests réseau externes désactivés par --no-network."
fi

# --- 10/15 Audio / Bluetooth / webcam --------------------------------------

print_line ""
print_line "[10/15] Périphériques"

has_cmd aplay && safe_raw "aplay" aplay -l || true
if compgen -G '/dev/video*' >/dev/null 2>&1; then
  ls -l /dev/video* 2>/dev/null | redact_stream > "${RAW_DIR}/video-devices.txt"
fi

status_add "INFO" "peripherals" "Ethernet=$(bool_json "$ETHERNET_PRESENT"), Wi-Fi=$(bool_json "$WIFI_PRESENT"), Bluetooth=$(bool_json "$BLUETOOTH_PRESENT")."

# --- 11/15 Batterie ---------------------------------------------------------

print_line ""
print_line "[11/15] Batterie"

BAT_PATH=""
for p in /sys/class/power_supply/BAT*; do
  [[ -d "$p" ]] || continue
  BAT_PATH="$p"; BATTERY_PRESENT=1; break
done

if [[ "$BATTERY_PRESENT" -eq 1 ]]; then
  {
    echo "path=$BAT_PATH"
    for f in status capacity cycle_count energy_full energy_full_design charge_full charge_full_design manufacturer model_name; do
      [[ -r "$BAT_PATH/$f" ]] && echo "$f=$(cat "$BAT_PATH/$f")"
    done
  } | redact_stream > "${RAW_DIR}/battery.txt"

  full="$(read_first "$BAT_PATH/energy_full")"
  design="$(read_first "$BAT_PATH/energy_full_design")"
  [[ -n "$full" && -n "$design" ]] || {
    full="$(read_first "$BAT_PATH/charge_full")"
    design="$(read_first "$BAT_PATH/charge_full_design")"
  }
  if [[ "$full" =~ ^[0-9]+$ && "$design" =~ ^[0-9]+$ && "$design" -gt 0 ]]; then
    BATTERY_HEALTH="$(awk -v f="$full" -v d="$design" 'BEGIN{printf "%.0f",100*f/d}')"
    if (( BATTERY_HEALTH < 50 )); then
      status_add "WARN" "battery" "Batterie fortement usée : santé estimée ${BATTERY_HEALTH}%."
    else
      status_add "INFO" "battery" "Santé batterie estimée : ${BATTERY_HEALTH}%."
    fi
  else
    status_add "INFO" "battery" "Batterie détectée ; santé précise non calculable."
  fi
else
  status_add "INFO" "battery" "Aucune batterie détectée."
fi

# --- 12/15 Thermique --------------------------------------------------------

print_line ""
print_line "[12/15] Thermique"

if has_cmd sensors; then
  safe_raw "sensors" sensors || true
  THERMAL_SUMMARY="$(sensors 2>/dev/null | grep -E 'Package id|Tctl|Tdie|temp[0-9]|Composite|edge|fan[0-9]' | head -n10 | paste -sd ';' - | cut -c1-1000)"
  [[ -n "$THERMAL_SUMMARY" ]] || THERMAL_SUMMARY="sensors présent, aucune valeur reconnue"
  status_add "INFO" "thermal" "Capteurs lus sans stress test. Voir raw/sensors.txt."
else
  temps=()
  for z in /sys/class/thermal/thermal_zone*/temp; do
    [[ -r "$z" ]] || continue
    v="$(cat "$z" 2>/dev/null || true)"
    [[ "$v" =~ ^[0-9]+$ ]] || continue
    temps+=("$(to_celsius_millideg "$v")C")
  done
  if (( ${#temps[@]} > 0 )); then
    THERMAL_SUMMARY="${temps[*]}"
    status_add "INFO" "thermal" "Capteurs kernel disponibles : ${THERMAL_SUMMARY}."
  else
    status_add "UNKNOWN" "thermal" "Aucun capteur thermique lisible sans outil supplémentaire."
  fi
fi

# --- 13/15 Logs noyau -------------------------------------------------------

print_line ""
print_line "[13/15] Logs noyau"

if has_cmd dmesg; then
  if dmesg -T > "${RAW_DIR}/.dmesg.tmp" 2>>"$ERROR_LOG"; then
    redact_stream < "${RAW_DIR}/.dmesg.tmp" > "${RAW_DIR}/dmesg.txt"
    grep -Ei 'thermal|mce|machine check|edac|nvme|ata|firmware|acpi|amdgpu|nouveau|i915|error|fail|fault' \
      "${RAW_DIR}/dmesg.txt" | tail -n 250 > "${RAW_DIR}/dmesg-filtered.txt" || true
    rm -f "${RAW_DIR}/.dmesg.tmp"

    # Critères conservateurs : machine-check / I/O errors explicites seulement.
    if grep -qiE 'machine check|MCE:.*Hardware Error|I/O error.*(nvme|sd[a-z]|ata)' "${RAW_DIR}/dmesg-filtered.txt" 2>/dev/null; then
      status_add "WARN" "kernel_hardware" "Le noyau contient des messages matériels à examiner ; voir dmesg-filtered.txt."
    else
      status_add "OK" "kernel" "Aucune erreur matérielle explicite retenue automatiquement dans le filtre noyau."
    fi
  else
    rm -f "${RAW_DIR}/.dmesg.tmp"
    status_add "UNKNOWN" "dmesg" "dmesg non lisible dans cet environnement."
  fi
else
  status_add "UNKNOWN" "dmesg" "Commande dmesg absente."
fi

# --- 14/15 Virtualisation ---------------------------------------------------

print_line ""
print_line "[14/15] Virtualisation"

if lsmod 2>/dev/null | grep -qE '^kvm(_intel|_amd)?'; then
  KVM_PRESENT=1
fi
if dmesg 2>/dev/null | grep -qiE 'IOMMU enabled|DMAR: IOMMU enabled|AMD-Vi'; then
  IOMMU_PRESENT=1
fi

status_add "INFO" "virtualization" "Virtualisation CPU: ${CPU_VIRT}; KVM=$(bool_json "$KVM_PRESENT"); IOMMU=$(bool_json "$IOMMU_PRESENT")."

# --- 15/15 Évaluation -------------------------------------------------------

print_line ""
print_line "[15/15] Profil G75IA et recommandation"

# Profil IA volontairement simple et explicable.
MEM_INT="$(awk -v m="$MEM_GIB" 'BEGIN{printf "%d",m+0}')"
if (( MEM_INT >= 32 )) && [[ "$CPU_AVX2" -eq 1 ]]; then
  AI_PROFILE="local-ai-strong-candidate"
elif (( MEM_INT >= 16 )) && [[ "$CPU_AVX2" -eq 1 ]]; then
  AI_PROFILE="local-ai-medium"
elif (( MEM_INT >= 8 )); then
  AI_PROFILE="local-ai-light"
else
  AI_PROFILE="cloud-oriented"
fi

# Compatibilité Debian préliminaire : le fait d'être dans Debian Live est un signal fort.
if [[ "$LIVE_ENV" -eq 1 ]]; then
  DEBIAN_COMPAT="compatible-preliminary"
else
  DEBIAN_COMPAT="manual-review"
fi
[[ "$CRIT_COUNT" -gt 0 ]] && DEBIAN_COMPAT="manual-review"

if [[ "$CRIT_COUNT" -gt 0 ]]; then
  INSTALL_STRATEGY="stop-and-review"
  BLOCKING_ISSUE="critical-finding"
elif [[ "$WINDOWS_DETECTED" -eq 1 ]]; then
  INSTALL_STRATEGY="dual-boot-candidate-human-validation-required"
else
  INSTALL_STRATEGY="debian-installation-candidate-human-validation-required"
fi

status_add "INFO" "ai_profile" "Profil IA indicatif: ${AI_PROFILE}."
status_add "INFO" "debian_compat" "Compatibilité Debian préliminaire: ${DEBIAN_COMPAT}."
status_add "INFO" "install" "Stratégie proposée: ${INSTALL_STRATEGY}."

# --- Rapports ---------------------------------------------------------------

# Résumé
{
  echo "G75IA MACHINE DIAGNOSTIC — SUMMARY"
  echo "=================================="
  echo "Generated: $START_TS"
  echo "Script: $VERSION"
  echo
  echo "Machine: ${MANUFACTURER:-unknown} ${PRODUCT:-unknown}"
  echo "Boot: $BOOT_MODE"
  echo "Secure Boot: $SECURE_BOOT"
  echo "CPU: ${CPU_MODEL:-unknown}"
  echo "CPU cores/threads: ${CPU_CORES:-unknown}/${CPU_THREADS:-unknown}"
  echo "AVX2: $( [[ "$CPU_AVX2" -eq 1 ]] && echo yes || echo no )"
  echo "RAM: ${MEM_GIB} GiB"
  echo "GPU(s): $GPU_COUNT"
  echo "Disks: $DISK_COUNT"
  echo "SMART: $SMART_STATUS"
  echo "Windows candidate: $( [[ "$WINDOWS_DETECTED" -eq 1 ]] && echo yes || echo no )"
  echo "EFI: $( [[ "$EFI_DETECTED" -eq 1 ]] && echo yes || echo no )"
  echo "Network test: $NETWORK_TEST"
  echo "Battery health: $BATTERY_HEALTH"
  echo "AI profile: $AI_PROFILE"
  echo "Debian compatibility: $DEBIAN_COMPAT"
  echo "Installation strategy: $INSTALL_STRATEGY"
  echo
  echo "Warnings: $WARN_COUNT"
  echo "Critical: $CRIT_COUNT"
  echo "Unknown: $UNKNOWN_COUNT"
  echo
  echo "Aucune modification de partition, firmware ou système de fichiers n'a été effectuée par ce script."
} > "$SUMMARY_REPORT"

# Rapport humain détaillé
{
  echo "G75IA MACHINE REPORT"
  echo "===================="
  echo
  echo "Generated: $START_TS"
  echo "Diagnostic mode: read-only"
  echo "Script version: $VERSION"
  echo
  echo "MACHINE"
  echo "-------"
  echo "Manufacturer: ${MANUFACTURER:-unknown}"
  echo "Product: ${PRODUCT:-unknown}"
  echo "Board: ${BOARD:-unknown}"
  echo "Boot mode: $BOOT_MODE"
  echo "BIOS vendor: ${BIOS_VENDOR:-unknown}"
  echo "BIOS version: ${BIOS_VERSION:-unknown}"
  echo "BIOS date: ${BIOS_DATE:-unknown}"
  echo "Secure Boot: $SECURE_BOOT"
  echo "TPM present: $( [[ "$TPM_PRESENT" -eq 1 ]] && echo yes || echo no )"
  echo
  echo "CPU"
  echo "---"
  echo "Model: ${CPU_MODEL:-unknown}"
  echo "Cores: ${CPU_CORES:-unknown}"
  echo "Threads: ${CPU_THREADS:-unknown}"
  echo "Sockets: ${CPU_SOCKETS:-unknown}"
  echo "AVX: $( [[ "$CPU_AVX" -eq 1 ]] && echo yes || echo no )"
  echo "AVX2: $( [[ "$CPU_AVX2" -eq 1 ]] && echo yes || echo no )"
  echo "AVX-512: $( [[ "$CPU_AVX512" -eq 1 ]] && echo yes || echo no )"
  echo "Virtualization: $CPU_VIRT"
  echo
  echo "MEMORY"
  echo "------"
  echo "Visible RAM: ${MEM_GIB} GiB"
  echo "Slots used/total: ${MEM_SLOTS_USED}/${MEM_SLOTS_TOTAL}"
  echo "Type: ${MEM_TYPE:-unknown}"
  echo "Speed: ${MEM_SPEED:-unknown}"
  echo
  echo "GPU"
  echo "---"
  echo "Count: $GPU_COUNT"
  echo "Summary: $GPU_SUMMARY"
  echo "Live graphic acceleration: $GPU_ACCEL"
  echo
  echo "STORAGE"
  echo "-------"
  echo "Physical disks: $DISK_COUNT"
  echo "Summary: $DISK_SUMMARY"
  echo "SMART: $SMART_STATUS"
  echo
  echo "OPERATING SYSTEMS / PARTITIONS"
  echo "------------------------------"
  echo "Windows candidate: $( [[ "$WINDOWS_DETECTED" -eq 1 ]] && echo yes || echo no )"
  echo "EFI detected: $( [[ "$EFI_DETECTED" -eq 1 ]] && echo yes || echo no )"
  echo
  echo "NETWORK / PERIPHERALS"
  echo "---------------------"
  echo "Ethernet present: $( [[ "$ETHERNET_PRESENT" -eq 1 ]] && echo yes || echo no )"
  echo "Wi-Fi present: $( [[ "$WIFI_PRESENT" -eq 1 ]] && echo yes || echo no )"
  echo "Bluetooth present: $( [[ "$BLUETOOTH_PRESENT" -eq 1 ]] && echo yes || echo no )"
  echo "Connectivity test: $NETWORK_TEST"
  echo
  echo "POWER / THERMAL"
  echo "---------------"
  echo "Battery present: $( [[ "$BATTERY_PRESENT" -eq 1 ]] && echo yes || echo no )"
  echo "Battery health: $BATTERY_HEALTH"
  echo "Thermal summary: $THERMAL_SUMMARY"
  echo
  echo "VIRTUALIZATION"
  echo "--------------"
  echo "CPU virtualization: $CPU_VIRT"
  echo "KVM active: $( [[ "$KVM_PRESENT" -eq 1 ]] && echo yes || echo no )"
  echo "IOMMU detected: $( [[ "$IOMMU_PRESENT" -eq 1 ]] && echo yes || echo no )"
  echo
  echo "G75IA PROFILE"
  echo "-------------"
  echo "AI profile: $AI_PROFILE"
  echo "Debian compatibility: $DEBIAN_COMPAT"
  echo "Installation strategy: $INSTALL_STRATEGY"
  echo "Blocking issue: $BLOCKING_ISSUE"
  echo
  echo "STATUS"
  echo "------"
  for item in "${STATUS_LINES[@]}"; do
    IFS='|' read -r level key msg <<<"$item"
    printf '[%s] %s\n' "$level" "$msg"
  done
  echo
  echo "SAFETY"
  echo "------"
  echo "This diagnostic did not intentionally format, repartition, resize, repair,"
  echo "or mount Windows volumes in write mode."
  echo "Raw technical outputs are available in ./raw/."
} | redact_stream > "$TXT_REPORT"

# JSON structuré, sans dépendance à jq.
{
  printf '{\n'
  printf '  "schema_version": "1.0",\n'
  printf '  "script_version": "%s",\n' "$(json_escape "$VERSION")"
  printf '  "generated_at": "%s",\n' "$(json_escape "$START_TS")"
  printf '  "diagnostic_mode": "read-only",\n'
  printf '  "live_environment": %s,\n' "$(bool_json "$LIVE_ENV")"
  printf '  "machine": {\n'
  printf '    "manufacturer": "%s",\n' "$(json_escape "${MANUFACTURER:-unknown}")"
  printf '    "product": "%s",\n' "$(json_escape "${PRODUCT:-unknown}")"
  printf '    "board": "%s"\n' "$(json_escape "${BOARD:-unknown}")"
  printf '  },\n'
  printf '  "firmware": {\n'
  printf '    "boot_mode": "%s",\n' "$(json_escape "$BOOT_MODE")"
  printf '    "bios_vendor": "%s",\n' "$(json_escape "${BIOS_VENDOR:-unknown}")"
  printf '    "bios_version": "%s",\n' "$(json_escape "${BIOS_VERSION:-unknown}")"
  printf '    "bios_date": "%s",\n' "$(json_escape "${BIOS_DATE:-unknown}")"
  printf '    "secure_boot": "%s",\n' "$(json_escape "$SECURE_BOOT")"
  printf '    "tpm_present": %s\n' "$(bool_json "$TPM_PRESENT")"
  printf '  },\n'
  printf '  "cpu": {\n'
  printf '    "model": "%s",\n' "$(json_escape "${CPU_MODEL:-unknown}")"
  printf '    "cores": "%s",\n' "$(json_escape "${CPU_CORES:-unknown}")"
  printf '    "threads": "%s",\n' "$(json_escape "${CPU_THREADS:-unknown}")"
  printf '    "sockets": "%s",\n' "$(json_escape "${CPU_SOCKETS:-unknown}")"
  printf '    "avx": %s,\n' "$(bool_json "$CPU_AVX")"
  printf '    "avx2": %s,\n' "$(bool_json "$CPU_AVX2")"
  printf '    "avx512": %s,\n' "$(bool_json "$CPU_AVX512")"
  printf '    "virtualization": "%s"\n' "$(json_escape "$CPU_VIRT")"
  printf '  },\n'
  printf '  "memory": {\n'
  printf '    "total_gib": "%s",\n' "$(json_escape "$MEM_GIB")"
  printf '    "slots_total": "%s",\n' "$(json_escape "$MEM_SLOTS_TOTAL")"
  printf '    "slots_used": "%s",\n' "$(json_escape "$MEM_SLOTS_USED")"
  printf '    "type": "%s",\n' "$(json_escape "${MEM_TYPE:-unknown}")"
  printf '    "speed": "%s"\n' "$(json_escape "${MEM_SPEED:-unknown}")"
  printf '  },\n'
  printf '  "graphics": {\n'
  printf '    "gpu_count": %s,\n' "${GPU_COUNT:-0}"
  printf '    "summary": "%s",\n' "$(json_escape "$GPU_SUMMARY")"
  printf '    "live_acceleration": "%s"\n' "$(json_escape "$GPU_ACCEL")"
  printf '  },\n'
  printf '  "storage": {\n'
  printf '    "disk_count": %s,\n' "${DISK_COUNT:-0}"
  printf '    "summary": "%s",\n' "$(json_escape "$DISK_SUMMARY")"
  printf '    "smart_status": "%s",\n' "$(json_escape "$SMART_STATUS")"
  printf '    "windows_candidate": %s,\n' "$(bool_json "$WINDOWS_DETECTED")"
  printf '    "efi_detected": %s\n' "$(bool_json "$EFI_DETECTED")"
  printf '  },\n'
  printf '  "network": {\n'
  printf '    "ethernet_present": %s,\n' "$(bool_json "$ETHERNET_PRESENT")"
  printf '    "wifi_present": %s,\n' "$(bool_json "$WIFI_PRESENT")"
  printf '    "bluetooth_present": %s,\n' "$(bool_json "$BLUETOOTH_PRESENT")"
  printf '    "connectivity_test": "%s"\n' "$(json_escape "$NETWORK_TEST")"
  printf '  },\n'
  printf '  "battery": {\n'
  printf '    "present": %s,\n' "$(bool_json "$BATTERY_PRESENT")"
  printf '    "health_percent": "%s"\n' "$(json_escape "$BATTERY_HEALTH")"
  printf '  },\n'
  printf '  "thermal": {\n'
  printf '    "summary": "%s"\n' "$(json_escape "$THERMAL_SUMMARY")"
  printf '  },\n'
  printf '  "virtualization": {\n'
  printf '    "cpu": "%s",\n' "$(json_escape "$CPU_VIRT")"
  printf '    "kvm_active": %s,\n' "$(bool_json "$KVM_PRESENT")"
  printf '    "iommu_detected": %s\n' "$(bool_json "$IOMMU_PRESENT")"
  printf '  },\n'
  printf '  "g75ia_profile": {\n'
  printf '    "ai_profile": "%s",\n' "$(json_escape "$AI_PROFILE")"
  printf '    "debian_compatibility": "%s"\n' "$(json_escape "$DEBIAN_COMPAT")"
  printf '  },\n'
  printf '  "installation_recommendation": {\n'
  printf '    "strategy": "%s",\n' "$(json_escape "$INSTALL_STRATEGY")"
  printf '    "blocking_issue": "%s",\n' "$(json_escape "$BLOCKING_ISSUE")"
  printf '    "human_validation_required": true\n'
  printf '  },\n'
  printf '  "status_counts": {\n'
  printf '    "warnings": %s,\n' "$WARN_COUNT"
  printf '    "critical": %s,\n' "$CRIT_COUNT"
  printf '    "unknown": %s\n' "$UNKNOWN_COUNT"
  printf '  },\n'
  printf '  "statuses": [\n'
  for ((i=0; i<${#STATUS_LINES[@]}; i++)); do
    IFS='|' read -r level key msg <<<"${STATUS_LINES[$i]}"
    printf '    {"level":"%s","key":"%s","message":"%s"}' \
      "$(json_escape "$level")" "$(json_escape "$key")" "$(json_escape "$msg")"
    (( i < ${#STATUS_LINES[@]}-1 )) && printf ','
    printf '\n'
  done
  printf '  ],\n'
  printf '  "privacy": {\n'
  printf '    "mandatory_redaction": true,\n'
  printf '    "serials_redacted": true,\n'
  printf '    "mac_addresses_redacted": true,\n'
  printf '    "ip_addresses_redacted": true,\n'
  printf '    "user_paths_redacted": true\n'
  printf '  }\n'
  printf '}\n'
} > "$JSON_REPORT"

# Validation JSON si jq est disponible.
if has_cmd jq; then
  if ! jq empty "$JSON_REPORT" 2>>"$ERROR_LOG"; then
    INTERNAL_ERROR=1
    status_add "CRITICAL" "json_invalid" "Le rapport JSON généré est invalide."
  fi
fi

# Empreintes.
if has_cmd sha256sum; then
  (
    cd "$REPORT_DIR" || exit 1
    sha256sum machine-report.txt machine-report.json summary.txt > SHA256SUMS
  ) 2>>"$ERROR_LOG" || INTERNAL_ERROR=1
fi

if [[ "$JSON_ONLY" -eq 0 ]]; then
  echo
  echo "Diagnostic terminé."
  echo "  Résumé : $SUMMARY_REPORT"
  echo "  Rapport : $TXT_REPORT"
  echo "  JSON    : $JSON_REPORT"
  echo "  Raw     : $RAW_DIR"
  echo
  echo "Warnings: $WARN_COUNT | Critical: $CRIT_COUNT | Unknown: $UNKNOWN_COUNT"
  echo "Aucune action d'installation n'a été lancée."
fi

if [[ "$INTERNAL_ERROR" -ne 0 ]]; then
  exit 3
elif [[ "$CRIT_COUNT" -gt 0 ]]; then
  exit 2
elif [[ "$WARN_COUNT" -gt 0 ]]; then
  exit 1
else
  exit 0
fi
