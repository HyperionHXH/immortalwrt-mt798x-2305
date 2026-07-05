#!/usr/bin/env bash
set -euo pipefail

OPENWRT_DIR="${1:-${OPENWRT_DIR:-$PWD}}"
MT7981_DTS_DIR="$OPENWRT_DIR/target/linux/mediatek/files-5.4/arch/arm64/boot/dts/mediatek"
MT7981_IMAGE="$OPENWRT_DIR/target/linux/mediatek/image/mt7981.mk"
MT7981_NETWORK="$OPENWRT_DIR/target/linux/mediatek/mt7981/base-files/etc/board.d/02_network"
MT7981_UPGRADE="$OPENWRT_DIR/target/linux/mediatek/mt7981/base-files/lib/upgrade/platform.sh"

if [ ! -d "$OPENWRT_DIR/target/linux/mediatek" ]; then
  echo "错误：OPENWRT_DIR 看起来不是 ImmortalWrt 源码树：$OPENWRT_DIR" >&2
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

insert_before_marker_after() {
  local file="$1"
  local anchor="$2"
  local marker="$3"
  local block_file="$4"
  local tmp

  tmp="$(mktemp)"
  awk -v anchor="$anchor" -v marker="$marker" -v block_file="$block_file" '
    BEGIN {
      while ((getline line < block_file) > 0) {
        block = block line ORS
      }
      close(block_file)
    }
    index($0, anchor) {
      seen_anchor = 1
    }
    seen_anchor && index($0, marker) && !done {
      printf "%s", block
      done = 1
    }
    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

has_between() {
  local file="$1"
  local start="$2"
  local stop="$3"
  local needle="$4"

  awk -v start="$start" -v stop="$stop" -v needle="$needle" '
    index($0, start) { in_range = 1 }
    in_range && index($0, needle) { found = 1 }
    in_range && index($0, stop) { in_range = 0 }
    END { exit found ? 0 : 1 }
  ' "$file"
}

mkdir -p "$MT7981_DTS_DIR"

cat > "$MT7981_DTS_DIR/mt7981-ruijie-rg-x30e.dtsi" <<'DTS'
// SPDX-License-Identifier: GPL-2.0-or-later OR MIT

/dts-v1/;
#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/input/input.h>

#include "mt7981.dtsi"

/ {
	aliases {
		led-boot = &sysled_red;
		led-failsafe = &sysled_red;
		led-running = &sysled_green;
		led-upgrade = &sysled_red;
	};

	memory {
		reg = <0 0x40000000 0 0x10000000>;
	};

	gpio-keys {
		compatible = "gpio-keys";

		button-reset {
			label = "reset";
			linux,code = <KEY_RESTART>;
			gpios = <&pio 1 GPIO_ACTIVE_LOW>;
		};

		button-wps {
			label = "wps";
			linux,code = <KEY_WPS_BUTTON>;
			gpios = <&pio 0 GPIO_ACTIVE_LOW>;
		};
	};

	leds-gpio {
		compatible = "gpio-leds";

		mesh_led: led-0 {
			label = "green:mesh";
			gpios = <&pio 5 GPIO_ACTIVE_LOW>;
		};

		sysled_red: led-1 {
			label = "red:status";
			gpios = <&pio 13 GPIO_ACTIVE_LOW>;
		};

		sysled_green: led-2 {
			label = "green:status";
			gpios = <&pio 6 GPIO_ACTIVE_LOW>;
		};
	};

	nmbm_spim_nand: nmbm_spim_nand {
		compatible = "generic,nmbm";
		#address-cells = <1>;
		#size-cells = <1>;
		lower-mtd-device = <&spi_nand>;
		forced-create;
	};
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
		reg = <1>;
		phy-mode = "2500base-x";

		fixed-link {
			speed = <2500>;
			full-duplex;
			pause;
		};
	};

	mdio: mdio-bus {
		#address-cells = <1>;
		#size-cells = <0>;

		switch: switch@1f {
			compatible = "mediatek,mt7531";
			reg = <31>;
			reset-gpios = <&pio 54 GPIO_ACTIVE_HIGH>;
			interrupt-controller;
			#interrupt-cells = <1>;
			interrupt-parent = <&pio>;
			interrupts = <38 IRQ_TYPE_LEVEL_HIGH>;

			ports {
				#address-cells = <1>;
				#size-cells = <0>;

				port@1 {
					reg = <1>;
					label = "lan1";
				};

				port@2 {
					reg = <2>;
					label = "lan2";
				};

				port@3 {
					reg = <3>;
					label = "lan3";
				};

				port@4 {
					reg = <4>;
					label = "wan";
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
	mtketh-wan = "wan";
	mtketh-lan = "lan";
	mtketh-max-gmac = <1>;
	status = "okay";
};

&spi0 {
	pinctrl-names = "default";
	pinctrl-0 = <&spi0_flash_pins>;
	status = "okay";

	spi_nand: flash@0 {
		#address-cells = <1>;
		#size-cells = <1>;
		compatible = "spi-nand";
		reg = <0>;
		spi-max-frequency = <52000000>;
		spi-cal-enable;
		spi-cal-mode = "read-data";
		spi-cal-datalen = <7>;
		spi-cal-data = /bits/ 8 <0x53 0x50 0x49 0x4E 0x41 0x4E 0x44>;
		spi-cal-addrlen = <5>;
		spi-cal-addr = /bits/ 32 <0x0 0x0 0x0 0x0 0x0>;
		spi-tx-bus-width = <4>;
		spi-rx-bus-width = <4>;
		mediatek,nmbm;
		mediatek,bmt-max-ratio = <1>;
		mediatek,bmt-max-reserved-blocks = <64>;
	};
};

&nmbm_spim_nand {
	partitions: partitions {
		compatible = "fixed-partitions";
		#address-cells = <1>;
		#size-cells = <1>;

		partition@0 {
			label = "BL2";
			reg = <0x00 0x100000>;
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
			label = "FIP2";
			reg = <0x580000 0x200000>;
		};

		partition@780000 {
			label = "product_info";
			reg = <0x780000 0x80000>;
		};

		partition@800000 {
			label = "kdump";
			reg = <0x800000 0x80000>;
		};
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

&uart0 {
	status = "okay";
};

&watchdog {
	status = "okay";
};
DTS

cat > "$MT7981_DTS_DIR/mt7981-ruijie-rg-x30e-pro.dtsi" <<'DTS'
// SPDX-License-Identifier: GPL-2.0-or-later OR MIT

/dts-v1/;
#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/input/input.h>

#include "mt7981.dtsi"

/ {
	aliases {
		led-boot = &sysled_red;
		led-failsafe = &sysled_red;
		led-running = &sysled_green;
		led-upgrade = &sysled_red;
	};

	memory {
		reg = <0 0x40000000 0 0x10000000>;
	};

	gpio-keys {
		compatible = "gpio-keys";

		button-reset {
			label = "reset";
			linux,code = <KEY_RESTART>;
			gpios = <&pio 1 GPIO_ACTIVE_LOW>;
		};

		button-wps {
			label = "wps";
			linux,code = <KEY_WPS_BUTTON>;
			gpios = <&pio 0 GPIO_ACTIVE_LOW>;
		};
	};

	leds-gpio {
		compatible = "gpio-leds";

		mesh_led: led-0 {
			label = "green:mesh";
			gpios = <&pio 5 GPIO_ACTIVE_LOW>;
		};

		sysled_red: led-1 {
			label = "red:status";
			gpios = <&pio 13 GPIO_ACTIVE_LOW>;
		};

		sysled_green: led-2 {
			label = "green:status";
			gpios = <&pio 6 GPIO_ACTIVE_LOW>;
		};
	};

	nmbm_spim_nand: nmbm_spim_nand {
		compatible = "generic,nmbm";
		#address-cells = <1>;
		#size-cells = <1>;
		lower-mtd-device = <&spi_nand>;
		forced-create;
	};
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
		reg = <1>;
		phy-mode = "2500base-x";

		fixed-link {
			speed = <2500>;
			full-duplex;
			pause;
		};
	};

	mdio: mdio-bus {
		#address-cells = <1>;
		#size-cells = <0>;

		switch: switch@1f {
			compatible = "mediatek,mt7531";
			reg = <31>;
			reset-gpios = <&pio 54 GPIO_ACTIVE_HIGH>;
			interrupt-controller;
			#interrupt-cells = <1>;
			interrupt-parent = <&pio>;
			interrupts = <38 IRQ_TYPE_LEVEL_HIGH>;

			ports {
				#address-cells = <1>;
				#size-cells = <0>;

				port@0 {
					reg = <0>;
					label = "wan";
				};

				port@1 {
					reg = <1>;
					label = "lan1";
				};

				port@2 {
					reg = <2>;
					label = "lan2";
				};

				port@4 {
					reg = <4>;
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
	mtketh-wan = "wan";
	mtketh-lan = "lan";
	mtketh-max-gmac = <1>;
	status = "okay";
};

&spi0 {
	pinctrl-names = "default";
	pinctrl-0 = <&spi0_flash_pins>;
	status = "okay";

	spi_nand: flash@0 {
		#address-cells = <1>;
		#size-cells = <1>;
		compatible = "spi-nand";
		reg = <0>;
		spi-max-frequency = <52000000>;
		spi-cal-enable;
		spi-cal-mode = "read-data";
		spi-cal-datalen = <7>;
		spi-cal-data = /bits/ 8 <0x53 0x50 0x49 0x4E 0x41 0x4E 0x44>;
		spi-cal-addrlen = <5>;
		spi-cal-addr = /bits/ 32 <0x0 0x0 0x0 0x0 0x0>;
		spi-tx-bus-width = <4>;
		spi-rx-bus-width = <4>;
		mediatek,nmbm;
		mediatek,bmt-max-ratio = <1>;
		mediatek,bmt-max-reserved-blocks = <64>;
	};
};

&nmbm_spim_nand {
	partitions: partitions {
		compatible = "fixed-partitions";
		#address-cells = <1>;
		#size-cells = <1>;

		partition@0 {
			label = "BL2";
			reg = <0x00 0x100000>;
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
			label = "FIP2";
			reg = <0x580000 0x200000>;
		};

		partition@780000 {
			label = "product_info";
			reg = <0x780000 0x80000>;
		};

		partition@800000 {
			label = "kdump";
			reg = <0x800000 0x80000>;
		};
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

&uart0 {
	status = "okay";
};

&watchdog {
	status = "okay";
};
DTS

cat > "$MT7981_DTS_DIR/mt7981-ruijie-rg-x30e.dts" <<'DTS'
// SPDX-License-Identifier: GPL-2.0-or-later OR MIT

/dts-v1/;
#include "mt7981-ruijie-rg-x30e.dtsi"

/ {
	model = "Ruijie RG-X30E";
	compatible = "ruijie,rg-x30e", "mediatek,mt7981";

	chosen {
		bootargs = "console=ttyS0,115200n1 loglevel=8 earlycon=uart8250,mmio32,0x11002000";
	};
};

&partitions {
	partition@880000 {
		label = "ubi";
		reg = <0x880000 0x6F80000>;
	};
};
DTS

cat > "$MT7981_DTS_DIR/mt7981-ruijie-rg-x30e-firmware2.dts" <<'DTS'
// SPDX-License-Identifier: GPL-2.0-or-later OR MIT

/dts-v1/;
#include "mt7981-ruijie-rg-x30e.dtsi"

/ {
	model = "Ruijie RG-X30E (firmware2 layout)";
	compatible = "ruijie,rg-x30e-firmware2", "mediatek,mt7981";

	chosen {
		bootargs = "console=ttyS0,115200n1 loglevel=8 earlycon=uart8250,mmio32,0x11002000";
	};
};

&partitions {
	partition@880000 {
		label = "ubi1";
		reg = <0x880000 0x2280000>;
	};

	partition@2b00000 {
		label = "ubi";
		reg = <0x2B00000 0x2280000>;
	};

	partition@4d80000 {
		label = "backup";
		reg = <0x4D80000 0x2A80000>;
	};
};
DTS

cat > "$MT7981_DTS_DIR/mt7981-ruijie-rg-x30e-stock.dts" <<'DTS'
// SPDX-License-Identifier: GPL-2.0-or-later OR MIT

/dts-v1/;
#include "mt7981-ruijie-rg-x30e.dtsi"

/ {
	model = "Ruijie RG-X30E (stock layout)";
	compatible = "ruijie,rg-x30e-stock", "mediatek,mt7981";

	chosen {
		bootargs = "console=ttyS0,115200n1 loglevel=8 earlycon=uart8250,mmio32,0x11002000";
	};
};

&partitions {
	partition@880000 {
		label = "ubi";
		reg = <0x880000 0x2280000>;
	};

	partition@2b00000 {
		label = "ubi2";
		reg = <0x2B00000 0x2280000>;
	};

	partition@4d80000 {
		label = "backup";
		reg = <0x4D80000 0x2A80000>;
	};
};
DTS

cat > "$MT7981_DTS_DIR/mt7981-ruijie-rg-x30e-pro.dts" <<'DTS'
// SPDX-License-Identifier: GPL-2.0-or-later OR MIT

/dts-v1/;
#include "mt7981-ruijie-rg-x30e-pro.dtsi"

/ {
	model = "Ruijie RG-X30E Pro";
	compatible = "ruijie,rg-x30e-pro", "mediatek,mt7981";

	chosen {
		bootargs = "console=ttyS0,115200n1 loglevel=8 earlycon=uart8250,mmio32,0x11002000";
	};
};

&partitions {
	partition@880000 {
		label = "ubi";
		reg = <0x880000 0x6F80000>;
	};
};
DTS

cat > "$MT7981_DTS_DIR/mt7981-ruijie-rg-x30e-pro-firmware2.dts" <<'DTS'
// SPDX-License-Identifier: GPL-2.0-or-later OR MIT

/dts-v1/;
#include "mt7981-ruijie-rg-x30e-pro.dtsi"

/ {
	model = "Ruijie RG-X30E Pro (firmware2 layout)";
	compatible = "ruijie,rg-x30e-pro-firmware2", "mediatek,mt7981";

	chosen {
		bootargs = "console=ttyS0,115200n1 loglevel=8 earlycon=uart8250,mmio32,0x11002000";
	};
};

&partitions {
	partition@880000 {
		label = "ubi1";
		reg = <0x880000 0x2280000>;
	};

	partition@2b00000 {
		label = "ubi";
		reg = <0x2B00000 0x2280000>;
	};

	partition@4d80000 {
		label = "backup";
		reg = <0x4D80000 0x2A80000>;
	};
};
DTS

cat > "$MT7981_DTS_DIR/mt7981-ruijie-rg-x30e-pro-stock.dts" <<'DTS'
// SPDX-License-Identifier: GPL-2.0-or-later OR MIT

/dts-v1/;
#include "mt7981-ruijie-rg-x30e-pro.dtsi"

/ {
	model = "Ruijie RG-X30E Pro (stock layout)";
	compatible = "ruijie,rg-x30e-pro-stock", "mediatek,mt7981";

	chosen {
		bootargs = "console=ttyS0,115200n1 loglevel=8 earlycon=uart8250,mmio32,0x11002000";
	};
};

&partitions {
	partition@880000 {
		label = "ubi";
		reg = <0x880000 0x2280000>;
	};

	partition@2b00000 {
		label = "ubi2";
		reg = <0x2B00000 0x2280000>;
	};

	partition@4d80000 {
		label = "backup";
		reg = <0x4D80000 0x2A80000>;
	};
};
DTS

if ! grep -q '^define Device/ruijie_rg-x30e$' "$MT7981_IMAGE"; then
  block="$(mktemp)"
  cat > "$block" <<'DEVICE'
define Device/ruijie_rg-x30e
  DEVICE_VENDOR := Ruijie
  DEVICE_MODEL := RG-X30E
  DEVICE_DTS := mt7981-ruijie-rg-x30e
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  SUPPORTED_DEVICES := ruijie,rg-x30e
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 114688k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += ruijie_rg-x30e

define Device/ruijie_rg-x30e-firmware2
  DEVICE_VENDOR := Ruijie
  DEVICE_MODEL := RG-X30E
  DEVICE_VARIANT := firmware2 layout
  DEVICE_DTS := mt7981-ruijie-rg-x30e-firmware2
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  SUPPORTED_DEVICES := ruijie,rg-x30e-firmware2
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 114688k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += ruijie_rg-x30e-firmware2

define Device/ruijie_rg-x30e-stock
  DEVICE_VENDOR := Ruijie
  DEVICE_MODEL := RG-X30E
  DEVICE_VARIANT := stock layout
  DEVICE_DTS := mt7981-ruijie-rg-x30e-stock
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  SUPPORTED_DEVICES := ruijie,rg-x30e-stock
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 114688k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += ruijie_rg-x30e-stock

define Device/ruijie_rg-x30e-pro
  DEVICE_VENDOR := Ruijie
  DEVICE_MODEL := RG-X30E Pro
  DEVICE_DTS := mt7981-ruijie-rg-x30e-pro
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  SUPPORTED_DEVICES := ruijie,rg-x30e-pro
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 114688k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += ruijie_rg-x30e-pro

define Device/ruijie_rg-x30e-pro-firmware2
  DEVICE_VENDOR := Ruijie
  DEVICE_MODEL := RG-X30E Pro
  DEVICE_VARIANT := firmware2 layout
  DEVICE_DTS := mt7981-ruijie-rg-x30e-pro-firmware2
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  SUPPORTED_DEVICES := ruijie,rg-x30e-pro-firmware2
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 114688k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += ruijie_rg-x30e-pro-firmware2

define Device/ruijie_rg-x30e-pro-stock
  DEVICE_VENDOR := Ruijie
  DEVICE_MODEL := RG-X30E Pro
  DEVICE_VARIANT := stock layout
  DEVICE_DTS := mt7981-ruijie-rg-x30e-pro-stock
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  SUPPORTED_DEVICES := ruijie,rg-x30e-pro-stock
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 114688k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += ruijie_rg-x30e-pro-stock

DEVICE
  insert_before_marker "$MT7981_IMAGE" "define Device/xiaomi_mi-router-wr30u-stock" "$block"
  rm -f "$block"
fi

if ! has_between "$MT7981_NETWORK" "mediatek_setup_interfaces()" "mtk_facrory_write_mac()" "ruijie,rg-x30e*)"; then
  block="$(mktemp)"
  cat > "$block" <<'NETWORK'
	ruijie,rg-x30e*)
		ucidef_set_interfaces_lan_wan "lan1 lan2 lan3" wan
		;;
NETWORK
  insert_before_marker_after "$MT7981_NETWORK" "mediatek_setup_interfaces()" "	*)" "$block"
  rm -f "$block"
fi

if ! has_between "$MT7981_NETWORK" "mediatek_setup_macs()" "board_config_update" "ruijie,rg-x30e*)"; then
  block="$(mktemp)"
  cat > "$block" <<'NETWORK'
	ruijie,rg-x30e*)
		label_mac=$(mtd_get_mac_ascii product_info ethaddr)
		wan_mac=$label_mac
		lan_mac=$(macaddr_add "$label_mac" 1)
		local wifi_mac="$(macaddr_add "$label_mac" 2)"
		sed -i '/^MacAddress=/d' /etc/wireless/mediatek/mt7981.dbdc.b0.dat
		echo "MacAddress=$wifi_mac" >> /etc/wireless/mediatek/mt7981.dbdc.b0.dat
		wifi_mac="$(macaddr_add "$label_mac" 3)"
		sed -i '/^MacAddress=/d' /etc/wireless/mediatek/mt7981.dbdc.b1.dat
		echo "MacAddress=$wifi_mac" >> /etc/wireless/mediatek/mt7981.dbdc.b1.dat
		;;
NETWORK
  insert_before_marker_after "$MT7981_NETWORK" "mediatek_setup_macs()" "h3c,nx30pro)" "$block"
  rm -f "$block"
fi

if ! has_between "$MT7981_UPGRADE" "platform_do_upgrade()" "platform_check_image()" "ruijie,rg-x30e* |"; then
  block="$(mktemp)"
  printf '\truijie,rg-x30e* |\\\n' > "$block"
  insert_before_marker_after "$MT7981_UPGRADE" "platform_do_upgrade()" "h3c,nx30pro |\\" "$block"
  rm -f "$block"
fi

if ! has_between "$MT7981_UPGRADE" "platform_check_image()" "platform_pre_upgrade()" "ruijie,rg-x30e* |"; then
  block="$(mktemp)"
  printf '\truijie,rg-x30e* |\\\n' > "$block"
  insert_before_marker_after "$MT7981_UPGRADE" "platform_check_image()" "h3c,nx30pro |\\" "$block"
  rm -f "$block"
fi

echo "Ruijie RG-X30E 23.05 适配已准备好。"
