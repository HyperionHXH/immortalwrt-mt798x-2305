#!/usr/bin/env bash
set -euo pipefail

OPENWRT_DIR="${1:-${OPENWRT_DIR:-$PWD}}"
MT7981_DTS_DIR="$OPENWRT_DIR/target/linux/mediatek/files-5.4/arch/arm64/boot/dts/mediatek"
MT7981_IMAGE="$OPENWRT_DIR/target/linux/mediatek/image/mt7981.mk"
MT7981_NETWORK="$OPENWRT_DIR/target/linux/mediatek/mt7981/base-files/etc/board.d/02_network"
MT7981_UPGRADE="$OPENWRT_DIR/target/linux/mediatek/mt7981/base-files/lib/upgrade/platform.sh"
MT7981_PREINIT="$OPENWRT_DIR/target/linux/mediatek/mt7981/base-files/lib/preinit/90_extract_caldata"

if [ ! -d "$OPENWRT_DIR/target/linux/mediatek" ]; then
  echo "error: OPENWRT_DIR does not look like an ImmortalWrt tree: $OPENWRT_DIR" >&2
  exit 1
fi

insert_before_marker() {
  local file="$1"
  local marker="$2"
  local block_file="$3"
  local tmp

  tmp="$(mktemp)"
  awk -v marker="$marker" -v block_file="$block_file" '
    BEGIN {
      while ((getline line < block_file) > 0) {
        block = block line ORS
      }
      close(block_file)
    }
    index($0, marker) && !done {
      printf "%s", block
      done = 1
    }
    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

insert_after_marker() {
  local file="$1"
  local marker="$2"
  local block_file="$3"
  local tmp

  tmp="$(mktemp)"
  awk -v marker="$marker" -v block_file="$block_file" '
    BEGIN {
      while ((getline line < block_file) > 0) {
        block = block line ORS
      }
      close(block_file)
    }
    { print }
    index($0, marker) && !done {
      printf "%s", block
      done = 1
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

mkdir -p "$MT7981_DTS_DIR"

cat > "$MT7981_DTS_DIR/mt7981-cmcc-xr30.dtsi" <<'DTS'
/dts-v1/;
#include "mt7981.dtsi"

/ {
	aliases {
		led-boot = &red_led;
		led-failsafe = &red_led;
		led-running = &white_led;
		led-upgrade = &red_led;
	};

	memory {
		reg = <0 0x40000000 0 0x20000000>;
	};

	leds {
		compatible = "gpio-leds";

		red_led: red {
			label = "xr30:red";
			gpios = <&pio 35 GPIO_ACTIVE_LOW>;
		};

		white_led: white {
			label = "xr30:white";
			gpios = <&pio 34 GPIO_ACTIVE_LOW>;
		};
	};

	gpio-keys {
		compatible = "gpio-keys";

		reset {
			label = "reset";
			linux,code = <KEY_RESTART>;
			gpios = <&pio 1 GPIO_ACTIVE_LOW>;
		};

		mesh {
			label = "mesh";
			gpios = <&pio 0 GPIO_ACTIVE_LOW>;
			linux,code = <BTN_9>;
			linux,input-type = <EV_SW>;
		};
	};
};

&uart0 {
	status = "okay";
};

&watchdog {
	status = "okay";
};

&eth {
	status = "okay";

	gmac0: mac@0 {
		compatible = "mediatek,eth-mac";
		reg = <0>;
		phy-mode = "2500base-x";

		fixed-link {
			speed = <2500>;
			full-duplex;
			pause;
		};
	};

	gmac1: mac@1 {
		compatible = "mediatek,eth-mac";
		label = "wan";
		reg = <1>;
		phy-mode = "gmii";
		phy-handle = <&phy0>;
	};

	mdio: mdio-bus {
		#address-cells = <1>;
		#size-cells = <0>;

		phy0: ethernet-phy@0 {
			compatible = "ethernet-phy-id03a2.9461";
			reg = <0>;
			phy-mode = "gmii";
			nvmem-cells = <&phy_calibration>;
			nvmem-cell-names = "phy-cal-data";
		};

		switch@0 {
			compatible = "mediatek,mt7531";
			reg = <31>;
			reset-gpios = <&pio 39 0>;

			ports {
				#address-cells = <1>;
				#size-cells = <0>;

				port@0 {
					reg = <0>;
					label = "lan1";
				};

				port@1 {
					reg = <1>;
					label = "lan2";
				};

				port@2 {
					reg = <2>;
					label = "lan3";
				};

				port@6 {
					reg = <6>;
					label = "cpu";
					ethernet = <&gmac0>;
					phy-mode = "2500base-x";

					fixed-link {
						speed = <2500>;
						full-duplex;
						pause;
					};
				};
			};
		};
	};
};

&hnat {
	mtketh-wan = "eth1";
	mtketh-lan = "lan";
	mtketh-max-gmac = <2>;
	status = "okay";
};

&xhci {
	mediatek,u3p-dis-msk = <0x0>;
	phys = <&u2port0 PHY_TYPE_USB2>,
		   <&u3port0 PHY_TYPE_USB3>;
	status = "okay";
};
DTS

cat > "$MT7981_DTS_DIR/mt7981-cmcc-xr30.dts" <<'DTS'
/dts-v1/;
#include "mt7981-cmcc-xr30.dtsi"

/ {
	model = "CMCC XR30";
	compatible = "cmcc,xr30", "mediatek,mt7981";

	chosen {
		bootargs = "console=ttyS0,115200n1 loglevel=8 \
			    earlycon=uart8250,mmio32,0x11002000";
	};

	nmbm_spim_nand {
		compatible = "generic,nmbm";
		#address-cells = <1>;
		#size-cells = <1>;

		lower-mtd-device = <&spi_nand>;
		forced-create;

		partitions {
			compatible = "fixed-partitions";
			#address-cells = <1>;
			#size-cells = <1>;

			partition@0 {
				label = "BL2";
				reg = <0x0 0x100000>;
			};

			partition@100000 {
				label = "u-boot-env";
				reg = <0x100000 0x80000>;
			};

			partition@180000 {
				label = "Factory";
				reg = <0x180000 0x200000>;
			};

			partition@380000 {
				label = "FIP";
				reg = <0x380000 0x200000>;
			};

			partition@580000 {
				label = "ubi";
				reg = <0x580000 0x7200000>;
			};
		};
	};
};

&spi0 {
	pinctrl-names = "default";
	pinctrl-0 = <&spi0_flash_pins>;
	status = "okay";

	spi_nand: spi_nand@0 {
		#address-cells = <1>;
		#size-cells = <1>;
		compatible = "spi-nand";
		reg = <0>;
		spi-max-frequency = <52000000>;
		spi-tx-bus-width = <4>;
		spi-rx-bus-width = <4>;
		spi-cal-enable;
		spi-cal-mode = "read-data";
		spi-cal-datalen = <7>;
		spi-cal-data = /bits/ 8 <0x53 0x50 0x49 0x4E 0x41 0x4E 0x44>;
		spi-cal-addrlen = <5>;
		spi-cal-addr = /bits/ 32 <0x0 0x0 0x0 0x0 0x0>;
	};
};

&pio {
	spi0_flash_pins: spi0-pins {
		mux {
			function = "spi";
			groups = "spi0", "spi0_wp_hold";
		};

		conf-pu {
			pins = "SPI0_CS", "SPI0_HOLD", "SPI0_WP";
			drive-strength = <MTK_DRIVE_8mA>;
			bias-pull-up = <MTK_PUPD_SET_R1R0_11>;
		};

		conf-pd {
			pins = "SPI0_CLK", "SPI0_MOSI", "SPI0_MISO";
			drive-strength = <MTK_DRIVE_8mA>;
			bias-pull-down = <MTK_PUPD_SET_R1R0_11>;
		};
	};
};
DTS

cat > "$MT7981_DTS_DIR/mt7981-cmcc-xr30-emmc.dts" <<'DTS'
/dts-v1/;
#include "mt7981-cmcc-xr30.dtsi"

/ {
	model = "CMCC XR30 eMMC version (RAX3000Z Enhanced version)";
	compatible = "cmcc,xr30-emmc", "mediatek,mt7981";

	chosen {
		bootargs = "console=ttyS0,115200n1 loglevel=8 \
			    earlycon=uart8250,mmio32,0x11002000 \
			    root=PARTLABEL=rootfs rootwait rootfstype=squashfs,f2fs";
	};
};

&mmc0 {
	bus-width = <8>;
	cap-mmc-highspeed;
	max-frequency = <52000000>;
	no-sd;
	no-sdio;
	non-removable;
	pinctrl-names = "default", "state_uhs";
	pinctrl-0 = <&mmc0_pins_default>;
	pinctrl-1 = <&mmc0_pins_uhs>;
	vmmc-supply = <&reg_3p3v>;
	status = "okay";
};

&pio {
	mmc0_pins_default: mmc0-pins-default {
		mux {
			function = "flash";
			groups = "emmc_45";
		};
	};

	mmc0_pins_uhs: mmc0-pins-uhs {
		mux {
			function = "flash";
			groups = "emmc_45";
		};
	};
};
DTS

if ! grep -q '^define Device/cmcc_xr30$' "$MT7981_IMAGE"; then
  block="$(mktemp)"
  cat > "$block" <<'DEVICE'
define Device/cmcc_xr30
  DEVICE_VENDOR := CMCC
  DEVICE_MODEL := XR30 NAND
  DEVICE_DTS := mt7981-cmcc-xr30
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  DEVICE_PACKAGES := $(MT7981_USB_PKGS) luci-app-ksmbd luci-i18n-ksmbd-zh-cn ksmbd-utils
  SUPPORTED_DEVICES := cmcc,xr30
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 116736k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += cmcc_xr30

define Device/cmcc_xr30-emmc
  DEVICE_VENDOR := CMCC
  DEVICE_MODEL := XR30 eMMC
  DEVICE_DTS := mt7981-cmcc-xr30-emmc
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  SUPPORTED_DEVICES := cmcc,xr30-emmc
  DEVICE_PACKAGES := $(MT7981_USB_PKGS) f2fsck losetup mkf2fs kmod-fs-f2fs kmod-mmc \
	luci-app-ksmbd luci-i18n-ksmbd-zh-cn ksmbd-utils
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += cmcc_xr30-emmc

DEVICE
  insert_before_marker "$MT7981_IMAGE" "define Device/h3c_nx30pro" "$block"
  rm -f "$block"
fi

if ! grep -q 'cmcc,xr30-emmc' "$MT7981_PREINIT"; then
  sed -i 's/cmcc,rax3000m-em)/cmcc,rax3000m-emmc|\\\n\tcmcc,xr30-emmc)/' "$MT7981_PREINIT"
fi

if ! grep -q '\*cmcc,xr30\*' "$MT7981_NETWORK"; then
  block="$(mktemp)"
  printf '\t*cmcc,xr30* |\\\n' > "$block"
  insert_before_marker "$MT7981_NETWORK" "*rax3000m*)" "$block"
  rm -f "$block"
fi

if ! grep -q 'cmcc,xr30-emmc)' "$MT7981_NETWORK"; then
  block="$(mktemp)"
  cat > "$block" <<'NETWORK'
	cmcc,xr30-emmc)
		lan_mac=$(mmc_get_mac_binary factory 0x2a)
		wan_mac=$(mmc_get_mac_binary factory 0x24)
		label_mac=$wan_mac
		local wifi_mac="$(macaddr_add $lan_mac 1)"
		sed -i '/MacAddress=$wifi_mac/d' /etc/wireless/mediatek/mt7981.dbdc.b0.dat
		echo "MacAddress=$wifi_mac" >> /etc/wireless/mediatek/mt7981.dbdc.b0.dat
		wifi_mac="$(macaddr_add $lan_mac 2)"
		sed -i '/MacAddress=$wifi_mac/d' /etc/wireless/mediatek/mt7981.dbdc.b1.dat
		echo "MacAddress=$wifi_mac" >> /etc/wireless/mediatek/mt7981.dbdc.b1.dat
		;;
NETWORK
  insert_before_marker "$MT7981_NETWORK" "cmcc,rax3000m-emmc)" "$block"
  rm -f "$block"
fi

if ! grep -q 'cmcc,xr30)' "$MT7981_NETWORK"; then
  block="$(mktemp)"
  cat > "$block" <<'NETWORK'
	cmcc,xr30)
		local factory_mac="$(mtd_get_mac_binary Factory 0x04)"
		lan_mac="$(macaddr_add $factory_mac 1)"
		wan_mac="$(macaddr_add $factory_mac 2)"
		local wifi_mac="$(macaddr_add $factory_mac 3)"
		sed -i '/MacAddress=$wifi_mac/d' /etc/wireless/mediatek/mt7981.dbdc.b0.dat
		echo "MacAddress=$wifi_mac" >> /etc/wireless/mediatek/mt7981.dbdc.b0.dat
		wifi_mac="$(macaddr_add $factory_mac 4)"
		sed -i '/MacAddress=$wifi_mac/d' /etc/wireless/mediatek/mt7981.dbdc.b1.dat
		echo "MacAddress=$wifi_mac" >> /etc/wireless/mediatek/mt7981.dbdc.b1.dat
		label_mac=$lan_mac
		;;
NETWORK
  insert_before_marker "$MT7981_NETWORK" "cmcc,rax3000m)" "$block"
  rm -f "$block"
fi

if ! grep -q 'cmcc,xr30 |\\' "$MT7981_UPGRADE"; then
  block="$(mktemp)"
  printf '\tcmcc,xr30 |\\\n' > "$block"
  insert_after_marker "$MT7981_UPGRADE" "cmcc,rax3000m |\\" "$block"
  rm -f "$block"
fi

if ! grep -q 'cmcc,xr30-emmc |\\' "$MT7981_UPGRADE"; then
  block="$(mktemp)"
  printf '\tcmcc,xr30-emmc |\\\n' > "$block"
  insert_after_marker "$MT7981_UPGRADE" "cmcc,rax3000m-emmc |\\" "$block"
  rm -f "$block"
fi

if ! grep -Fq 'cmcc,xr30* |' "$MT7981_UPGRADE"; then
  block="$(mktemp)"
  printf '\tcmcc,xr30* |\\\n' > "$block"
  insert_after_marker "$MT7981_UPGRADE" "cmcc,rax3000m* |\\" "$block"
  rm -f "$block"
fi

perl -0pi -e 's/\\t/\t/g' "$MT7981_NETWORK" "$MT7981_UPGRADE"
perl -0pi -e 's/\n\tcmcc,xr30\* \|\\\n\tcmcc,xr30 \|\\/\n\tcmcc,xr30 |\\/g' "$MT7981_UPGRADE"

echo "CMCC XR30 23.05 adaptation ready."
