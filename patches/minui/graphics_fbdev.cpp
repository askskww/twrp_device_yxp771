/*
 * MTK triple-buffer patch for YOUXUEPAI P771 (yxp_771_pad)
 * 目标文件：bootable/recovery/minui/graphics_fbdev.cpp
 *
 * ============ 基线来源（已实机验证）============
 * TWRP 12.1 的 bootable/recovery 来自：
 *   TeamWin/android_bootable_recovery @ android-12.1
 *   （由 minimal-manifest-twrp/platform_manifest_twrp_aosp 的
 *     twrp-default.xml 通过 remove-project + project 覆盖）
 * 本文件 = 该分支原始 graphics_fbdev.cpp + 三缓冲适配修改。
 * 原文件 sha: 353a070fc9c28685d40f0f617554090a70bef05c
 *
 * ============ 问题诊断 ============
 * 本机 fb0 实际参数：
 *   xres=1200  yres=1920
 *   xres_virtual=1216  yres_virtual=5760   ← 1920 * 3 三缓冲
 *   line_length=4864   smem_len≈28MB
 *
 * 原版两处假设「只有 2 个缓冲」：
 *   (A) SetDisplayedFramebuffer(): vi.yres_virtual = height * 2;   ← 写死 2
 *   (B) Init():                    if (yres*line_length*2 <= smem_len) double_buffered = true;
 *
 * 后果：驱动 yres_virtual 被从 5760 改成 3840，
 *       但 MTK 显示硬件/Ovl 仍按 3 slot 输出，
 *       于是出现「同一画面竖直重复 3 次」或「只占上 1/3」。
 *
 * ============ 修复策略 ============
 * 【不改缓冲数量，改「单缓冲绘制 + 安全 yoffset 切页」】
 *   原因：gr_framebuffer 是 size-2 的 unique_ptr 数组，
 *         接第三块内存会数组越界 → 段错误。
 *
 *   做法：
 *     1) 始终 double_buffered = false（走内存缓冲区 memcpy 路径）
 *     2) 内存 buffer 仍为完整一屏（1920 行），绘制逻辑不变
 *     3) Flip() 时把内存 buffer 拷到「下一个」slot，
 *        再用 yoffset 切换（FBIOPUT_VSCREENINFO）
 *     4) slot 数量运行时探测：yres_virtual / yres，并用 smem_len 校验
 *     5) 关键：不把 yres_virtual 改小，只改 yoffset
 *
 *   兼容：slot=1 时行为等同单缓冲；slot=2 时等同原生双缓冲；
 *         slot>=3 时按真实数量轮转。
 *
 * ============ 验证方法 ============
 * 进 TWRP 后看 /tmp/recovery.log，应出现：
 *   fbdev: slot_height=1920 slot_bytes=9338880 line_length=4864 smem_len=28016640 -> slot_count=3
 *   若 slot_count=3 且画面正常 → 补丁生效
 */

#include "graphics_fbdev.h"

#include <fcntl.h>
#include <linux/fb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>

#include <memory>

#include <android-base/unique_fd.h>

#include "minui/minui.h"

// ---- 本补丁私有状态（文件内静态，不改头文件）----
namespace {
int g_slot_count = 1;      // 探测到的 slot 数（1/2/3…）
size_t g_slot_bytes = 0;   // 每个 slot 字节数 = slot_height * line_length
int g_slot_height = 0;     // 每个 slot 行数（用 vi.yres）
size_t g_current_slot = 0; // 当前显示中的 slot
}  // namespace

std::unique_ptr<GRSurfaceFbdev> GRSurfaceFbdev::Create(size_t width, size_t height,
                                                       size_t row_bytes, size_t pixel_bytes) {
  // Cannot use std::make_unique to access non-public ctor.
  return std::unique_ptr<GRSurfaceFbdev>(new GRSurfaceFbdev(width, height, row_bytes, pixel_bytes));
}

