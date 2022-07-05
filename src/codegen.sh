#!/usr/bin/env bash
cd "${BASH_SOURCE[0]%/*}" || exit 1
data=\
"#include <sodium.h>
type
  SignPK* = array[crypto_sign_PUBLICKEYBYTES, uint8]
  SignSK  = array[crypto_sign_SECRETKEYBYTES, uint8]
  EphPK   = array[crypto_box_PUBLICKEYBYTES, uint8]
  EphSK   = array[crypto_box_SECRETKEYBYTES, uint8]
  SymK    = array[crypto_secretstream_xchacha20poly1305_KEYBYTES, uint8]
  Header  = array[crypto_secretstream_xchacha20poly1305_HEADERBYTES, uint8]"
len="$(wc -l <<< "$data")"
result="$(tcc -E - <<< "$data" | tail -n "$((len - 1))")"
tmp="$(mktemp)"
awk '
BEGIN {
	normal = 1
}

/# CODEGEN END/ {
	normal = 1
}

{
	if(normal) {
		print
	}
}

/# CODEGEN START/ {
	normal = 0
	print "'"${result//$'\n'/\\n}"'"
}

' "zeolite.nim" > "$tmp"
mv "$tmp" "zeolite.nim"
