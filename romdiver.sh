#!/bin/bash

SECURE_EXTRACT_DIR="$PWD/tmp"
ETHERNET_DEV="eth0"
TOOLS_DIR="$PWD/bin"
FIREJAIL=$(which firejail)
NC=$(which nc)
IFDTOOL="$TOOLS_DIR/ich_descriptors_tool"
ME_CLEANER="$TOOLS_DIR/me_cleaner.py"
ROM_HEADERS="$TOOLS_DIR/romheaders"
UEFI_EXTRACT="$TOOLS_DIR/uefiextract"

function execute_command() {
  local cmd="$1"
  local dest="$2"
  local file="$3"
  local uuid=$(uuidgen)

  mkfifo "$PWD/network-$uuid"
  ($NC -s localhost -l -p 9999 < "$PWD/network-$uuid" > "$dest") &
  $FIREJAIL --caps.drop=all --seccomp --ipc-namespace \
    --overlay-tmpfs --private-dev --private-tmp \
    -c "$cmd && cat $file | nc localhost 9999 > $PWD/network-$uuid"
  killall -q nc
  rm "$PWD/network-$uuid"
}

function is_x86_layout() {
  local src="$1"
  local result=""

  execute_command "$IFDTOOL -f $src && echo $? > result" "$SECURE_EXTRACT_DIR/result" "result"
  result=$(cat "$SECURE_EXTRACT_DIR/result")
  if [ "$result" == "1" ] ; then
    return 0
  fi

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

  execute_command "echo \"VGABIOS_NAME=pci\" > vgabios_pci.name && $ROM_HEADERS $src | grep 'Vendor ID:' | cut -d ':' -f 2 | tr -d '[:space:]' >> vgabios_pci.name && \
  echo \",\" >> vgabios_pci.name && $ROM_HEADERS $src | grep 'Device ID:' | cut -d ':' -f 2 | tr -d '[:space:]' >> vgabios_pci.name && echo \".rom\" >> vgabios_pci.name" \
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

  execute_command "$UEFI_EXTRACT $src dump && grep -rl \"$pattern\" $src.dump > vgabios.list" "$SECURE_EXTRACT_DIR/vgabios.list" "vgabios.list"
  IFS=$'\n'
  for p in $(cat "$SECURE_EXTRACT_DIR/vgabios.list")
  do
    get_vgabios_name "$file"
    source "$SECURE_EXTRACT_DIR/vgabios_pci.name"
    rm "$SECURE_EXTRACT_DIR/vgabios_pci.name"
    cp "$file" "$SECURE_EXTRACT_DIR/$VGABIOS_NAME"
  done
}

mkdir -p "$SECURE_EXTRACT_DIR"