// ===== 保持 TWRP 12.1 原版的背光分支（勿删，否则 TW_NO_SCREEN_BLANK 失效）=====
void MinuiBackendFbdev::Blank(bool blank) {
#if defined(TW_NO_SCREEN_BLANK) && defined(TW_BRIGHTNESS_PATH) && defined(TW_MAX_BRIGHTNESS)
    int fd;
    char brightness[4];
    snprintf(brightness, 4, "%03d", TW_MAX_BRIGHTNESS / 2);

    fd = open(TW_BRIGHTNESS_PATH, O_RDWR);
    if (fd < 0) {
        perror("cannot open LCD backlight");
        return;
    }
    write(fd, blank ? "000" : brightness, 3);
    close(fd);
#else
    int ret;

    ret = ioctl(fb_fd, FBIOBLANK, blank ? FB_BLANK_POWERDOWN : FB_BLANK_UNBLANK);
    if (ret < 0)
        perror("ioctl(): blank");
#endif
}

// ===== 修改点 1：只改 yoffset，绝不写死 yres_virtual =====
void MinuiBackendFbdev::SetDisplayedFramebuffer(size_t n) {
  if (g_slot_count < 1) return;
  if (n >= static_cast<size_t>(g_slot_count)) return;

  // 保持驱动原始 yres_virtual（本机 5760），只切 yoffset
  vi.yoffset = static_cast<__u32>(n) * static_cast<__u32>(g_slot_height);
  vi.bits_per_pixel = gr_framebuffer[0]->pixel_bytes * 8;
  if (ioctl(fb_fd, FBIOPUT_VSCREENINFO, &vi) < 0) {
    perror("active fb swap failed");
  }
  displayed_buffer = n;
}

