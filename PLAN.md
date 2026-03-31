# 本地编译计划

## 目标

在本机按当前 [`.github/workflows/openwrt-ci.yml`](/home/blast/src/lede/.github/workflows/openwrt-ci.yml) 的流程完成一次可复现的 OpenWrt 固件编译，并将 OpenClash 的以下内容一并集成进固件：

- `luci-app-openclash` 源码
- OpenClash 编译依赖
- OpenClash 运行时面板资源
- OpenClash Meta 内核

## 前提条件

开始前先确认以下条件：

- 主机系统为较新的 Debian / Ubuntu
- 磁盘剩余空间建议不少于 `80GB`
- 内存建议不少于 `8GB`
- 网络可以访问 GitHub、`raw.githubusercontent.com`、`codeload.github.com`
- 当前仓库目录为 `/home/blast/src/lede`

建议先执行：

```bash
pwd
df -h .
free -h
git status --short
printf '%s\n' "$PATH" | tr ':' '\n'
```

额外检查：

- 如果是在 WSL 或混合 Windows 环境下编译，确认 `PATH` 中不要带有 `/mnt/c/Program Files/...` 这类带空格的 Windows 路径。
- 否则全量编译在 `package/install` 阶段可能因为 `find ... -execdir` 安全检查直接失败，典型报错为：

```text
find: The relative path 'Files/NVIDIA' is included in the PATH environment variable, which is insecure in combination with the -execdir action of find.
```

可临时使用精简后的 `PATH` 重新编译，例如：

```bash
export PATH="/home/blast/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
```

## 总体步骤

1. 准备编译环境
2. 更新并安装 feeds
3. 按 OpenClash README 拉取源码
4. 编译并安装 `po2lmo`
5. 准备目标平台 `.config`
6. 启用 OpenClash 主包和依赖
7. 预置 OpenClash 运行时资源
8. 下载源码包
9. 编译固件
10. 校验产物

## 详细执行计划

### 1. 准备编译环境

安装 workflow 中对应的构建依赖。若本机已长期用于 OpenWrt 编译，可只补缺失项。

参考命令：

```bash
sudo apt update
sudo apt install -y ack antlr3 asciidoc autoconf automake autopoint binutils bison build-essential \
  bzip2 ccache clang cmake cpio curl device-tree-compiler flex gawk gcc-multilib g++-multilib \
  gettext genisoimage git gperf haveged help2man intltool libc6-dev-i386 libelf-dev libfuse-dev \
  libglib2.0-dev libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev libncurses5-dev libncursesw5-dev \
  libpython3-dev libreadline-dev libssl-dev libtool llvm lrzsz msmtp ninja-build p7zip p7zip-full \
  patch pkgconf python3 python3-pyelftools python3-setuptools qemu-utils rsync scons squashfs-tools \
  subversion swig texinfo uglifyjs upx-ucl unzip vim wget xmlto xxd zlib1g-dev
```

### 2. 更新并安装 feeds

保持和 workflow 一致：

```bash
sed -i 's/#src-git helloworld/src-git helloworld/g' ./feeds.conf.default
./scripts/feeds update -a
./scripts/feeds install -a
```

检查点：

- `feeds/luci`
- `feeds/packages`
- `package/feeds/`

### 3. 拉取 OpenClash 源码

本地编译时不要直接使用 feeds 里的同名包，按 workflow 方式单独拉源码到 `package/`。

执行：

```bash
rm -rf package/feeds/luci/luci-app-openclash package/luci-app-openclash
mkdir -p package/luci-app-openclash
cd package/luci-app-openclash
git init
git remote add -f origin https://github.com/vernesong/OpenClash.git
git config core.sparsecheckout true
echo "luci-app-openclash" >> .git/info/sparse-checkout
git pull --depth 1 origin master
shopt -s dotglob nullglob
mv luci-app-openclash/* .
rmdir luci-app-openclash
cd /home/blast/src/lede
```

检查点：

- `package/luci-app-openclash/Makefile`

### 4. 编译并安装 po2lmo

