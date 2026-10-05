# gaokun3: half of the panel stays black on linux-gaokun3 7.2.8 / 7.2.9

Workaround for **Huawei MateBook E Go (gaokun3, sc8280xp, Himax HX83121A dual-DSI panel)** running the
[`linux-gaokun3`](https://aur.archlinux.org/packages/linux-gaokun3) kernel package: with 7.2.8 and 7.2.9 only one
half of the 1600x2560 panel shows the picture (the other half is black), with 7.2.3 the whole panel works.
GRUB and Windows show the whole panel, so the hardware is fine.

## What I found

The kernel package is built from `linux-rolling-stable` plus the patches of
[right-0903/linux-gaokun](https://github.com/right-0903/linux-gaokun) (`patch sets/recommended`). That patch set did not change between the 7.2.3 and
7.2.8 builds and all of its `drm/msm` patches apply cleanly to v7.2.3, v7.2.8 and v7.2.9, so the difference comes from the
upstream stable tree. Between v7.2.3 and v7.2.8 only the DSI layer of `drivers/gpu/drm/msm` changed
(`dsi/dsi_host.c`, `dsi/phy/dsi_phy_7nm.c`, `dsi/phy/dsi_phy.h`); the panel driver, `drm_mipi_dsi` and the gaokun3 DTS are functionally the same.

The suspected change is the rework of the PLL enable counting in `dsi_phy_7nm.c`
(`if (pll->pll_enable_cnt++) return;`, `phy_enable()` sets the counter to 1, `phy_disable()` to 0, new `phy->pll_data`).
gaokun3 uses bonded dual-DSI (`qcom,dual-dsi-mode`, `qcom,sync-dual-dsi`, DSI0 master, DSI1 slave) and the slave PLL is
enabled through `dsi_pll_enable_global_clk(pll_7nm->slave)`.

Reverting only `dsi_phy_7nm.c` and `dsi_phy.h` to their v7.2.3 state (the patch in this repo) brings the whole panel back
on 7.2.8. `dsi_host.c` did not need to be touched.

What I did **not** do: I did not bisect to a single upstream commit, and I do not know why the same 7.2.8 kernel
displayed the whole panel for about six days before the problem appeared (it started after a suspend/reboot cycle).
So the revert is a workaround, not a verified root-cause fix. Tested so far: one boot of 7.2.8 with the reverted module, whole panel works.

Symptoms for reference: `DSI-1` connected/enabled at 1600x2560@60, clocks of both DSI links running, no kernel errors; only
one half of the panel is lit and reacts to what is drawn to the framebuffer, the other half never lights up.

## Files

* `0001-drm-msm-dsi-phy-revert-7nm-PLL-enable-count-rework.patch` - revert for `dsi_phy_7nm.c` / `dsi_phy.h` (applies to v7.2.8 and v7.2.9).
* `build-msm.sh` - builds `msm.ko` on the tablet itself and optionally installs it.

## Rebuilding the module (after every kernel package update)

A kernel update replaces `msm.ko` (and the copy inside the initramfs), so the workaround has to be re-applied until this is fixed
upstream or in the package.

Run on the tablet, with the matching `linux-gaokun3-headers` installed:

```bash
sudo pacman -S --needed base-devel bc pahole patch curl   # gcc make flex bison python perl are in base-devel
./build-msm.sh                    # builds for the installed kernel; takes about 3 minutes, downloads about 250 MB
./build-msm.sh 7.2.9 --install    # build and install: msm.ko replaced, depmod, mkinitcpio -p linux-gaokun3
sudo reboot
```

The script copies the kernel build tree to `~/work-msm-<ver>`, takes `drivers/gpu/drm/msm` of the stable tag from GitHub, applies
the two gaokun `drm/msm` patches (`0010`, `0014`) and the revert, and builds `msm.ko` as an out-of-tree module. It refuses to
install a module with a wrong `vermagic`, and stops if the revert patch no longer applies (a sign that upstream changed the code again).
With `--install` the stock module is kept next to the new one as `msm.ko.stock-<ver>`.

To go back to the stock module:

```bash
sudo cp /lib/modules/<ver>-gaokun3/kernel/drivers/gpu/drm/msm/msm.ko.stock-<ver> \
        /lib/modules/<ver>-gaokun3/kernel/drivers/gpu/drm/msm/msm.ko
sudo depmod <ver>-gaokun3 && sudo mkinitcpio -p linux-gaokun3
```

Or simply stay on 7.2.3 (`IgnorePkg = linux-gaokun3 linux-gaokun3-headers` in `/etc/pacman.conf`).

## Notes

* Do not unload/reload `panel_himax_hx83121a` or `msm` at runtime: the DRM device does not come back, a reboot is needed.
* The patch is a revert of upstream code and therefore GPL-2.0-only, like the kernel.
