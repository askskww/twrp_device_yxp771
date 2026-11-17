# TWRP Device Tree — YOUXUEPAI P771 (yxp_771_pad)

## 设备信息
| 项 | 值 | 来源 |
|---|---|---|
| 型号 | YOUXUEPAI P771 | getprop |
| 代号 | yxp_771_pad | ro.product.device |
| SoC | MT8183（商用名 MT8788） | ro.soc.model / ro.boot.hardware |
| 软件平台 | MT6771 ALPS alps-mp-s0.mp1 | ro.board.platform / CONFIG_MACH_MT6771 |
| Android | 12 / SDK 31, A-only | ro.build.version |
| 内核 | 4.19.191 aarch64, CONFIG_MTK_FB=y | 内核 config |
| 屏幕 | 1200x1920 DSI, LCM rotation 90 | fb0 / CONFIG_MTK_LCM_PHYSICAL_ROTATION |
| 触摸 | Himax 内建（input8/event7） | /proc/bus/input/devices |
| recovery 分区 | 0x108000 → 0x2108000 = 32MB | scatter.txt |
| boot 分区 | 0x20700000 → 0x22700000 = 32MB | scatter.txt |
| vendor_boot | 0x22700000 → 0x26700000 = 64MB | scatter.txt |
| BL 状态 | unlocked (verifiedbootstate=orange) | /proc/cmdline |

## 完整分区表（scatter.txt 绝对偏移，已交叉验证）
```
preloader    0x0
pgpt         0x0
boot_para    0x8000
recovery     0x108000        32MB   ← 刷 TWRP 的目标
para         0x2108000       512KB
expdb        0x2188000       20MB
frp          0x3588000       1MB
vbmeta       0x3688000       8MB
vbmeta_system 0x3e88000      8MB
vbmeta_vendor 0x4688000      8MB
nvcfg        0x4e88000       32MB
nvdata       0x6e88000       64MB
md_udc       0xae88000       22.6MB
metadata     0xc522000       32MB
protect1     0xe522000       8MB
protect2     0xed22000       10.9MB
seccfg       0xf800000       8MB
sec1         0x10000000      2MB
proinfo      0x10200000      3MB
md1img       0x10500000      100MB
spmfw        0x16900000      1MB
scp1         0x16a00000      6MB
scp2         0x17000000      6MB
sspm_1       0x17600000      1MB
sspm_2       0x17700000      1MB
cam_vpu1     0x17800000      15MB
cam_vpu2     0x18700000      15MB
cam_vpu3     0x19600000      15MB
gz1          0x1a500000      16MB
gz2          0x1b500000      16MB
nvram        0x1c500000      64MB
lk           0x20500000      1MB
lk2          0x20600000      1MB
boot         0x20700000      32MB
vendor_boot  0x22700000      64MB
logo         0x26700000      8MB
dtbo         0x26f00000      8MB
tee1         0x27700000      5MB
tee2         0x27c00000      5MB
super        0x28100000      10.007GB   ← 实测，非估算
cache        0x2a8800000     432MB      ← 实测
userdata     0x2c3800000     ~106GB
```

## 待办事项（按顺序）

### 1. prebuilt 目录（✅ 已完成）

```
device/youxuepai/yxp_771_pad/prebuilt/
└── Image.gz     14,662,280 B  ← gzip 压缩的 aarch64 内核（编译用这个）
```

#### 🔴🔴 铁律：必须用 **Image.gz**，不能用解压后的 Image

| 项 | 大小 | 说明 |
|---|---|---|
| 解压后 `Image` | 29,902,848 B (28.52 MB) | ❌ **不能用** |
| gzip 后 `Image.gz` | 14,662,280 B (13.98 MB) | ✅ **必须用这个** |
| recovery 分区总容量 | 33,554,432 B (32.00 MB) | — |

**为什么必须压缩：**

`mkbootimg` 打包时**不会自动压缩 kernel**。若用 28.52MB 的 `Image`，
加上 TWRP 自己的 ramdisk（正常 12-16MB），最终 `recovery.img` 会到 **40-45MB**，
**远超 32MB 分区**。后果：

1. 刷入时被截断 → TWRP 无法启动
2. 更糟的情况：写入越过 recovery 分区边界，**覆盖后面的 para 分区** → 卡 recovery 循环

**用 Image.gz 后：** 13.98MB + 14MB ramdisk ≈ **28MB < 32MB** ✅

#### 交叉验证（证明 Image.gz 是正确的）

```
我们重新压缩的 Image.gz : 14,662,280 B
原厂 recovery.img 里的     : 14,656,332 B
差值                      :      5,948 B (0.04%)
```

