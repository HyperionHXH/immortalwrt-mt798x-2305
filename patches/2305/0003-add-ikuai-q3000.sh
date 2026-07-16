#!/usr/bin/env bash
set -euo pipefail

OPENWRT_DIR="${1:-${OPENWRT_DIR:-$PWD}}"
MT7981_DTS_DIR="$OPENWRT_DIR/target/linux/mediatek/files-5.4/arch/arm64/boot/dts/mediatek"
MT7981_IMAGE="$OPENWRT_DIR/target/linux/mediatek/image/mt7981.mk"
MT7981_NETWORK="$OPENWRT_DIR/target/linux/mediatek/mt7981/base-files/etc/board.d/02_network"
MT7981_LEDS="$OPENWRT_DIR/target/linux/mediatek/mt7981/base-files/etc/board.d/01_leds"
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

remove_ikuai_network_blocks() {
  local tmp
  tmp="$(mktemp)"
  awk '
    $0 == "\tikuai,q3000 |\\" {
      skip_iface = 1
      next
    }
    skip_iface && $0 == "\t*fpga*)" {
      skip_iface = 0
    }
    skip_iface && $0 == "\t\tucidef_set_interfaces_lan_wan \"lan1 lan2 lan3\" wan" {
      next
    }
    skip_iface && $0 == "\t\t;;" {
      skip_iface = 0
      next
    }
    $0 == "\tikuai,q3000)" {
      skip_mac = 1
      next
    }
    skip_mac && $0 == "\t\t;;" {
      skip_mac = 0
      next
    }
    skip_iface || skip_mac {
      next
    }
    { print }
  ' "$MT7981_NETWORK" > "$tmp"
  mv "$tmp" "$MT7981_NETWORK"
}

normalize_fpga_interface_block() {
  local block tmp
  block="$(mktemp)"
  cat > "$block" <<'NETWORK'
	*fpga*)
		ucidef_set_interfaces_lan_wan "eth0" "eth1"
		ucidef_add_switch "switch0" \
			"0:lan" "1:lan" "2:lan" "3:lan" "4:wan" "6u@eth0" "5u@eth1"
		;;
NETWORK

  tmp="$(mktemp)"
  awk '
    $0 == "\t*fpga*)" {
      skip = 1
      next
    }
    skip && $0 == "\t\t;;" {
      skip = 0
      next
    }
    skip {
      next
    }
    { print }
  ' "$MT7981_NETWORK" > "$tmp"
  mv "$tmp" "$MT7981_NETWORK"

  tmp="$(mktemp)"
  awk -v block_file="$block" '
    BEGIN {
      while ((getline line < block_file) > 0) {
        block = block line ORS
      }
      close(block_file)
    }
    $0 == "\tcase $board in" && !done {
      print
      printf "%s", block
      done = 1
      next
    }
    { print }
  ' "$MT7981_NETWORK" > "$tmp"
  mv "$tmp" "$MT7981_NETWORK"
  rm -f "$block"
}

mkdir -p "$MT7981_DTS_DIR"

cat > "$MT7981_DTS_DIR/mt7981-ikuai-q3000.dts" <<'DTS'
/dts-v1/;
#include "mt7981.dtsi"

/ {
	compatible = "ikuai,q3000", "mediatek,mt7981";
	model = "iKuai Q3000";

	aliases {
		led-boot = &red_led;
		led-failsafe = &red_led;
		led-running = &green_led;
		led-upgrade = &blue_led;
	};

	chosen {
		bootargs = "console=ttyS0,115200n1 loglevel=8 earlycon=uart8250,mmio32,0x11002000 clk_ignore_unused";
	};

	gpio-keys {
		compatible = "gpio-keys";

		reset {
			label = "reset";
			linux,code = <KEY_RESTART>;
			gpios = <&pio 1 GPIO_ACTIVE_LOW>;
		};

		wps {
			label = "wps";
			linux,code = <KEY_WPS_BUTTON>;
			gpios = <&pio 0 GPIO_ACTIVE_LOW>;
		};
	};

	leds {
		compatible = "gpio-leds";

		green_led: green {
			label = "q3000:green";
			gpios = <&pio 11 GPIO_ACTIVE_LOW>;
		};

		red_led: red {
			label = "q3000:red";
			gpios = <&pio 10 GPIO_ACTIVE_LOW>;
		};

		blue_led: blue {
			label = "q3000:blue";
			gpios = <&pio 12 GPIO_ACTIVE_LOW>;
		};
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
				reg = <0x00000 0x0100000>;
				read-only;
			};

			partition@100000 {
				label = "u-boot-env";
				reg = <0x0100000 0x0080000>;
			};

			partition@180000 {
				label = "Factory";
				reg = <0x180000 0x0200000>;
			};

			partition@380000 {
				label = "FIP";
				reg = <0x380000 0x0200000>;
			};

			partition@580000 {
				label = "ubi";
				reg = <0x580000 0x4000000>;
			};
		};
	};

	sound_wm8960 {
		compatible = "mediatek,mt79xx-wm8960-machine";
		mediatek,platform = <&afe>;
		audio-routing = "Headphone", "HP_L",
				"Headphone", "HP_R",
				"LINPUT1", "AMIC",
				"RINPUT1", "AMIC";
		mediatek,audio-codec = <&wm8960>;
		status = "disabled";
	};

	sound_si3218x {
		compatible = "mediatek,mt79xx-si3218x-machine";
		mediatek,platform = <&afe>;
		mediatek,ext-codec = <&proslic_spi>;
		status = "disabled";
	};
};

&afe {
	pinctrl-names = "default";
	pinctrl-0 = <&pcm_pins>;
	status = "okay";
};

