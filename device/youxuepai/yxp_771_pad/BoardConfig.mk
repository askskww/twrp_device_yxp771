#
# BoardConfig.mk for YOUXUEPAI P771 (yxp_771_pad)
# SoC: MT8183 (ro.soc.model) / MT8788 (ro.boot.hardware)
# SW platform: MT6771 branch (ALPS alps-mp-s0.mp1, Android 12 / SDK 31)
# Kernel: 4.19.191 aarch64, MTK FB (no DRM)
# Recovery: independent 32MB partition, boot image header v0, page_size 2048
#
# 数据来源：
#   - recovery.img header (magic/kernel/ramdisk addr/page_size/cmdline)
#   - scatter.txt 绝对地址表 (recovery @ 0x108000, size 32MB)
#   - vendor/etc/fstab.mt6771
#   - kernel config (4.19.191)
#

# ===== 平台与架构 =====
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := cortex-a53
TARGET_CPU_VARIANT_RUNTIME := cortex-a73
TARGET_CPU_ABI_LIST_64_BIT := arm64-v8a

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := cortex-a53
TARGET_2ND_CPU_VARIANT_RUNTIME := cortex-a53
TARGET_CPU_ABI_LIST_32_BIT := armeabi-v7a,armeabi

# ⚠️ 平台双名（实机 getprop 验证）：
#   ro.board.platform = mt6771  ← 编译分支名（ALPS alps-mp-s0.mp1）
#   ro.hardware       = mt8788  ← 运行时硬件名（init 用它找 *.rc）
# 二者都是真的，不要只留一个。
TARGET_BOARD_PLATFORM := mt6771
TARGET_BOARD_PLATFORM_GPU := mali-g72
TARGET_BOOTLOADER_BOARD_NAME := yxp_771_pad


# recovery 的 init 文件名按 ro.hardware(mt8788) 命名，
# 同时保留 mt6771 副本兜底（见 recovery/root/）

TARGET_NO_BOOTLOADER := true
TARGET_NO_KERNEL := false
TARGET_NO_RECOVERY := false

# ===== Kernel / Boot image =====
# 直接复用原厂 recovery 分区里的 kernel（触摸、LCM、fb 全部内建驱动）
#
# ⚠️⚠️ 关键：必须用 **Image.gz（gzip 压缩后的内核）**，不能用解压后的 Image！
#
#   原因（实测数据）：
#     解压后 Image  : 29,902,848 B (28.52 MB)
#     gzip 后 Image.gz: 14,662,286 B (13.98 MB)   ← 压缩率 49%
#     recovery 分区总 : 33,554,432 B (32.00 MB)
#
#   mkbootimg 打包时**不会**自动压缩 kernel，
#   若用 28.52MB 的 Image，加上 TWRP ramdisk(12-18MB) 会到 40-50MB，
#   远超 32MB 分区 → 镜像刷不进去。
#
#   验证：我们重新压缩的 Image.gz = 14,662,286 B，
#         原厂 recovery.img 里的 kernel.gz = 14,656,332 B，
#         只差 5,954 字节（0.04%），说明压缩参数与原厂一致。
TARGET_PREBUILT_KERNEL := device/youxuepai/yxp_771_pad/prebuilt/Image.gz
BOARD_KERNEL_IMAGE_NAME := Image.gz

# 打包参数：与 header 实测一致（见下方交叉验证）
BOARD_KERNEL_CMDLINE := bootopt=64S3,32N2,64N2 buildvariant=userdebug
BOARD_KERNEL_BASE := 0x40078000
BOARD_KERNEL_PAGESIZE := 2048
BOARD_HASH_TYPE := sha1
BOARD_KERNEL_OFFSET := 0x00008000
BOARD_RAMDISK_OFFSET := 0x14f88000
BOARD_SECOND_OFFSET := 0x00e88000
BOARD_KERNEL_TAGS_OFFSET := 0x13f88000

# 交叉验证（你的 recovery.img header 实测值）：
#   kernel_addr  = 0x40080000 = 0x40078000 + 0x8000      ✅
#   ramdisk_addr = 0x55000000 = 0x40078000 + 0x14f88000  ✅
#   tags_addr    = 0x54000000 = 0x40078000 + 0x13f88000  ✅
# 三个地址与真实镜像 100% 吻合，说明这套 offset 就是本机 MTK 打包参数。