差值来自压缩器实现细节（Python zlib vs 原厂工具），**解压后数据完全一致**：
```
Image.gz 解压后 md5 = ba177fb4aa8af9ee608bbd9c839a6222
原 Image      md5 = ba177fb4aa8af9ee608bbd9c839a6222  ✅
```

gzip 头也与原厂逐字节一致（`1f8b 08 00 00000000 02 03`），
去掉了 Python 默认的 FNAME 字段，确保 MTK 简化解压器也能正常处理。

#### 还需要解压后的 Image 吗？

不需要。真要还原（比如调试时想看内容）：
```sh
gunzip -c prebuilt/Image.gz > prebuilt/Image
```
或用包里附带的 `restore_Image.sh`。

#### 提取方法（如何从原厂 recovery.img 得到这两个文件）

```sh
python3 - <<'EOF'
import struct, gzip, io
f = open('/storage/emulated/0/recovery.img','rb').read()
ps = struct.unpack('<I', f[36:40])[0]   # page_size
ks = struct.unpack('<I', f[8:12])[0]    # kernel_size
rs = struct.unpack('<I', f[12:16])[0]   # ramdisk_size
def align(x): return (x + ps - 1)//ps*ps
off = ps
kernel = f[off:off+ks]; off += align(ks)
ramdisk = f[off:off+rs]
# kernel 本身是 gzip → 直接存为 Image.gz，解压得 Image
open('Image.gz','wb').write(kernel)
open('Image','wb').write(gzip.decompress(kernel))
print(f'Image.gz = {len(kernel):,d} B')
print(f'Image    = {len(gzip.decompress(kernel)):,d} B')
EOF
```

> 本机实测值：`page=2048, kernel_size=14,656,332, ramdisk_size=13,313,762`
> kernel 解压后 29,902,848 B，magic `ARMd` @0x38（标准 aarch64 Image）。
> 注：本机 ramdisk 是 MTK 私有格式（tar 校验失败），但这不影响使用——
> TWRP 用的是它自己的 ramdisk，原厂 ramdisk 完全不用。

### 2. 同步 TWRP 源码（先确认分支名）
```sh
# 注意：TWRP 分支名随版本变化，先查再 init
# 目前常见为 twrp-12.1（对应 Android 12.1），若不存在则用 twrp-12.0
repo init -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git -b twrp-12.1
repo sync -j8 --force-sync
```
⚠️ **分支名务必先确认**：访问 https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp 的 branches 页面，看实际存在的分支。

### 3. 放入 device tree
```sh
mkdir -p device/youxuepai
cp -r /storage/emulated/0/twrp_dev/device/youxuepai/yxp_771_pad device/youxuepai/
```

### 4. 编译
```sh
export ALLOW_MISSING_DEPENDENCIES=true
source build/envsetup.sh
lunch twrp_yxp_771_pad-eng
make -j8 recoveryimage
```
产物：`out/target/product/yxp_771_pad/recovery.img`

### 5. 刷入前的强制安全流程（🔴 不可跳过）

**完整应急手册见 `/storage/emulated/0/EMERGENCY_RECOVERY.md`。**

#### 5.1 先跑体检脚本

```sh
bash /storage/emulated/0/pre_flash_check.sh /sdcard/recovery.img
```

检查项：设备身份、bootloader 锁定状态、电量 ≥60%、recovery 分区存在性、
镜像大小是否 <32MB、ANDROID! magic 是否正确。
**任何 FAIL 都不要刷。**

#### 5.2 先备份原厂分区（必做）

```sh
bash /storage/emulated/0/backup_stock_recovery.sh
```

会备份 `recovery`、`para`、`seccfg`、`boot` 到 `/sdcard/twrp_backup_preflash/`。
**备份完必须拷到电脑** —— 手机刷坏了，手机里的备份也没法用。

⚠️ 特别注意：原厂 `recovery.img`（你 `/sdcard` 上那个 33,554,432 字节的文件）
**绝对不能删**，它是一键回滚的唯一凭据。

#### 5.3 刷入命令

```sh
su
dd if=/sdcard/recovery.img of=/dev/block/by-name/recovery bs=1M
sync                                    # ← 必须！不等 sync 就重启可能写一半
```

⚠️ **`of=` 必须是 `/dev/block/by-name/recovery`，不是 `boot`。**
本树已从 fstab 移除除 recovery 外所有分区的 `flashimg=1`，
所以 TWRP 的「刷入镜像」界面里只会看到 recovery 一个可选项，降低误操作风险。

