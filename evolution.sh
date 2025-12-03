#!/bin/bash

# =========================================================
# CONFIGURATION
# =========================================================
# This token was retrieved from your previous log for continuous functionality.
TG_BOT_TOKEN="5171513339:AAFMofFtLRVxsPlGhqjAFA-gjMyQLMfK2ns"
TG_BUILD_CHAT_ID="-1001769713594"
DEVICE_CODE="joyeuse"
BUILD_TARGET="Evolution-X AOSP QPR1"
ANDROID_VERSION="16"
AOSP_CLANG_ROOT="prebuilts/clang/host/linux-x86"

# SHELL CONFIGURATION
export TZ="Asia/Jakarta"
export BUILD_USERNAME=hafidz
export BUILD_HOSTNAME=alchemist

# =========================================================
# TELEGRAM FUNCTIONS
# =========================================================

# Function to safely format and send a text message to Telegram
send_telegram() {
  local chat_id="$1"
  local message="$2"

  # 1. Escape characters required by MarkdownV2 that are NOT meant to be formatters.
  # We use a comprehensive escaping logic to ensure *bold* text works.
  local escaped_message=$(echo "$message" | sed \
    -e 's/\*/\*TEMP\*/g' \
    -e 's/_/\_TEMP\_/g' \
    -e 's/\[/\\[/g' \
    -e 's/\]/\\]/g' \
    -e 's/(/\\(/g' \
    -e 's/)/\\)/g' \
    -e 's/~/\\~/g' \
    -e 's/`/\`/g' \
    -e 's/>/\\>/g' \
    -e 's/#/\\#/g' \
    -e 's/+/\\+/g' \
    -e 's/-/\\-/g' \
    -e 's/=/\\=/g' \
    -e 's/|/\\|/g' \
    -e 's/{/\\{/g' \
    -e 's/}/\\}/g' \
    -e 's/\./\\./g' \
    -e 's/!/\\!/g')

  # 2. Revert the temporary placeholders for the actual formatting characters that are intended for bold/italic.
  local re_escaped_message=$(echo "$escaped_message" | sed \
    -e 's/\*TEMP\*/\*/g' \
    -e 's/\_TEMP\_/\_/g')
  
  # 3. URL encode special characters for transmission, including newlines.
  local encoded_message=$(echo "$re_escaped_message" | sed \
    -e 's/%/%25/g' \
    -e 's/&/%26/g' \
    -e 's/+/%2b/g' \
    -e 's/ /%20/g' \
    -e 's/\"/%22/g' \
    -e 's/'"'"'/%27/g' \
    -e 's/\n/%0A/g')
    
  echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] Sending message to Telegram (${chat_id})"
  # We must explicitly set parse_mode to MarkdownV2
  curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${chat_id}" \
    -d "text=${encoded_message}" \
    -d "parse_mode=MarkdownV2" \
    -d "disable_web_page_preview=true"
}

# Function to format total seconds into HH:MM:SS string
format_duration() {
    local T=$1
    local H=$((T/3600))
    local M=$(( (T%3600)/60 ))
    local S=$((T%60))
    printf "%02d hours, %02d minutes, %02d seconds" $H $M $S
}


# =========================================================
# BUILD LOGIC FUNCTION
# =========================================================

