# FPGA 安路视频处理工程

基于安路 `PH1P35MDG324` FPGA 和 HX1P35A 开发板的视频处理工程，实现 SC500 摄像头采集、ISP 处理、DDR 缓存、实时图像算法和 HDMI 显示。

## 工程结构

```text
.
├─ td_project/                       # Tang Dynasty 工程及实现结果
├─ user_source/
│  ├─ constraints_source/            # 引脚和时序约束
│  ├─ hdl_source/                    # Verilog/SystemVerilog 源码
│  └─ ip_source/                     # PLL、FIFO、DDR 等 IP
└─ README.md
```

工程顶层为：

```text
design_top_wrapper
```

Tang Dynasty 工程文件为：

```text
td_project/camera_to_dsi_display.al
```

## 视频链路

```text
SC500 摄像头
    ↓
2-lane MIPI CSI-2
    ↓
RAW10 解包
    ↓
ISP：Demosaic + AWB
    ↓
DDR 四帧缓存
    ↓
img_processing
    ↓
HDMI 720p 显示
```

目标视频格式：

- 分辨率：`1280 × 720`
- 帧率：`60 fps`
- HDMI 像素时钟：约 `74.25 MHz`
- Bayer 模式：`BGGR`

## 图像处理算法

`img_processing` 位于 DDR 和 HDMI 之间，是顶层的二级视频处理模块。

```text
img_processing
├─ rgb2ycbcr
└─ sobel_edge
```

### RGB2YCbCr

- 文件：`user_source/hdl_source/rgb.v`
- 输入：RGB888
- 输出：YCbCr888，格式为 `{Y, Cb, Cr}`
- 使用流水线结构，每时钟处理一个像素

### 灰度化和二值化

- 灰度图使用 Y 通道输出：`{Y, Y, Y}`
- 二值化阈值：`Y >= 128`
- 二值化输出为黑色或白色

### Sobel 边缘检测

- 文件：`user_source/hdl_source/sobel.v`
- 仅处理 Y 通道
- 使用两行缓存构造 `3 × 3` 窗口
- 采用流水线计算 `|Gx| + |Gy|`
- 输出灰度梯度图
- 边界区域输出黑色

## 模式控制

模式控制模块为：

```text
user_source/hdl_source/control_top.v
```

### 按键控制

开发板按键为低电平有效：

| 按键 | FPGA 引脚 | 功能 |
|---|---|---|
| KEY1 | D5 | 保留，暂未使用 |
| KEY2 | A9 | 保留，暂未使用 |
| KEY3 | B9 | 向后切换算法 |
| KEY4 | C7 | 向前切换算法 |

算法循环顺序：

```text
灰度 → 二值化 → Sobel → 灰度
```

### 乒乓开关控制

乒乓开关为高电平有效，上拨为 `1`，下拨为 `0`：

| 开关 | FPGA 引脚 | 功能 |
|---|---|---|
| SW1 | A4 | 保留，暂未使用 |
| SW2 | B4 | 保留，暂未使用 |
| SW3 | E11 | 保留，暂未使用 |
| SW4 | D11 | 上拨强制显示原图 |

SW4 下拨后恢复按键选择的算法模式。

## 摄像头参数

当前摄像头自动曝光模块的参数固定为：

- 曝光值：`1900`
- 增益值：`89`

摄像头按键输入在顶层固定为未按下状态，板载按键专用于图像模式切换。

## 开发环境

- 安路 Tang Dynasty
- FPGA 器件：`PH1P35MDG324`
- 工程版本信息以 `td_project/camera_to_dsi_display.al` 为准

## 编译流程

1. 使用 Tang Dynasty 打开 `td_project/camera_to_dsi_display.al`。
2. 确认工程顶层为 `design_top_wrapper`。
3. 检查 `user_source/constraints_source/pin.adc` 引脚约束。
4. 执行综合。
5. 执行布局布线和时序分析。
6. 生成 bit 文件并下载到开发板。

本工程的综合、布局布线和下载验证由项目使用者执行。

## 版本管理

根目录 `.gitignore` 排除了以下资料文件：

```text
安路二方案（基础）.md
新HX1P35A开发板手册-HDL版2604.pdf
```