#### 5.4 编译产物自动防砖（已在 workflow 中实现）

GitHub Actions 有两道硬校验，任一不过直接让 workflow 失败：

| 时机 | 检查 |
|---|---|
| 编译前 | `TARGET_PREBUILT_KERNEL` 不能指向未压缩 Image；Image.gz 必须 <20MB；`AB_OTA_UPDATER` 必须 false |
| 产物生成后 | 镜像 ≤32MB（超 1 字节就 fail）；ANDROID! magic 正确；kernel_size <20MB（验证已压缩）；ramdisk_size <20MB |

### 6. 如果黑屏/花屏（分级处置）

| 现象 | 原因 | 处理 |
|---|---|---|
| 画面重复 3 次 | MTK fb 三缓冲未处理 | 打 minui 补丁（见下） |
| 完全黑 | 背光节点路径不对 | `/sys/class/leds/` 下确认实际节点 |
| 触摸不动 | event 号不对 | `/proc/bus/input/devices` 确认，加 `TW_INPUT_BLACKLIST` |
| 卡 logo 超 5 分钟 | 启动失败 | 长按电源 20 秒强重启，刷回原厂 recovery |

**重要：卡住不等于变砖。** 只要 boot 分区没动，系统本体一定还在。
详见 `EMERGENCY_RECOVERY.md` 的 L1~L6 分级处置。

## 参考树与交叉验证记录

### 已核对的参考树
`github.com/shadowofleaf96/android_device_umidgi_f1`（UMIDIGI F1 Play, MT6771 Helio P60, LineageOS 18.1）

**三条关键交叉验证结果（全部吻合）：**

| 参数 | 参考树写法 | 你的 recovery.img header 实测 | 结果 |
|---|---|---|---|
| kernel_addr | 0x40078000 + 0x8000 = **0x40080000** | 0x40080000 | ✅ 一致 |
| ramdisk_addr | 0x40078000 + 0x14f88000 = **0x55000000** | 0x55000000 | ✅ 一致 |
| tags_addr | 0x40078000 + 0x13f88000 = **0x54000000** | 0x54000000 | ✅ 一致 |
| recovery 分区大小 | 33554432 (32MB) | scatter: 0x108000→0x2108000 = 32MB | ✅ 一致 |
| cmdline 前缀 | `bootopt=64S3,32N2,64N2` | `bootopt=64S3,32N2,64N2 buildvariant=userdebug` | ✅ 一致 |
| 背光路径 | `/sys/class/leds/lcd-backlight/brightness` | 同 | ✅ 一致 |

**已从参考树采纳的内容：**
- `BOARD_KERNEL_BASE := 0x40078000` 系列标准写法（比原来 0x40000000 更规范）
- USB gadget / adb 相关 rc 配置
- `BOARD_USES_MTK_HARDWARE` / `BOARD_HAS_MTK_HARDWARE`
- `TARGET_RECOVERY_LCD_BACKLIGHT_PATH` / `TARGET_USES_MKE2FS`

**未采纳（实机验证后否决）：**
- 该树的 `zImage`（32位内核）→ 本机必须用 aarch64 `Image.gz`
- `preloader_a/_b`、`mmcblk0boot0/1` symlink → 本机 A-only，无此分区
- `musb-hdrc` UDC 名 → 本机未确认，不写死
- 🔴 **`symlink /dev/block/platform/bootdevice /dev/block/bootdevice`** →
  实机 `/dev/block/platform/bootdevice` **根本不存在**（`ls /dev/block/` 只有
  `sdc2 sdc4 zram1`，被 noah 管控裁剪）。本机正确路径是 `/dev/block/by-name/`，
  已按 vendor fstab 实证全部改写。

## MTK 三缓冲 minui 补丁要点
fb0 `virtual_size=1216,5760`，`minui` 默认把 height 当 5760 处理，画出来会重复 3 次。
补丁位置：`bootable/recovery/minui/graphics_fbdev.cpp`，在 `gr_init` 里把 `vi.yres` 改为 `vi.yres_virtual / buffer_count`，或者用 `fb_var_screeninfo.yoffset` 分页刷新。

## 已知风险
1. **`para` 分区曾被写入**（2026-11-15 17:22，GeekFlashTool 自动），若手机能正常开机则无害
2. **教育机可能有 noah 系统校验**（OTA/seccfg 层面），刷 TWRP 后可能与原系统冲突
3. **userdata 未加密**（ro.crypto.state=unencrypted），所以 TWRP 不需要 FBE 解密能力
4. **Magisk 环境不随 recovery 加载**，刷完 TWRP 后需要重新处理 root