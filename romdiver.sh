#!/bin/bash

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bin"
IFDTOOL="$TOOLS_DIR/ich_descriptors_tool"
ME_CLEANER="$TOOLS_DIR/me_cleaner.py"
ROM_HEADERS="$TOOLS_DIR/romheaders"
UEFI_EXTRACT="$TOOLS_DIR/uefiextract"
BIOS_EXTRACT="$TOOLS_DIR/bios_extract"
PHOENIX_EXTRACT="$TOOLS_DIR/phoenix_extract.py"

OLD_VGABIOS_PATTERN="PCIR"
INTEL_VGABIOS_PATTERN="pci8086,"
INTEL_NVIDIA_PATTERN="VGA Compatible"
GOP_DRIVER_PATTERN="IntelGopDriver"
GOP_VBT_PATTERN="IntelGopVbt"

declare -a INTEL_VGABIOS_DEVICE_ID_LIST=("0406" "0106")

ROM_FILE=""
OUTPUT_DIR=""
VERBOSE=0
USER=""

if $VERBOSE ; then
  set -x
fi

function is_new_x86_layout() {
  local src="$1"

  $IFDTOOL -f "$src"
}

function get_real_mac() {
  local src="$1"

  $IFDTOOL -f "$src" | awk -F: -v key="The MAC address might be at offset 0x1000" \
  "\$1==key {printf(\"%s:%s:%s:%s:%s:%s\", \$2, \$3, \$4, \$5, \$6, \$7)}" | tr -d '[:space:]' > $OUTPUT_DIR/macaddress
  chown "$USER:" "$OUTPUT_DIR/macaddress"
}

function get_vgabios_name() {
  local src="$1"

  echo -n "VGABIOS_NAME=pci" > vgabios_pci.name && "$ROM_HEADERS" "$src" | grep 'Vendor ID:' | cut -d ':' -f 2 | tr -d '[:space:]' | sed -e "s/^0x//" >> vgabios_pci.name && \
  echo -n "," >> vgabios_pci.name && "$ROM_HEADERS" "$src" | grep 'Device ID:' | cut -d ':' -f 2 | tr -d '[:space:]' | sed -e "s/^0x//" >> vgabios_pci.name && echo ".rom" >> vgabios_pci.name
}

function extract_x86_blobs() {
  local src="$1"

  cp -f "$src" "$OUTPUT_DIR/rom.bin"
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
    cp -f "$p" vgabios.bin
    get_vgabios_name vgabios.bin
    source vgabios_pci.name
    rm vgabios_pci.name
    mv vgabios.bin "$OUTPUT_DIR/$VGABIOS_NAME"
    chown "$USER:" "$OUTPUT_DIR/$VGABIOS_NAME"

    if [[ "$VGABIOS_NAME" == "$INTEL_VGABIOS_PATTERN"* ]] ; then
      for id in "${INTEL_VGABIOS_DEVICE_ID_LIST[@]}"
      do
        cp -f "$OUTPUT_DIR/$VGABIOS_NAME" "$OUTPUT_DIR/$INTEL_VGABIOS_PATTERN$id.rom"
      done
    fi

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

  cp -f "$gop_file" "$OUTPUT_DIR/IntelGopDriver.efi"
  cp -f "$vbt_file" "$OUTPUT_DIR/IntelGopVbt"

  rm -rf "$(basename "$src.dump")"
}

if ( ! getopts "r:x:u:vh" opt); then
	echo "Usage: $(basename "$0") options ( -r rom.bin ) ( -x output dir ) ( -u perms for user ) ( -v verbose ) -h for help";
	exit $E_OPTERROR
fi

while getopts "r:x:u:vh" opt; do
     case $opt in
         v) export VERBOSE=1 ;;
         r) export ROM_FILE="$OPTARG" ;;
         x) export OUTPUT_DIR="$OPTARG" ;;
         u) export USER="$OPTARG" ;;
     esac
done

mkdir -p "$OUTPUT_DIR" || true

if is_new_x86_layout "$ROM_FILE" ; then
  get_real_mac "$ROM_FILE"
  extract_x86_blobs "$ROM_FILE"
  extract_vgabios "$OUTPUT_DIR/uefi.bin" "$INTEL_NVIDIA_PATTERN"
  extract_gop "$OUTPUT_DIR/uefi.bin" "$GOP_DRIVER_PATTERN" "$GOP_VBT_PATTERN"
fi