start_build_process() {

    # --- STEP 1: START TIMER AND SEND INITIAL NOTIFICATION ---
    START_TIME=$(date +%s)

    # Message for Build Started
    local initial_msg="⚙️ *ROM Build Started!*
    *ROM:* $BUILD_TARGET
    *Android:* $ANDROID_VERSION
    *Device:* $DEVICE_CODE
    *Start Time:* $(date '+%Y-%m-%d %H:%M:%S %Z')"
    send_telegram "$TG_BUILD_CHAT_ID" "$initial_msg"
    echo "Build Started at $(date '+%Y-%m-%d %H:%M:%S')"

    # =========================================================
    # ORIGINAL BUILD STEPS
    # =========================================================

    # Init Evolution-X Android 16 branch
    repo init -u https://github.com/Evolution-X/manifest -b bq1 --git-lfs

    # Resync sources
    repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags
    /opt/crave/resync.sh
    repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags
    /opt/crave/resync.sh

    # Clean up existing trees
    echo "Starting remove repositories..."
    rm -rf device/xiaomi/joyeuse
    rm -rf vendor/xiaomi/joyeuse
    rm -rf vendor/xiaomi/miuicamera-joyeuse
    rm -rf kernel/xiaomi/sm6250
    rm -rf out/target/product/joyeuse
    rm -rf vendor/*priv*
    rm -rf vendor/evolution-priv/keys
    rm -rf hardware/xiaomi
    rm -rf hardware/sony/timekeep
    echo "Successfully deleted previous repositories."

    echo "Cloning device stuff..."
    # Device Trees
    git clone https://github.com/nekoshirro/platform_device_xiaomi_joyeuse.git device/xiaomi/joyeuse -b evox-q1 --depth 1

    # Vendor Trees
    git clone https://github.com/nekoshirro/platform_vendor_xiaomi_joyeuse.git vendor/xiaomi/joyeuse --depth 1

    # Kernel & Toolchain
    git clone https://github.com/LineageOS/android_kernel_xiaomi_sm6250.git kernel/xiaomi/sm6250 --depth 1
#   git clone https://gitlab.com/nekoshirro/Alchemist-LLVM.git prebuilts/clang/host/linux-x86/clang-alchemist -b clang-21-LTO --depth 1

    # Camera/Hardware
    git clone https://github.com/nekoshirro/platform_vendor_xiaomi_miuicamera-joyeuse.git vendor/xiaomi/miuicamera-joyeuse --depth 1
    git clone https://github.com/Evolution-X-Devices/hardware_xiaomi.git hardware/xiaomi --depth 1
    git clone https://github.com/LineageOS/android_hardware_sony_timekeep.git hardware/sony/timekeep --depth 1

    echo "Tree sync complete."

    # Sign build with custom signing keys from Evolution-X
    git clone https://github.com/Evolution-X/vendor_evolution-priv_keys-template vendor/evolution-priv/keys --depth 1
    chmod +x vendor/evolution-priv/keys/keys.sh
    pushd vendor/evolution-priv/keys
    ./keys.sh
    popd

    # Setup the build environment
    . build/envsetup.sh
    echo "Environment setup success."

    # Lunch target selection
    lunch lineage_joyeuse-bp3a-user
    echo "Lunch command executed."

    # Build ROM
    echo "========================="
    echo "Starting ROM Compilation..."
    echo "========================="
    m evolution -j$(nproc --all)

    BUILD_STATUS=$? # Capture exit code immediately

    # --- STEP 3: CALCULATE TIME AND SEND FINAL NOTIFICATION ---
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    local DURATION_FORMATTED=$(format_duration $DURATION)
    
    if [[ $BUILD_STATUS -eq 0 ]]; then
        local status_icon="✅"
        local status_text="Success"
    else
        local status_icon="❌"
        local status_text="Failure (Exit Code: $BUILD_STATUS)"
    fi

    # Final Message with Android Version
    local final_msg="${status_icon} *Build Finished!*
    *ROM:* $BUILD_TARGET
    *Android:* $ANDROID_VERSION
    *Device:* $DEVICE_CODE
    *Duration:* $DURATION_FORMATTED
    *Status:* $status_text"
    send_telegram "$TG_BUILD_CHAT_ID" "$final_msg"

    # KernelSU Function
    local ksu_warning="⚠️ *This build is using KSU-Next by default!*"
    local sukisu_warning="⚠️ *This build is using SukiSU-Ultra by default!*"
    local non_ksu_warning="🧪 *This build is using Alchemist-LTO+ without KSU-Next by default!*"
    local kernel_dir="kernel/xiaomi/sm8450"

    local current_branch=$(git -C "$kernel_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
    local warning_message=""

    echo "Current branch ($kernel_dir): $current_branch"

    if [ "$current_branch" == "ksu-next" ]; then
       warning_message="$ksu_warning"
    elif [ "$current_branch" == "bka" ]; then
       warning_message="$non_ksu_warning"
    elif [ "$current_branch" == "sukisu" ]; then
       warning_message="$sukisu_warning"
    else
       echo "Warning not sent because branch ($current_branch) is not 'ksu-next' or 'bka' 'sukisu'."
    fi

    # KernelSU Warning Message to Telegram
    if [ -n "$warning_message" ]; then
       send_telegram "$TG_BUILD_CHAT_ID" "$warning_message"
    fi

    # Toolchain Notification
    local CLANG_ALCHEMIST_DIR="$AOSP_CLANG_ROOT/clang-alchemist"
    local CLANG_AOSP_DIR="$AOSP_CLANG_ROOT/clang-r547379"
    local CLANG_BIN_PATH=""
    local TOOLCHAIN_NAME=""
    local version_output=""
    local version_message=""

    echo "Searching for Clang toolchain in $AOSP_CLANG_ROOT..."

    if [ -d "$CLANG_ALCHEMIST_DIR" ]; then
       CLANG_BIN_PATH="$CLANG_ALCHEMIST_DIR/bin/clang"
       TOOLCHAIN_NAME="🧪 Alchemist Clang"
       echo "Using Alchemist: $CLANG_BIN_PATH"
    elif [ -d "$CLANG_AOSP_DIR" ]; then
       CLANG_BIN_PATH="$CLANG_AOSP_DIR/bin/clang"
       TOOLCHAIN_NAME="Google AOSP Clang"
       echo "Using AOSP r547379: $CLANG_BIN_PATH"
    else
       echo "Error: Clang toolchain directory not found in $AOSP_CLANG_ROOT/."
    fi

    if [ ! -x "$CLANG_BIN_PATH" ]; then
       echo "Error: Clang binary is not executable: $CLANG_BIN_PATH"
    fi

    version_output=$("$CLANG_BIN_PATH" --version 2>&1 | head -n 3)
    version_output=$(echo "$version_output" | sed 's/_/\\_/g')
    version_message="*${TOOLCHAIN_NAME}*
    ${version_output}"
    send_telegram "$TG_BUILD_CHAT_ID" "$version_message"

    # Conditional Upload ROM
    if [[ $BUILD_STATUS -eq 0 ]]; then
        echo "Build successful. Starting upload script..."
        # Calls the go-up script
        rm -rf go-up*
        wget https://raw.githubusercontent.com/nekoshirro/tools-gofile/refs/heads/private/go-up
        chmod +x go-up
        ./go-up out/target/product/joyeuse/Evolution*.zip
    else
        echo "Build failed. Skipping upload."
    fi

    # Display any error logs
    echo "Here is your error"
    cat out/error.log
}

# =========================================================
# MAIN EXECUTION
# =========================================================

# Check required environment variables (optional but good practice)
start_build_process