&i2c0 {
	pinctrl-names = "default";
	pinctrl-0 = <&i2c_pins>;
	status = "disabled";

	wm8960: wm8960@1a {
		compatible = "wlf,wm8960";
		reg = <0x1a>;
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

	mdio: mdio-bus {
		#address-cells = <1>;
		#size-cells = <0>;

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

				port@3 {
					reg = <3>;
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
	mtketh-max-gmac = <2>;
	status = "okay";
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
	};
};

&spi1 {
	pinctrl-names = "default";
	pinctrl-0 = <&spic_pins>;
	status = "okay";

	proslic_spi: proslic_spi@0 {
		compatible = "silabs,proslic_spi";
		reg = <0>;
		spi-max-frequency = <10000000>;
		spi-cpha = <1>;
		spi-cpol = <1>;
		channel_count = <1>;
		debug_level = <4>;
		reset_gpio = <&pio 15 0>;
		ig,enable-spi = <1>;
	};
};

&pio {
	i2c_pins: i2c-pins-g0 {
		mux {
			function = "i2c";
			groups = "i2c0_0";
		};
	};

	pcm_pins: pcm-pins-g0 {
		mux {
			function = "pcm";
			groups = "pcm";
		};
	};

	pwm0_pin: pwm0-pin-g0 {
		mux {
			function = "pwm";
			groups = "pwm0_0";
		};
	};

	pwm1_pin: pwm1-pin-g0 {
		mux {
			function = "pwm";
			groups = "pwm1_0";
		};
	};

	pwm2_pin: pwm2-pin {
		mux {
			function = "pwm";
			groups = "pwm2";
		};
	};

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

	spic_pins: spi1-pins {
		mux {
			function = "spi";
			groups = "spi1_1";
		};
	};

	uart1_pins: uart1-pins-g1 {
		mux {
			function = "uart";
			groups = "uart1_1";
		};
	};

	uart2_pins: uart2-pins-g1 {
		mux {
			function = "uart";
			groups = "uart2_1";
		};
	};
};

&xhci {
	mediatek,u3p-dis-msk = <0x0>;
	phys = <&u2port0 PHY_TYPE_USB2>,
	       <&u3port0 PHY_TYPE_USB3>;
	status = "okay";
};

&trng {
	status = "disabled";
};
DTS

if ! grep -q '^define Device/ikuai_q3000$' "$MT7981_IMAGE"; then
  block="$(mktemp)"
  cat > "$block" <<'DEVICE'
define Device/ikuai_q3000
  DEVICE_VENDOR := iKuai
  DEVICE_MODEL := Q3000
  DEVICE_DTS := mt7981-ikuai-q3000
  DEVICE_DTS_DIR := $(DTS_DIR)/mediatek
  SUPPORTED_DEVICES := ikuai,q3000
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 65536k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += ikuai_q3000

DEVICE
  insert_before_marker "$MT7981_IMAGE" "define Device/livinet_zr-3020" "$block"
  rm -f "$block"
fi

normalize_fpga_interface_block

if ! has_between "$MT7981_NETWORK" "mediatek_setup_interfaces()" "mtk_facrory_write_mac()" "ikuai,q3000)" || \
   ! has_between "$MT7981_NETWORK" "mediatek_setup_macs()" "board_config_update" "ikuai,q3000)"; then
  remove_ikuai_network_blocks

  block="$(mktemp)"
  cat > "$block" <<'NETWORK'
	ikuai,q3000)
		ucidef_set_interfaces_lan_wan "lan1 lan2 lan3" wan
		;;
NETWORK
  insert_before_marker_after "$MT7981_NETWORK" "nradio,wt9103)" "	*)" "$block"
  rm -f "$block"

  block="$(mktemp)"
  cat > "$block" <<'NETWORK'
	ikuai,q3000)
		wan_mac=$(mtd_get_mac_binary $part_name 0x10048)
		lan_mac=$(macaddr_add $wan_mac 1)
		;;
NETWORK
  insert_before_marker_after "$MT7981_NETWORK" "*jcg,q30*)" "h3c,nx30pro)" "$block"
  rm -f "$block"
fi

if ! grep -q 'ikuai,q3000)' "$MT7981_LEDS"; then
  block="$(mktemp)"
  cat > "$block" <<'LEDS'
ikuai,q3000)
	ucidef_set_led_default "green" "GREEN" "q3000:green" "1"
	ucidef_set_led_default "blue" "BLUE" "q3000:blue" "0"
	ucidef_set_led_default "red" "RED" "q3000:red" "0"
	;;
LEDS
  insert_before_marker "$MT7981_LEDS" "konka,komi-a31)" "$block"
  rm -f "$block"
fi

if ! has_between "$MT7981_UPGRADE" "platform_do_upgrade()" "platform_check_image()" "ikuai,q3000 |"; then
  block="$(mktemp)"
  printf '\tikuai,q3000 |\\\n' > "$block"
  insert_before_marker_after "$MT7981_UPGRADE" "platform_do_upgrade()" "h3c,nx30pro |\\" "$block"
  rm -f "$block"
fi

if ! has_between "$MT7981_UPGRADE" "platform_check_image()" "return 0" "ikuai,q3000 |"; then
  block="$(mktemp)"
  printf '\tikuai,q3000 |\\\n' > "$block"
  insert_before_marker_after "$MT7981_UPGRADE" "platform_check_image()" "h3c,nx30pro |\\" "$block"
  rm -f "$block"
fi

perl -0pi -e 's/\n\tikuai,q3000 \|\\\n\tikuai,q3000 \|\\/\n\tikuai,q3000 |\\/g' "$MT7981_UPGRADE"

echo "iKuai Q3000 23.05 适配已准备好。"
