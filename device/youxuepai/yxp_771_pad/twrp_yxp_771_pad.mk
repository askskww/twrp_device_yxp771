#
# twrp_yxp_771_pad.mk — 产品定义
#
# ⚠️ inherit 顺序很重要：
#   base.mk 会内部继承 core_minimal.mk，如果 core_64_bit.mk 放在 base 之前，
#   会被 base 的继承链覆盖掉 64 位配置。
#   正确顺序：base → core_64_bit（后者覆盖前者的架构设置）
#
$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)

# [REMOVED] embedded.mk — 该文件在 android-12.1 中不存在
# 核实结果：TeamWin/android_build@android-12.1 的 target/product/ 共 103
# 个文件，没有 embedded.mk（它属于 Android 8/9 时代）。
# recovery 所需基础配置由 base.mk + vendor/twrp/config/common.mk 提供。

# TWRP 基础（这些在 TWRP manifest 里存在，用 if-exists 防止缺失时报错）
$(call inherit-product-if-exists, vendor/twrp/config/common.mk)
$(call inherit-product-if-exists, vendor/twrp/config/gsm.mk)

# 设备配置
$(call inherit-product, device/youxuepai/yxp_771_pad/device.mk)

# ===== 产品身份 =====
PRODUCT_NAME := twrp_yxp_771_pad
PRODUCT_DEVICE := yxp_771_pad
PRODUCT_BRAND := YOUXUEPAI
PRODUCT_MODEL := P771
PRODUCT_MANUFACTURER := YOUXUEPAI
PRODUCT_RELEASE_NAME := yxp_771_pad

# ===== 屏幕 =====
TARGET_SCREEN_HEIGHT := 1920
TARGET_SCREEN_WIDTH := 1200

# ===== 语言（唯一定义处，device.mk 里不再重复）=====
PRODUCT_LOCALES := zh_CN zh_TW en_US
PRODUCT_DEFAULT_LANGUAGE := zh
PRODUCT_DEFAULT_REGION := CN

# ===== API 等级 =====
# 本机出厂 Android 12 = SDK 31
PRODUCT_SHIPPING_API_LEVEL := 31