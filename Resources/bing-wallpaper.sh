#!/bin/bash

# ==========================================
# Bing Daily Wallpaper Script
# ==========================================
# Downloads the Bing daily wallpaper and sets it on all screens
# ==========================================

# Set PATH to include Homebrew and system binaries
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Get script directory (used to locate add-watermark.swift alongside this script)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Paths — overridable via environment (set by the app)
LOG_DIR="${BINGWALLPAPER_LOG_DIR:-${HOME}/Library/Logs/BingWallpaper}"
WALLPAPER_DIR="${BINGWALLPAPER_WALLPAPER_DIR:-${HOME}/Pictures/BingWallpaper}"
LOG_RETENTION="${BINGWALLPAPER_LOG_RETENTION:-7}"
WATERMARK="${BINGWALLPAPER_WATERMARK:-1}"

# Create directories if missing
mkdir -p "${LOG_DIR}"
mkdir -p "${WALLPAPER_DIR}"
TODAY=$(date +"%Y-%m-%d")
WALLPAPER_FILE="${WALLPAPER_DIR}/bing-${TODAY}.jpg"

# Generate timestamped log file
TIMESTAMP=$(date +"%m-%d-%Y-%H%M%S")
LOG_FILE="${LOG_DIR}/BingWallpaper_${TIMESTAMP}.log"

# Bing image API
MARKET="${BINGWALLPAPER_MARKET:-en-US}"
RESOLUTION="${BINGWALLPAPER_RESOLUTION:-UHD}"
BING_API="https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=${MARKET}"
BING_BASE="https://www.bing.com"

# Log function
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

# Function to purge logs older than 7 days
purge_old_logs() {
    if [ -d "${LOG_DIR}" ]; then
        find "${LOG_DIR}" -name "BingWallpaper_*.log" -type f -mtime "+${LOG_RETENTION}" -delete
    fi
}

# Purge old logs before starting
purge_old_logs

# Start
log_message "=========================================="
log_message "Starting Bing Daily Wallpaper Update"
log_message "=========================================="

# Fetch Bing API JSON
log_message "Fetching Bing wallpaper metadata..."
API_RESPONSE=$(curl -s --max-time 15 "${BING_API}" 2>/dev/null)

if [ -z "${API_RESPONSE}" ]; then
    log_message "ERROR: Failed to fetch Bing API response"
    log_message "=========================================="
    exit 1
fi

# Extract image URL path from JSON
IMAGE_PATH=$(echo "${API_RESPONSE}" | /usr/bin/python3 -c \
    "import sys, json; data=json.load(sys.stdin); print(data['images'][0]['url'])" 2>/dev/null)

if [ -z "${IMAGE_PATH}" ]; then
    log_message "ERROR: Failed to parse image URL from API response"
    log_message "=========================================="
    exit 1
fi

# Build full image URL with requested resolution
IMAGE_URL="${BING_BASE}${IMAGE_PATH}"
IMAGE_URL=$(echo "${IMAGE_URL}" | sed "s/[0-9]\{3,4\}x[0-9]\{3,4\}/${RESOLUTION}/")

log_message "Image URL: ${IMAGE_URL}"

# Download the wallpaper
log_message "Downloading wallpaper..."
HTTP_CODE=$(curl -s --max-time 30 -w "%{http_code}" -o "${WALLPAPER_FILE}" "${IMAGE_URL}" 2>/dev/null)

if [ "${HTTP_CODE}" != "200" ] || [ ! -f "${WALLPAPER_FILE}" ]; then
    log_message "ERROR: Failed to download wallpaper (HTTP ${HTTP_CODE})"
    log_message "=========================================="
    exit 1
fi

FILE_SIZE=$(du -h "${WALLPAPER_FILE}" | cut -f1)
log_message "Wallpaper downloaded: ${WALLPAPER_FILE} (${FILE_SIZE})"

# Remove all previous wallpaper files, keeping only today's
find "${WALLPAPER_DIR}" -name "bing-*.jpg" -type f ! -name "bing-${TODAY}.jpg" -delete

# Extract title and description
IMAGE_TITLE=$(echo "${API_RESPONSE}" | /usr/bin/python3 -c \
    "import sys, json; data=json.load(sys.stdin); print(data['images'][0].get('title','Bing Daily Wallpaper'))" 2>/dev/null)
IMAGE_TITLE="${IMAGE_TITLE:-Bing Daily Wallpaper}"
IMAGE_DESC=$(echo "${API_RESPONSE}" | /usr/bin/python3 -c \
    "import sys, json; data=json.load(sys.stdin); print(data['images'][0].get('copyright',''))" 2>/dev/null)
log_message "Title: ${IMAGE_TITLE}"
log_message "Description: ${IMAGE_DESC}"

# Stamp title + description as a subtle watermark on the lower-left (optional)
if [ "${WATERMARK}" = "1" ]; then
    log_message "Adding watermark..."
    /usr/bin/swift "${SCRIPT_DIR}/add-watermark.swift" "${WALLPAPER_FILE}" "${IMAGE_TITLE}" "${IMAGE_DESC}" 2>&1 | tee -a "${LOG_FILE}"
fi

# Set wallpaper on all desktops
log_message "Setting wallpaper on all screens..."
osascript -e "tell application \"System Events\" to set picture of every desktop to \"${WALLPAPER_FILE}\"" 2>&1 | tee -a "${LOG_FILE}"

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log_message "ERROR: Failed to set wallpaper via System Events"
    log_message "=========================================="
    exit 1
fi

# Force WallpaperAgent to re-read from disk (handles same-path cache)
# Sleep briefly so osascript can finish writing the preference before the agent restarts
sleep 2
killall WallpaperAgent 2>/dev/null || true

log_message "Wallpaper set successfully on all screens"

# Done
log_message "=========================================="
log_message "Bing Daily Wallpaper Update Completed"
log_message "=========================================="

exit 0
