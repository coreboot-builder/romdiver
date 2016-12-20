#!/bin/bash

SECURE_EXTRACT_DIR="$PWD/tmp"
ETHERNET_DEV="eth0"
TOOLS_DIR="$PWD/bin"
FIREJAIL=$(which firejail)
FIREJAIL_FEATUES="--caps.drop=all --seccomp --ipc-namespace \
--overlay-tmpfs --private-dev --private-tmp"
NC=$(which nc)
IFDTOOL="$TOOLS_DIR/ich_descriptors_tool"
ME_CLEANER="$TOOLS_DIR/me_cleaner.py"
ROM_HEADERS="$TOOLS_DIR/romheaders"
UEFI_EXTRACT="$TOOLS_DIR/uefiextract"
UEFI_FIND="$TOOLS_DIR/uefifind"

function execute_command() {
  local cmd="$1"
  local dest="$2"
  local file="$3"
  local uuid=$(uuidgen)

  mkfifo "$PWD/network-$uuid"
  ($NC -l -p 9999 < "$PWD/network-$uuid" > "$dest") &
  $FIREJAIL "$FIREJAIL_FEATUES" \
    -c "$cmd && cat $file | nc localhost 9999 > $PWD/network-$uuid"
  killall nc
  rm "$PWD/network-$uuid"
}

function is_x86_layout() {
  local src="$1"
  local result=""

  execute_command "$IFDTOOL -f $src && echo $? > result" "$SECURE_EXTRACT_DIR/result" "result"
  result=$(cat "$SECURE_EXTRACT_DIR/result")
  if "$result" == "1" ; then
    return 0
  fi

  return 1
}

function get_real_mac() {
  local src="$1"

  execute_command "$IFDTOOL -f $src | awk -F: -v key=\"The MAC address might be \at offset 0x1000\" \
  '$1==key {printf(\"%s:%s:%s:%s:%s:%s\", $2, $3, $4, $5, $6, $7)}' > macaddress" "$SECURE_EXTRACT_DIR/macaddress" "macaddress"
}

function strip_me() {
  local src="$1"

  execute_command "$ME_CLEANER $src" "$SECURE_EXTRACT_DIR/me.bin" "$src"
}

function extract_x86_blobs() {
  local src="$1"

  execute_command "$IFDTOOL -d -f $src" "$SECURE_EXTRACT_DIR/descriptor.bin" "$src.Descriptor.bin"
  execute_command "$IFDTOOL -d -f $src" "$SECURE_EXTRACT_DIR/me.bin" "$src.ME.bin"
  execute_command "$IFDTOOL -d -f $src" "$SECURE_EXTRACT_DIR/gbe.bin" "$src.GbE.bin"
  execute_command "$IFDTOOL -d -f $src" "$SECURE_EXTRACT_DIR/uefi.bin" "$src.BIOS.bin"
}

mkdir -p "$SECURE_EXTRACT_DIR"
is_x86_layout "$1"