执行：

```bash
cd package/luci-app-openclash/tools/po2lmo
make
sudo make install
cd /home/blast/src/lede
```

检查点：

- `which po2lmo`
- `po2lmo` 可执行

### 5. 准备目标平台配置

这一步是本地编译和 CI 的最大差异点。CI 当前 workflow 没有生成具体目标平台配置，但本地编译必须先明确：

- 目标架构
- 目标机型
- 固件文件系统类型

推荐方式二选一：

#### 方式 A：直接使用已有 `.config`

如果你已经有稳定的目标配置：

```bash
cp /你的现成配置/.config /home/blast/src/lede/.config
make defconfig
```

#### 方式 B：手动生成 `.config`

如果没有现成配置：

```bash
make menuconfig
```

至少确认：

- `Target System`
- `Subtarget`
- `Target Profile`

完成后执行：

```bash
make defconfig
```

检查点：

- `.config` 存在
- `.config` 中存在 `CONFIG_TARGET_ARCH_PACKAGES=...`

### 6. 启用 OpenClash 主包和依赖

先启用主包：

```bash
cat >> .config <<'EOF'
CONFIG_PACKAGE_luci-app-openclash=y
EOF
make defconfig
```

再补关键依赖：

```bash
cat >> .config <<'EOF'
CONFIG_PACKAGE_dnsmasq-full=y
CONFIG_PACKAGE_bash=y
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_ca-bundle=y
CONFIG_PACKAGE_ip-full=y
CONFIG_PACKAGE_ruby=y
CONFIG_PACKAGE_ruby-yaml=y
CONFIG_PACKAGE_kmod-tun=y
CONFIG_PACKAGE_kmod-inet-diag=y
CONFIG_PACKAGE_luci-compat=y
CONFIG_PACKAGE_unzip=y
EOF
```

如果 `.config` 中有：

```bash
grep '^CONFIG_PACKAGE_firewall4=y' .config
```

则追加：

```bash
cat >> .config <<'EOF'
CONFIG_PACKAGE_kmod-nft-tproxy=y
CONFIG_PACKAGE_dnsmasq_full_nftset=y
EOF
```

否则追加：

```bash
cat >> .config <<'EOF'
CONFIG_PACKAGE_kmod-ipt-nat=y
CONFIG_PACKAGE_ip6tables-mod-nat=y
CONFIG_PACKAGE_iptables-mod-tproxy=y
CONFIG_PACKAGE_iptables-mod-extra=y
CONFIG_PACKAGE_ipset=y
CONFIG_PACKAGE_dnsmasq_full_ipset=y
EOF
```

然后执行：

```bash
make defconfig
```

检查点：

```bash
grep -E 'CONFIG_PACKAGE_(luci-app-openclash|dnsmasq-full|bash|curl|ca-bundle|ip-full|ruby|ruby-yaml|kmod-tun|kmod-inet-diag|luci-compat|unzip)=' .config
```

### 7. 预置 OpenClash 运行时资源

需要预置两类资源：

- 面板资源
- Meta 内核

#### 7.1 预置面板资源

目标目录：

- `package/luci-app-openclash/root/usr/share/openclash/ui/dashboard`
- `package/luci-app-openclash/root/usr/share/openclash/ui/yacd`
- `package/luci-app-openclash/root/usr/share/openclash/ui/zashboard`
- `package/luci-app-openclash/root/usr/share/openclash/ui/metacubexd`

建议按 workflow 的来源下载：

- `Dashboard`: `ayanamist/clash-dashboard`
- `Yacd`: `MetaCubeX/Yacd-meta`
- `Zashboard`: `Zephyruso/zashboard`
- `Metacubexd`: `MetaCubeX/metacubexd`

#### 7.2 推导 OpenClash 内核架构

从 `.config` 中读取：

```bash
ARCH_PACKAGES="$(sed -n 's/^CONFIG_TARGET_ARCH_PACKAGES=\"\\(.*\\)\"$/\\1/p' .config | head -n1)"
echo "$ARCH_PACKAGES"
```