BOARD_MKBOOTIMG_ARGS := --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_KERNEL_TAGS_OFFSET)
BOARD_MKBOOTIMG_ARGS += --kernel_offset $(BOARD_KERNEL_OFFSET)
BOARD_MKBOOTIMG_ARGS += --second_offset $(BOARD_SECOND_OFFSET)
BOARD_MKBOOTIMG_ARGS += --base $(BOARD_KERNEL_BASE)
BOARD_MKBOOTIMG_ARGS += --pagesize $(BOARD_KERNEL_PAGESIZE)
# 🔴 关键修复（2026-11-21，实机对照原厂 recovery.img 得出）：
# 原厂 recovery.img header_version = 2，带 dtb(138,531B) + recovery_dtbo(51,239B)。
# header v0 时 LK 走老路径，完全不会加载 DTB/DTBO，内核拿不到设备树 → pwrap/PMIC/
# display 全部初始化失败 → 黑屏 → PMIC_cold_reboot（实机上已观测到 4 次）。
BOARD_MKBOOTIMG_ARGS += --header_version 2

# ===== DTB / DTBO（从原厂 recovery.img 中精确切出）=====
# dtb.img       : 138,531 B  MD5 2e9e2f5c7c99febe8db8fe800f817ecf  (d00dfeed, ver 17)
# recovery_dtbo :  51,239 B  MD5 60b68758821d385857919744c2156442  (d7b7ab1e, 32 entry)
# dtb_addr      : 0x54000000（原厂 header 实测）→ = 0x40078000 + 0x13f88000，与 tags_addr 同址
BOARD_INCLUDE_DTB_IN_BOOTIMG := true
BOARD_PREBUILT_DTBIMAGE_DIR := device/youxuepai/yxp_771_pad/prebuilt
BOARD_DTBIMAGE := $(BOARD_PREBUILT_DTBIMAGE_DIR)/dtb.img
BOARD_PREBUILT_DTBOIMAGE := $(BOARD_PREBUILT_DTBIMAGE_DIR)/recovery_dtbo
BOARD_MKBOOTIMG_ARGS += --dtb $(BOARD_DTBIMAGE)
BOARD_MKBOOTIMG_ARGS += --dtb_offset 0x13f88000
# DTBO 打进 recovery.img 的 recovery_dtbo 段（header v2 才有该字段）
BOARD_MKBOOTIMG_ARGS += --recovery_dtbo $(BOARD_PREBUILT_DTBOIMAGE)

# ===== 分区大小（全部来自 scatter.txt 相邻偏移差，非估算）=====
# 计算方法：size = 下一分区起始偏移 - 本分区起始偏移
BOARD_BOOTIMAGE_PARTITION_SIZE := 33554432       # boot 0x20700000 → vendor_boot 0x22700000
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 33554432   # recovery 0x108000 → para 0x2108000
BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE := ext4
# cache 0x2A8800000 → userdata 0x2C3800000 = 452,984,832
BOARD_CACHEIMAGE_PARTITION_SIZE := 452984832
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_DTBOIMG_PARTITION_SIZE := 8388608          # dtbo 0x26F00000 → tee1 0x27700000
# 已禁用：本机虽有 vendor_boot 分区，但我们只生成独立 recovery.img，不打包 vendor_boot。
# Android 12 build/make 一旦看到此变量就会给 recovery packaging 套用 vendor_boot 的
# rsync 逻辑，试图把 recovery/root/vendor 变成软链接，与动态分区实体目录冲突：
#   could not make way for new symlink: root/vendor
#   rsync error: some files/attrs were not transferred (code 23)
# BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 67108864 # vendor_boot 0x22700000 → logo 0x26700000

BOARD_USES_METADATA_PARTITION := true

