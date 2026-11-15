#!/bin/sh
set -eu
cd "$(dirname "$0")"
version=2.10.1
checksum=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
mkdir -p work/vendor
scratch="$(mktemp -d work/vendor/.sparkle.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
curl -fLsS --retry 2 "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" -o "$scratch/sparkle.tar.xz"
printf '%s  %s\n' "$checksum" "$scratch/sparkle.tar.xz" | shasum -a 256 -c -
mkdir "$scratch/unpacked"
tar -xf "$scratch/sparkle.tar.xz" -C "$scratch/unpacked"
test -d "$scratch/unpacked/Sparkle.framework"
test -x "$scratch/unpacked/bin/generate_appcast"
test ! -e work/vendor/Sparkle
mv "$scratch/unpacked" work/vendor/Sparkle
