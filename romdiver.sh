#!/bin/bash

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bin"
IFDTOOL="$TOOLS_DIR/ich_descriptors_tool"
ME_CLEANER="$TOOLS_DIR/me_cleaner.py"
ROM_HEADERS="$TOOLS_DIR/romheaders"
UEFI_EXTRACT="$TOOLS_DIR/uefiextract"

INTEL_NVIDIA_PATTERN="VGA Compatible"
GOP_DRIVER_PATTERN="IntelGopDriver"
GOP_VBT_PATTERN="IntelGopVbt"

ROM_FILE=""
OUTPUT_DIR=""
DISABLE_ME=0
USER=""

set -ex

function is_new_x86_layout() {
  local src="$1"

  $IFDTOOL -f "$src"
}

function get_real_mac() {
  local src="$1"

  $IFDTOOL -f "$src" | awk -F: -v key="The MAC address might be at offset 0x1000" \
  '\$1==key {printf(\"%s:%s:%s:%s:%s:%s\", \$2, \$3, \$4, \$5, \$6, \$7)}' | tr -d '[:space:]' > $OUTPUT_DIR/macaddress
  chown "$USER:" "$OUTPUT_DIR/macaddress"
}

function disable_me() {
  local src="$1"

  if [ -f "$src" ] ; then
    $ME_CLEANER "$src"
  fi
}

function get_vgabios_name() {
  local src="$1"

  echo -n "VGABIOS_NAME=pci" > vgabios_pci.name && "$ROM_HEADERS" "$src" | grep 'Vendor ID:' | cut -d ':' -f 2 | tr -d '[:space:]' | sed -e "s/^0x//" >> vgabios_pci.name && \
  echo -n "," >> vgabios_pci.name && "$ROM_HEADERS" "$src" | grep 'Device ID:' | cut -d ':' -f 2 | tr -d '[:space:]' | sed -e "s/^0x//" >> vgabios_pci.name && echo ".rom" >> vgabios_pci.name
}

function extract_x86_blobs() {
  local src="$1"

  cp "$src" "$OUTPUT_DIR/rom.bin"
  $IFDTOOL -d -f "$OUTPUT_DIR/rom.bin"

  mv "$OUTPUT_DIR/rom.bin.BIOS.bin" "$OUTPUT_DIR/uefi.bin"
  chown "$USER:" "$OUTPUT_DIR/uefi.bin"
  mv "$OUTPUT_DIR/rom.bin.ME.bin" "$OUTPUT_DIR/me.bin"
  chown "$USER:" "$OUTPUT_DIR/me.bin"
  mv "$OUTPUT_DIR/rom.bin.GbE.bin" "$OUTPUT_DIR/gbe.bin"
  chown "$USER:" "$OUTPUT_DIR/gbe.bin"
  mv "$OUTPUT_DIR/rom.bin.Descriptor.bin" "$OUTPUT_DIR/descriptor.bin"
  chown "$USER:" "$OUTPUT_DIR/descriptor.bin"

  rm "$OUTPUT_DIR/rom.bin"
}

function extract_vgabios() {
  local src="$1"
  local pattern="$2"

  $UEFI_EXTRACT "$src" dump
  grep -rl "$pattern" "$(basename "$src.dump")" > vgabios.list

  while IFS=$'\n' read -r p < vgabios.list
  do
    cp "$p" vgabios.bin
    get_vgabios_name vgabios.bin
    source vgabios_pci.name
    rm vgabios_pci.name
    mv vgabios.bin "$OUTPUT_DIR/$VGABIOS_NAME"
    chown "$USER:" "$OUTPUT_DIR/$VGABIOS_NAME"
    sed -i '1d' vgabios.list
  done

  rm vgabios.list
  rm -rf "$(basename "$src.dump")"
}

function extract_gop() {
  local src="$1"
  local gop_pattern="*$2*"
  local vbt_pattern="*$3*"

  $UEFI_EXTRACT "$src" dump

  gop_root=$(find "$(basename "$src.dump")" -type d -name "$gop_pattern")
  gop_file="$gop_root/0 PE32 image section/body.bin"
  vbt_root=$(find "$(basename "$src.dump")" -type d -name "$vbt_pattern")
  vbt_file="$vbt_root/0 Raw section/body.bin"

  cp "$gop_file" "$OUTPUT_DIR/IntelGopDriver.efi"
  cp "$vbt_file" "$OUTPUT_DIR/IntelGopVbt"

  rm -rf "$(basename "$src.dump")"
}

if ( ! getopts "r:x:u:dh" opt); then
	echo "Usage: $(basename "$0") options ( -d disable Management Engine ) ( -r rom.bin ) ( -x output dir ) ( -u perms for user ) -h for help";
	exit $E_OPTERROR
fi

while getopts "r:x:u:dh" opt; do
     case $opt in
         d) export DISABLE_ME=1 ;;
         r) export ROM_FILE="$OPTARG" ;;
         x) export OUTPUT_DIR="$OPTARG" ;;
         u) export USER="$OPTARG" ;;
     esac
done

if is_new_x86_layout "$ROM_FILE" ; then
  get_real_mac "$ROM_FILE"
  extract_x86_blobs "$ROM_FILE"
  if [ "$DISABLE_ME" == "1" ] ; then
    disable_me "$OUTPUT_DIR/me.bin"
  fi
  extract_vgabios "$OUTPUT_DIR/uefi.bin" "$INTEL_NVIDIA_PATTERN"
  extract_gop "$OUTPUT_DIR/uefi.bin" "$GOP_DRIVER_PATTERN" "$GOP_VBT_PATTERN"
fi