# super 0x28100000 → cache 0x2A8800000 = 10,744,758,272 字节（约 10.007 GiB）
# ⚠️ 这是「偏移跨度」上界，真实分区表里的 size 可能略小，
#    但写入 super 的构建配置时用上界是安全的（不会超出物理分区）。
BOARD_SUPER_PARTITION_SIZE := 10744758272
BOARD_SUPER_PARTITION_GROUPS := yxp_dynamic_partitions
# group 可用空间 = super 总大小 - lp_metadata 预留（Android 默认 4MiB）
BOARD_YXP_DYNAMIC_PARTITIONS_SIZE := 10740610048
BOARD_YXP_DYNAMIC_PARTITIONS_PARTITION_LIST := system vendor product

BOARD_FLASH_BLOCK_SIZE := 131072

# ===== 文件系统 / Recovery =====
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
TARGET_USES_MKE2FS := true
BOARD_HAS_LARGE_FILESYSTEM := true
TARGET_RECOVERY_PIXEL_FORMAT := "BGRA_8888"
TARGET_RECOVERY_FSTAB := device/youxuepai/yxp_771_pad/recovery.fstab
TARGET_RECOVERY_LCD_BACKLIGHT_PATH := "/sys/class/leds/lcd-backlight/brightness"
BOARD_CHARGER_ENABLE_SUSPEND := true

# MTK 硬件标记（必需，否则 MTK 专有组件可能不参与编译）
BOARD_USES_MTK_HARDWARE := true
BOARD_HAS_MTK_HARDWARE := true

# 无 vendor_boot 分离的 recovery 启动路径（独立 recovery 分区，A-only）
AB_OTA_UPDATER := false
BOARD_USES_RECOVERY_AS_BOOT := false
BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT := false

# ⚠️ 显式钉死 recovery 资源输出目录。
# 本机虽然存在 vendor_boot 分区，但 recovery 是独立分区（非 recovery-as-boot），
# Android 12 的 build 系统在检测到 vendor_boot 时可能把
# TARGET_COPY_OUT_RECOVERY 解析成 vendor_boot，
# 导致 device.mk 里 PRODUCT_COPY_FILES 的 init.recovery.*.rc 被拷到错误位置。
TARGET_COPY_OUT_RECOVERY := recovery

# ===== TWRP 专属 =====
RECOVERY_VARIANT := twrp

TW_THEME := landscape_hdpi
# 屏幕物理 1200x1920（竖），LCM physical rotation=90 → 实际显示 1920x1200 横屏
# 所以必须用 landscape 主题，用 portrait 会导致 UI 错位（图标被裁、按钮点不到）
TW_ROTATION := 90
TW_DEFAULT_LANGUAGE := zh_CN
# TW_EXTRA_LANGUAGES 不要留空值 —— 空赋值在部分 TWRP 分支里会被当作"启用全部语言"，
# 导致编译时打包大量用不到的语言包、增大镜像体积。
# 如需多语言，写成 true；不需要就整行注释掉。
# TW_EXTRA_LANGUAGES := true
TW_INCLUDE_CRYPTO := false          # ro.crypto.state=unencrypted，暂不需要 FBE
TW_INCLUDE_CRYPTO_FBE := false
TW_INCLUDE_FBE_METADATA_DECRYPT := false
TW_EXCLUDE_DEFAULT_USB_INIT := true
TW_INCLUDE_NTFS_3G := true
TW_INCLUDE_FUSE_EXFAT := true
TW_INCLUDE_FUSE_NTFS := true
TW_USE_TOOLBOX := true
TW_BRIGHTNESS_PATH := "/sys/class/leds/lcd-backlight/brightness"
TW_CUSTOM_BATTERY_PATH := "/sys/class/power_supply/battery"
# TW_SECONDARY_BRIGHTNESS_PATH 已注释：原值指向 leds-mt65xx，
# 但 MT8183 不是 mt65xx 系列，该节点几乎肯定不存在（写了也是无效路径）。
# 主路径 TW_BRIGHTNESS_PATH 已确认可用，无需备用路径。
# TW_SECONDARY_BRIGHTNESS_PATH := "/sys/devices/platform/leds-mt65xx/leds/lcd-backlight/brightness"
TW_HAS_EDL_MODE := true
TW_EXCLUDE_TWRPAPP := true

