# ImmortalWrt MT798x Build (openwrt-23.05)

基于 padavanonly/immortalwrt-mt798x-6.6 openwrt-23.05 分支

## 设备支持

| 变种 | 设备数 | 示例 |
|------|--------|------|
| mt7981-ax3000 | 12款 | RAX3000M, ASR3000, CT3003, JCG Q30, 360 T7, AX3000T 等 |
| mt7986-ax4200 | 1款 | BPI-R3 Mini |
| mt7986-ax6000 | 2款 | GL-MT6000, Netcore N60 |
| mt7986-ax6000-256m | 2款 | 256M 内存版 |

## 快速开始

### 安装依赖
sudo apt install -y build-essential gcc-multilib g++-multilib git python3 cmake clang bison flex gawk gettext libssl-dev libncurses-dev libelf-dev libgmp-dev libmpc-dev libtool autoconf automake unzip wget ...

完整列表见 .github/workflows/mt798x.yml

### 编译
```bash
git clone --depth=1 -b openwrt-23.05 https://github.com/padavanonly/immortalwrt-mt798x-6.6.git openwrt
cd openwrt
bash ../01_prepare.sh
bash ../build_all.sh
```
### 自定义插件
编辑 package.conf 增删插件

### WSL 用户
sudo tee -a /etc/wsl.conf << 'EOF'
[interop]
appendWindowsPath=false
EOF
