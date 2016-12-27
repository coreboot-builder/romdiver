#!/bin/bash

TOOLS_DIR="$PWD/bin"
FIREJAIL=$(which firejail)
NC=$(which nc)
IFDTOOL="$TOOLS_DIR/ich_descriptors_tool"
ME_CLEANER="$TOOLS_DIR/me_cleaner.py"
ROM_HEADERS="$TOOLS_DIR/romheaders"
UEFI_EXTRACT="$TOOLS_DIR/uefiextract"

set -e

function execute_command() {
  local cmd="$1"
  local dest="$2"
  local file="$3"
  local uuid=$(uuidgen)

  mkfifo "/tmp/network-$uuid"
  ($NC -l 127.0.0.1 9999 < "/tmp/network-$uuid" > "$dest") &
  $FIREJAIL --caps.drop=all --seccomp --ipc-namespace \
    --overlay-tmpfs --private-dev --private-tmp \
    -c "$cmd && cat $file | nc 127.0.0.1 9999 > /tmp/network-$uuid"
  killall -9 -q nc
  rm "/tmp/network-$uuid"
}

function is_new_x86_layout() {
  local src="$1"
  local result=""

  execute_command "$IFDTOOL -f $src && echo $? > result" "$SECURE_EXTRACT_DIR/result" "result"
  result=$(cat "$SECURE_EXTRACT_DIR/result")
  if [ "$result" == "1" ] ; then
    rm "$SECURE_EXTRACT_DIR/result"
    return 0
  fi

  rm "$SECURE_EXTRACT_DIR/result"
  return 1
}

function get_real_mac() {
  local src="$1"

  execute_command "$IFDTOOL -f $src | awk -F: -v key=\"The MAC address might be at offset 0x1000\" \
  '\$1==key {printf(\"%s:%s:%s:%s:%s:%s\", \$2, \$3, \$4, \$5, \$6, \$7)}' | tr -d '[:space:]' > macaddress" "$SECURE_EXTRACT_DIR/macaddress" "macaddress"
}

function disable_me() {
  if [ -f "$SECURE_EXTRACT_DIR/me.bin" ] ; then
    execute_command "$ME_CLEANER $SECURE_EXTRACT_DIR/me.bin" "$SECURE_EXTRACT_DIR/me.bin" "$src"
  fi
}

function get_vgabios_name() {
  local src="$1"

  execute_command "echo -n \"VGABIOS_NAME=pci\" > vgabios_pci.name && $ROM_HEADERS $src | grep 'Vendor ID:' | cut -d ':' -f 2 | tr -d '[:space:]' | sed -e \"s/^0x//\" >> vgabios_pci.name && \
  echo -n \",\" >> vgabios_pci.name && $ROM_HEADERS $src | grep 'Device ID:' | cut -d ':' -f 2 | tr -d '[:space:]' | sed -e \"s/^0x//\" >> vgabios_pci.name && echo \".rom\" >> vgabios_pci.name" \
  "$SECURE_EXTRACT_DIR/vgabios_pci.name" "vgabios_pci.name"
}

function extract_x86_blobs() {
  local src="$1"

  execute_command "$IFDTOOL -d -f $src" "$SECURE_EXTRACT_DIR/descriptor.bin" "$src.Descriptor.bin"
  execute_command "$IFDTOOL -d -f $src" "$SECURE_EXTRACT_DIR/me.bin" "$src.ME.bin"
  execute_command "$IFDTOOL -d -f $src" "$SECURE_EXTRACT_DIR/gbe.bin" "$src.GbE.bin"
  execute_command "$IFDTOOL -d -f $src" "$SECURE_EXTRACT_DIR/uefi.bin" "$src.BIOS.bin"
}

function extract_vgabios() {
  local src="$1"
  local pattern="$2"

  execute_command "$UEFI_EXTRACT $src dump && grep -rl \"$pattern\" uefi.bin.dump > vgabios.list" "$SECURE_EXTRACT_DIR/vgabios.list" "vgabios.list"
  while IFS=$'\n' read -r p < "$SECURE_EXTRACT_DIR/vgabios.list"
  do
    file="${p// /\\ }"
    execute_command "$UEFI_EXTRACT $src dump" "$SECURE_EXTRACT_DIR/vgabios.bin" "$file"
    get_vgabios_name "$SECURE_EXTRACT_DIR/vgabios.bin"
    source "$SECURE_EXTRACT_DIR/vgabios_pci.name"
    rm "$SECURE_EXTRACT_DIR/vgabios_pci.name"
    mv "$SECURE_EXTRACT_DIR/vgabios.bin" "$SECURE_EXTRACT_DIR/$VGABIOS_NAME"
  done

  rm "$SECURE_EXTRACT_DIR/vgabios.list"
}

if ( ! getopts "r:x:dh" opt); then
	echo "Usage: $(basename "$0") options (-d disable Management Engine) (-r rom.bin) (-x extract directory) -h for help";
	exit $E_OPTERROR
fi

while getopts "r:x:dh" opt; do
     case $opt in
         d) export DISABLE_ME=1 ;;
         r) export ROM_FILE="$OPTARG" ;;
         x) export SECURE_EXTRACT_DIR="$OPTARG" ;;
     esac
done

if [ -d "$SECURE_EXTRACT_DIR" ] ; then
  if is_new_x86_layout "$ROM_FILE" ; then
    get_real_mac "$ROM_FILE"
    extract_x86_blobs "$ROM_FILE"
    if DISABLE_ME ; then
      disable_me
    fi
    extract_vgabios "$SECURE_EXTRACT_DIR/uefi.bin" "VGA Compatible"
  fi
fi
