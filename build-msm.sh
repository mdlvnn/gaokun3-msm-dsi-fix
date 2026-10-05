#!/bin/bash
# Rebuild msm.ko for linux-gaokun3 with the dsi_phy_7nm PLL-enable-count rework reverted.
# Run ON THE TABLET (native arm64, needs: gcc make bc pahole flex bison python3 perl patch curl).
#
#   ./build-msm.sh              # build for the installed kernel (pacman -Q linux-gaokun3)
#   ./build-msm.sh 7.2.9        # build for a specific version (its linux-gaokun3-headers must be installed)
#   ./build-msm.sh 7.2.9 --install   # build and install (needs sudo): replaces msm.ko, depmod, mkinitcpio
#
# What it does:
#   1. copies the installed kernel build tree (/usr/lib/modules/<ver>-gaokun3/build) to a work dir
#   2. downloads drivers/gpu/drm/msm of stable tag v<ver> (github.com/gregkh/linux)
#   3. applies the two gaokun msm patches (0010, 0014) from right-0903/linux-gaokun, then 0001-*.patch from this dir
#   4. builds msm.ko as an out-of-tree module against that build tree
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
V=${1:-$(pacman -Q linux-gaokun3 | awk '{print $2}' | cut -d- -f1)}
INSTALL=${2:-}
KREL=$V-gaokun3
W=${W:-$HOME/work-msm-$V}
BUILD_SRC=/usr/lib/modules/$KREL/build
GK=https://raw.githubusercontent.com/right-0903/linux-gaokun/HEAD/patch%20sets/recommended
PATCHES=(
  0010-drm-msm-dpu-encoder-fix-DSC-width-truncation.patch
  0014-drm-msm-dsi-avoid-link-clock-toggles-during-active-v.patch
)

[ -d "$BUILD_SRC" ] || { echo "no $BUILD_SRC: install linux-gaokun3-headers $V first"; exit 1; }
[ "$(uname -m)" = aarch64 ] || { echo "run this on the aarch64 tablet"; exit 1; }
echo "== kernel $KREL, work dir $W"

rm -rf "$W"; mkdir -p "$W/src"
echo "== 1/4 copy build tree"
cp -a "$BUILD_SRC" "$W/build"
[ -d "$W/build/drivers/gpu/drm/msm" ] && mv "$W/build/drivers/gpu/drm/msm" "$W/build/drivers/gpu/drm/msm.orig"

echo "== 2/4 fetch drivers/gpu/drm/{msm,*.h} of v$V (about 250 MB download, only the needed files are kept)"
curl -fL "https://github.com/gregkh/linux/archive/refs/tags/v$V.tar.gz" \
  | tar -xz -C "$W/src" --strip-components=1 --wildcards \
      '*/drivers/gpu/drm/msm' '*/drivers/gpu/drm/*.h'

echo "== 3/4 apply patches"
for p in "${PATCHES[@]}"; do
  curl -fsSL "$GK/$p" -o "$W/$p"
  patch -p1 -d "$W/src" < "$W/$p"
done
REVERT=$(ls "$HERE"/0001-*.patch)
if ! patch -p1 -d "$W/src" --dry-run < "$REVERT" >/dev/null; then
  echo "The revert patch does NOT apply to v$V. Upstream changed dsi_phy_7nm.c again (maybe fixed?)."
  echo "Check first whether stock 7.2.x still shows half a screen; otherwise rebase $REVERT."
  exit 2
fi
patch -p1 -d "$W/src" < "$REVERT"

echo "== 4/4 build"
ln -s "$W/src/drivers/gpu/drm/msm" "$W/build/drivers/gpu/drm/msm"   # trace headers are looked up relative to the tree
( cd "$W/src/drivers/gpu/drm/msm" && make -C "$W/build" M="$PWD" modules -j"$(nproc)" )
KO=$W/src/drivers/gpu/drm/msm/msm.ko
echo "built: $KO ($(stat -c %s "$KO") bytes), vermagic: $(modinfo -F vermagic "$KO")"
[ "$(modinfo -F vermagic "$KO" | cut -d' ' -f1)" = "$KREL" ] || { echo "vermagic mismatch"; exit 3; }

DEST=/lib/modules/$KREL/kernel/drivers/gpu/drm/msm/msm.ko
if [ "$INSTALL" = --install ]; then
  sudo cp -an "$DEST" "$DEST.stock-$V" 2>/dev/null || true       # keep the stock module next to it
  sudo install -m644 "$KO" "$DEST"
  sudo depmod "$KREL"
  sudo mkinitcpio -p linux-gaokun3          # msm.ko is also inside the initramfs
  echo "installed. reboot to use it. Stock module saved as $DEST.stock-$V"
else
  echo
  echo "to install:  sudo install -m644 $KO $DEST && sudo depmod $KREL && sudo mkinitcpio -p linux-gaokun3"
  echo "or rerun:    $0 $V --install"
fi