按 workflow 当前逻辑映射：

- `aarch64_*` -> `linux-arm64`
- `arm_cortex-a*` / `arm_*neon*` / `arm_*vfpv3*` / `arm_*vfpv4*` -> `linux-armv7`
- `arm_arm1176jzf-s_vfp` / `arm_*arm11*` / `arm_*vfp` -> `linux-armv6`
- `arm_*` -> `linux-armv5`
- `i386*|i486*|i586*|i686*` -> `linux-386`
- `mips64_*` -> `linux-mips64`
- `mipsel_*` -> `linux-mipsle-softfloat`
- `mips_*` -> `linux-mips-softfloat`
- `x86_64` -> `linux-amd64`

若映射失败，不要继续编译，先修正架构映射。

#### 7.3 下载并预置 Meta 内核

下载后放到：

- `package/luci-app-openclash/root/etc/openclash/core/clash_meta`

并赋权：

```bash
chmod 4755 package/luci-app-openclash/luci-app-openclash/root/etc/openclash/core/clash_meta
```

检查点：

```bash
file package/luci-app-openclash/luci-app-openclash/root/etc/openclash/core/clash_meta
ls -l package/luci-app-openclash/luci-app-openclash/root/etc/openclash/core/clash_meta
```

### 8. 下载源码包

执行：

```bash
make download -j"$(nproc)"
```

若失败，可重试：

```bash
make download -j1 V=s
```

### 9. 编译固件

优先并行编译，失败时退回串行详细日志：

```bash
make -j"$(nproc)" || make -j1 V=s
```

如果失败发生在 `package/install`，并且日志里出现上面的 `find ... -execdir` 报错，优先检查宿主机 `PATH`，这属于环境问题，不是 OpenClash 包本身编译失败。

### 10. 校验产物

重点检查：

- `bin/targets/`
- `bin/packages/`

固件层面确认：

- 存在目标固件镜像
- 存在 `luci-app-openclash` 的 `ipk`
- 若构建的是整机固件，根文件系统内应已包含：
  - `/etc/openclash/core/clash_meta`
  - `/usr/share/openclash/ui/dashboard`
  - `/usr/share/openclash/ui/yacd`
  - `/usr/share/openclash/ui/zashboard`
  - `/usr/share/openclash/ui/metacubexd`

## 建议的实际执行顺序

如果你要直接照着跑，建议按下面顺序执行：

```bash
sed -i 's/#src-git helloworld/src-git helloworld/g' ./feeds.conf.default
./scripts/feeds update -a
./scripts/feeds install -a

rm -rf package/feeds/luci/luci-app-openclash package/luci-app-openclash
mkdir -p package/luci-app-openclash
cd package/luci-app-openclash
git init
git remote add -f origin https://github.com/vernesong/OpenClash.git
git config core.sparsecheckout true
echo "luci-app-openclash" >> .git/info/sparse-checkout
git pull --depth 1 origin master
cd /home/blast/src/lede

cd package/luci-app-openclash/luci-app-openclash/tools/po2lmo
make
sudo make install
cd /home/blast/src/lede

# 准备或导入 .config
make menuconfig
make defconfig

# 按上面的步骤追加 OpenClash 主包、依赖、运行时资源

make download -j"$(nproc)"
make -j"$(nproc)" || make -j1 V=s
```

## 风险点

- 当前 workflow 依赖外网下载 GitHub 资源，本地网络受限时会直接失败
- `CONFIG_TARGET_ARCH_PACKAGES` 到 OpenClash 内核架构的映射并不是 OpenWrt 官方映射，遇到少见平台要单独校验
- 当前只预置 `Meta` 内核，不包含其他可选核心
- 面板资源是构建时快照，后续不会自动跟随上游更新

## 完成标准

满足以下条件视为本地编译计划完成：

- 能成功执行 `make defconfig`
- 能成功执行 `make download`
- 能成功编译出目标固件
- `luci-app-openclash` 被编进固件或至少生成对应 `ipk`
- 固件内包含预置面板资源和 `clash_meta`
