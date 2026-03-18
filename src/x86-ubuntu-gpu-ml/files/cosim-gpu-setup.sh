#!/bin/bash
# Guest-side MI300X co-simulation GPU initialization.
# Called by cosim-gpu-setup.service at boot.
# Detects all AMD GPU PCI devices and initializes each one.

set -e

export LD_LIBRARY_PATH=/opt/rocm/lib:${LD_LIBRARY_PATH:-}
export HSA_ENABLE_INTERRUPT=0
export HCC_AMDGPU_TARGET=gfx942

ROM_PATH="/root/roms/mi300.rom"
FW_DISCOVERY="/usr/lib/firmware/amdgpu/mi300_discovery"
FW_LINK="/usr/lib/firmware/amdgpu/ip_discovery.bin"

# Load VGA ROM to legacy address 0xC0000 (required by amdgpu driver)
if [ -f "$ROM_PATH" ]; then
    dd if="$ROM_PATH" of=/dev/mem bs=1k seek=768 count=128 2>/dev/null
    echo "cosim-gpu-setup: VGA ROM loaded"
else
    echo "cosim-gpu-setup: WARNING: $ROM_PATH not found" >&2
fi

# Link IP discovery firmware
if [ -e "$FW_DISCOVERY" ]; then
    rm -f "$FW_LINK"
    ln -s "$FW_DISCOVERY" "$FW_LINK"
    echo "cosim-gpu-setup: IP discovery firmware linked"
fi

# Load amdgpu driver
if [ -f /home/gem5/load_amdgpu.sh ]; then
    sh /home/gem5/load_amdgpu.sh
elif [ -f "/lib/modules/$(uname -r)/updates/dkms/amdgpu.ko" ]; then
    modprobe amdgpu ip_block_mask=0x67 ras_enable=0 discovery=2
else
    echo "cosim-gpu-setup: ERROR: amdgpu.ko not found" >&2
    exit 1
fi

# Verify: count initialized AMD GPUs via DRM
EXPECTED=$(lspci -d 1002: | wc -l)
INITIALIZED=0
for card in /sys/class/drm/card[0-9]*; do
    if [ -d "$card/device" ] && [ -f "$card/device/vendor" ]; then
        vendor=$(cat "$card/device/vendor" 2>/dev/null)
        if [ "$vendor" = "0x1002" ]; then
            INITIALIZED=$((INITIALIZED + 1))
        fi
    fi
done

echo "cosim-gpu-setup: $INITIALIZED/$EXPECTED GPU(s) initialized"
if [ "$INITIALIZED" -lt "$EXPECTED" ]; then
    echo "cosim-gpu-setup: WARNING: not all GPUs initialized" >&2
    exit 1
fi