GRSurface* MinuiBackendFbdev::Init() {
  android::base::unique_fd fd(open("/dev/graphics/fb0", O_RDWR | O_CLOEXEC));
  if (fd == -1) {
    perror("cannot open fb0");
    return nullptr;
  }

  fb_fix_screeninfo fi;
  if (ioctl(fd, FBIOGET_FSCREENINFO, &fi) < 0) {
    perror("failed to get fb0 info");
    return nullptr;
  }

  if (ioctl(fd, FBIOGET_VSCREENINFO, &vi) < 0) {
    perror("failed to get fb0 info");
    return nullptr;
  }

  // We print this out for informational purposes only, but
  // throughout we assume that the framebuffer device uses an RGBX
  // pixel format.  This is the case for every development device I
  // have access to.  For some of those devices (eg, hammerhead aka
  // Nexus 5), FBIOGET_VSCREENINFO *reports* that it wants a
  // different format (XBGR) but actually produces the correct
  // results on the display when you write RGBX.
  //
  // If you have a device that actually *needs* another pixel format
  // (ie, BGRX, or 565), patches welcome...

  printf(
      "fb0 reports (possibly inaccurate):\n"
      "  vi.xres = %u   vi.yres = %u\n"
      "  vi.xres_virtual = %u   vi.yres_virtual = %u\n"
      "  vi.bits_per_pixel = %u\n"
      "  vi.red.offset   = %3u   .length = %3u\n"
      "  vi.green.offset = %3u   .length = %3u\n"
      "  vi.blue.offset  = %3u   .length = %3u\n"
      "  fi.line_length  = %u   fi.smem_len = %u\n",
      vi.xres, vi.yres, vi.xres_virtual, vi.yres_virtual, vi.bits_per_pixel, vi.red.offset,
      vi.red.length, vi.green.offset, vi.green.length, vi.blue.offset, vi.blue.length,
      fi.line_length, fi.smem_len);

  void* bits = mmap(0, fi.smem_len, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (bits == MAP_FAILED) {
    perror("failed to mmap framebuffer");
    return nullptr;
  }

  memset(bits, 0, fi.smem_len);

  gr_framebuffer[0] =
      GRSurfaceFbdev::Create(vi.xres, vi.yres, fi.line_length, vi.bits_per_pixel / 8);
  gr_framebuffer[0]->buffer_ = static_cast<uint8_t*>(bits);
  memset(gr_framebuffer[0]->buffer_, 0, gr_framebuffer[0]->height * gr_framebuffer[0]->row_bytes);

  gr_framebuffer[1] =
      GRSurfaceFbdev::Create(gr_framebuffer[0]->width, gr_framebuffer[0]->height,
                             gr_framebuffer[0]->row_bytes, gr_framebuffer[0]->pixel_bytes);

  // ===== 修改点 2：探测真实 slot 数 =====
  g_slot_height = static_cast<int>(vi.yres);
  if (g_slot_height <= 0) g_slot_height = static_cast<int>(gr_framebuffer[0]->height);

  g_slot_bytes = static_cast<size_t>(g_slot_height) * static_cast<size_t>(fi.line_length);

  int slots = 1;
  if (g_slot_height > 0) slots = static_cast<int>(vi.yres_virtual) / g_slot_height;
  if (g_slot_bytes > 0) {
    int by_mem = static_cast<int>(static_cast<size_t>(fi.smem_len) / g_slot_bytes);
    if (by_mem < slots) slots = by_mem;  // smem_len 交叉校验，防 yres_virtual 虚报
  }
  if (slots < 1) slots = 1;
  if (slots > 4) slots = 4;

  g_slot_count = slots;
  g_current_slot = 0;

  printf("fbdev: slot_height=%d slot_bytes=%zu line_length=%u smem_len=%u -> slot_count=%d\n",
         g_slot_height, g_slot_bytes, fi.line_length, fi.smem_len, g_slot_count);

  // ===== 修改点 3：强制走「内存绘制 + Flip 时 memcpy 到后台 slot」=====
  // 避免访问 gr_framebuffer[2]（数组只有 2 个元素）
  double_buffered = false;
  memory_buffer.resize(gr_framebuffer[1]->height * gr_framebuffer[1]->row_bytes);
  gr_framebuffer[1]->buffer_ = memory_buffer.data();

  gr_draw = gr_framebuffer[1].get();
  memset(gr_draw->buffer_, 0, gr_draw->height * gr_draw->row_bytes);
  fb_fd = std::move(fd);

  // 把所有 slot 清空，避免残留旧画面（MTK 三缓冲时尤其明显）
  memset(bits, 0, fi.smem_len);
  SetDisplayedFramebuffer(0);

  printf("framebuffer: %d (%zu x %zu)\n", fb_fd.get(), gr_draw->width, gr_draw->height);

  Blank(true);
  Blank(false);

  return gr_draw;
}

// ===== 修改点 4：Flip 改为「拷到后台 slot + 切 yoffset」=====
GRSurface* MinuiBackendFbdev::Flip() {
  size_t copy_bytes = static_cast<size_t>(g_slot_height) * gr_draw->row_bytes;
  if (copy_bytes > g_slot_bytes) copy_bytes = g_slot_bytes;

  if (g_slot_count >= 2 && gr_framebuffer[0]->buffer_ != nullptr) {
    // 轮转到下一个 slot，永远不画正在显示的那个，避免撕裂
    size_t next = (g_current_slot + 1) % static_cast<size_t>(g_slot_count);
    uint8_t* dst = gr_framebuffer[0]->buffer_ + g_slot_bytes * next;
    memcpy(dst, gr_draw->buffer_, copy_bytes);
    g_current_slot = next;
    SetDisplayedFramebuffer(next);
  } else {
    // 单 slot：直接 memcpy 到第一屏（与原生非双缓冲路径一致）
    memcpy(gr_framebuffer[0]->buffer_, gr_draw->buffer_, copy_bytes);
  }
  return gr_draw;
}

// ==================== 若编译报 "redefinition of Flip" ====================
// 说明 graphics_fbdev.h 里已把 Flip() 写成 inline。
// 处理：打开 bootable/recovery/minui/graphics_fbdev.h，
//       删掉其中 Flip() 的 inline 函数体（保留声明即可），
//       或把本文件末尾的 Flip() 实现整段删除并在头里改。
// ======================================================================