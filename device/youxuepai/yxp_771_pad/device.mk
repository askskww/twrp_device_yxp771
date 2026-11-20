#
# device.mk — 设备配置
#
LOCAL_PATH := device/youxuepai/yxp_771_pad

# ===== 拷贝 recovery ramdisk 内容 =====
# ⚠️ 关键：init.recovery.<ro.hardware>.rc 才是运行时真正被 init 读取的文件。
#    本机 ro.hardware = mt8788，所以必须拷 mt8788.rc；
#    mt6771.rc 作为冗余副本一起拷（部分 init 分支会按 ro.board.platform 回退）。
#
# recovery.fstab 不要拷到 system/etc —— TWRP 通过 TARGET_RECOVERY_FSTAB
# 在编译期直接打包到 ramdisk 根目录（/etc/recovery.fstab）。
# 再拷一份到 system/etc 会产生两份 fstab，TWRP 以 /etc/recovery.fstab 为准，
# 多余的副本只会占用空间并可能造成混淆。
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/recovery/root/init.recovery.mt8788.rc:$(TARGET_COPY_OUT_RECOVERY)/root/init.recovery.mt8788.rc \
    $(LOCAL_PATH)/recovery/root/init.recovery.mt6771.rc:$(TARGET_COPY_OUT_RECOVERY)/root/init.recovery.mt6771.rc

# 触摸 / 显示 / 传感器驱动全部内建在内核里，无需 external .ko
# wifi/bt 的 .ko 在 TWRP 中不使用，不拷

# ===== TWRP 内需要的可执行组件 =====
# ⚠️ 不列 fastbootd —— 它需要 android.hardware.fastboot@1.0-impl-mock 配合，
#    本机是 A-only（无 slot），fastbootd 的价值很低，
#    TWRP 自身的刷写界面已覆盖所有需求。
#    少一个包 = 少一个编译失败点。
PRODUCT_PACKAGES += \
    e2fsck \
    mke2fs \
    tune2fs \
    resize2fs \
    linker \
    toybox \
    sh \
    toolbox

# Android 12 强制校验：host 模块必须放 PRODUCT_HOST_PACKAGES，
# 不能混在 PRODUCT_PACKAGES 里（否则 main.mk:1330 直接 Build failed）
PRODUCT_HOST_PACKAGES += \
    adb

# ===== 属性 =====
# 注意：ro.hardware / ro.board.platform 这两个属性在 recovery 里由 kernel
# 的 bootconfig / cmdline 注入（ro.boot.hardware 等），
# 这里写死只是为了在没有 bootconfig 时有个兜底值。
PRODUCT_PROPERTY_OVERRIDES += \
    ro.hardware=mt8788 \
    ro.board.platform=mt6771 \
    ro.sf.lcd_density=240 \
    persist.sys.usb.config=adb

# ===== 分区布局 =====
# 本机是 A-only（AB_OTA_UPDATER=false），但 system/vendor/product 在 super 里
PRODUCT_USE_DYNAMIC_PARTITIONS := true

# ===== 动态分区的分组定义 =====
# 必须与 BoardConfig.mk 里 BOARD_SUPER_PARTITION_GROUPS 的组名一致
# 组名为 yxp_dynamic_partitions，对应变量前缀 BOARD_YXP_DYNAMIC_PARTITIONS_*
# （PRODUCT_LOCALES 在 twrp_yxp_771_pad.mk 里统一定义，此处不重复）