# MTK 平台专属
TW_HAS_MTK_FB := true               # CONFIG_MTK_FB=y，走 /dev/graphics/fb0
TW_SCREEN_BLANK_ON_BOOT := true
# TW_INPUT_BLACKLIST 已注释：原值 "hbtp_vm" 抄自 UMIDIGI 参考树，
# 本机是否有该输入设备未确认。minui 会自动忽略无事件的设备，
# 这里写死反而有"误杀真实触摸设备"的风险。
# 若进 TWRP 后发现触摸事件错乱，再按 /proc/bus/input/devices 实际名字填。
# TW_INPUT_BLACKLIST := "hbtp_vm"

# ===== 电池 / 温度（MTK 常见坑，来自 momo54181 实践）=====
# MTK 设备 TWRP 常显示电池 0% 或恒 100%，用传统 battey 服务可修
TW_USE_LEGACY_BATTERY_SERVICES := true
TW_BATTERY_SYSFS_WAIT_SECONDS := 6
TW_CUSTOM_BATTERY_POS := 800
# CPU 温度节点尚未在 recovery 环境确认，先注释；查法见 README
# TW_CUSTOM_CPU_TEMP_PATH := /sys/class/thermal/thermal_zone0/temp
# TW_CUSTOM_CPU_POS := 50
# TW_CUSTOM_CLOCK_POS := 300

# ===== 调试相关（务必保留，出问题全靠它）=====
TWRP_INCLUDE_LOGCAT := true
TARGET_USES_LOGD := true
# 🔴 防砖关键：开启详细日志。
#    卡 TWRP logo / 黑屏 / 挂载失败时，没有它只能盲猜；
#    有它可以在 TWRP 内 Advanced → View Log 或 /tmp/recovery.log 看到具体错误。
#    唯一代价是镜像体积增加约 100-300KB，相对 32MB 分区可忽略。
TW_VERBOSE := true

# 🔴 防砖关键：禁止屏幕超时熄灭。
#    刷写过程中屏幕黑了，看不出卡在哪一步，容易误判为死机而强行断电。
#    （强行断电在写 emmc 中途 = 潜在变砖）
TW_NO_SCREEN_TIMEOUT := true
TW_NO_SCREEN_BLANK := true

# 亮度：不要设太高，长时间停在 TWRP 界面防烧屏/过热
TW_MAX_BRIGHTNESS := 2047
TW_DEFAULT_BRIGHTNESS := 700

# 需要排查触屏时，临时打开下面这行（会快速写满日志，调试完关掉）
# TW_EVENT_LOGGING := true

# ===== 动态分区逻辑分区名单 =====
# 只列 super 里真实存在的逻辑分区。
# 本机 super 内只有 system / vendor / product（见 vendor fstab 的 logical 标记），
# 没有 odm —— 列了 odm 会让 TWRP 启动时尝试映射不存在的分区并报错。
TW_INCLUDE_LOGICAL := system vendor product

# ===== 显示微调（1016 对齐差异兜底）=====
# fb0 xres=1200 但 virtual 宽 1216，若进 TWRP 后界面右侧被裁，
# 试着取消下面两行注释微调（单位像素）
# TW_X_OFFSET := 0
# TW_H_OFFSET := 0
# 若整个画面上下颠倒（横屏方向反了），打开下面这行
# BOARD_HAS_FLIPPED_SCREEN := true

# TWRP 版本标识（显示在关于页面）
TW_DEVICE_VERSION := yxp771-by-operit

# fb0 virtual_size=1216,5760 (1216 宽 = 1200 对齐 + 16，5760 = 1920*3 三缓冲)
# ⚠️ 这个问题不能靠 BoardConfig 解决，必须改 minui 源码：
#    替换 bootable/recovery/minui/graphics_fbdev.cpp
#    补丁已备好：patches/minui/graphics_fbdev.cpp

# 触摸：himax-touchscreen (input8/event7) + mtk-tpd (input7/event8)，均内建驱动
# 无需额外 ramdisk 模块

# ===== 编译优化 =====
TARGET_USES_64_BIT_BINDER := true
TARGET_SUPPORTS_32_BIT_APPS := true
TARGET_SUPPORTS_64_BIT_APPS := true
ALLOW_MISSING_DEPENDENCIES := true

# 关闭 AVB（生成后手动 erase_footer 或用 disable-verity 刷入）
BOARD_AVB_ENABLE := false