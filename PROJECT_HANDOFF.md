# ANLU SC500 720p 工程交接文档

更新时间：2026-10-15

## 1. 工程定位

本工程是基于安路 `PH1P35MDG324` FPGA 和 HX1P35A 开发板的 SC500 摄像头视频处理工程，当前工作基线为队友提交：

```text
da56e2d feat: optimize full video pipeline and remove dataset capture
```

当前本地分支：

```text
teammate-pipeline-da56e2d
```

工程顶层：

```text
design_top_wrapper
```

Tang Dynasty 工程文件：

```text
td_project/camera_to_dsi_display.al
```

目标视频格式：

- SC500，2-lane MIPI CSI-2
- RAW10
- Bayer `BGGR`
- 1280 × 720
- HDMI 720p
- FPGA 器件 `PH1P35MDG324`

## 2. 目录结构

### `td_project/`

Tang Dynasty 工程、工程源文件清单、约束、IP 引用和综合/布局布线运行目录。

重要文件：

- `camera_to_dsi_display.al`：工程主配置、顶层、HDL 文件清单、ADC/SDC 文件引用。
- `camera_to_dsi_display.sdc`：时钟、异步时钟组、CNN/LCD mailbox 时序约束。
- `camera_to_dsi_display_Runs/`：工具生成的综合、布局布线、数据库、报告和 bit 文件。

运行目录中的 `.db`、`.bit`、`.log`、`.lock`、`.prj` 等是工具生成物，可能是旧结果或机器相关文件，不能代替当前 HDL 源码作为修改依据。

### `user_source/hdl_source/`

工程 Verilog/SystemVerilog 源码。

主要功能分组：

- 顶层和视频系统：`design_top_wrapper.v`、`SC500CS_top.v`、`display_top.v`、`hdmi_mixer.v`。
- 摄像头和 ISP：`isp/`、`ISP_preprocess_top.v`、`awb.v`、`signal_delay.v`。
- DDR：`DDR_top.v`、`video_in.v`、`video_out.v`、`ph1p35_ddr/`。
- 图像处理：`rgb.v`、`sobel.v`、`auto_exposure.v`、`histogram_equalization.v`、`y_lut.v`、`ycbcr2rgb.v`、`img_processing.v`。
- CNN 和多目标识别：`cnn/`、`digit_multi_bbox.v`、`bbox_gray_downsampler.v`、`bbox_cnn_adapter.v`。
- 状态显示和 LCD：`lcd_hw_test.v`、`lcd_mode_display.v`、`lcd_status_bridge.v`、`latency_monitor.v`。
- 通用显示资源：`osd_char_lib.v`、`anlogic_logo_rom.v`、`key_remove_shakes.v`、`seg7_scan8.v`。

### `user_source/hdl_source/isp/`

摄像头输入到 DDR 写入前的 ISP 链路，包括：

- RAW10 解包。
- Bayer demosaic。
- `128 bit -> 96 bit` 像素打包。
- AWB。
- `96 bit -> 128 bit` 像素打包。

### `user_source/ip_source/`

安路 IP 和生成文件，包括 PLL、异步 FIFO、BRAM、MCU 等。不要手工修改 IP 生成 RTL；应通过 Tang Dynasty 工具重新生成。

### `user_source/constraints_source/`

- `pin.adc`：顶层板级引脚约束，包括摄像头、按键、拨码、数码管、HDMI、DDR 和 LCD。
- `timing.sdc`：目前基本为空；主工程使用 `td_project/camera_to_dsi_display.sdc`。

### `sim/`

测试台文件。当前包含 LCD 状态桥和 LCD SPI 显示相关测试台。由于当前机器上的 ModelSim `vsim` 会报 `FileWatch(fileName)` 启动错误，测试台可能只能完成 `vlog` 编译，不能据此宣称行为仿真通过。

### `doc/`

说明和交接资料。

- `route_failure_notes.md`：此前综合/布局布线失败和视频截断问题记录。

## 3. 顶层数据链路

```text
SC500
  -> MIPI DPHY/CSI-2
  -> RAW10 解包
  -> demosaic
  -> AWB
  -> DDR 四帧缓存
  -> HDMI 像素域读出
  -> RGB/YUV 图像处理
  -> 多目标检测和 CNN
  -> HDMI OSD / SPI LCD 状态显示
  -> HDMI TX
```

顶层主要连接位于 `design_top_wrapper.v`：

1. `SC500CS_top` 输出摄像头 AXI4-Stream。
2. `ISP_preprocess_top` 调用 `isp_top`。
3. `DDR_top` 管理写入、读出和四帧缓存。
4. `img_processing` 选择图像增强/分析模式。
5. `digit_multi_bbox` 定位多个数字目标。
6. `bbox_gray_downsampler` 对目标区域生成 28×28 输入。
7. `bbox_cnn_adapter` 跨 HDMI 像素时钟和 CNN 时钟传输输入，并接收结果。
8. `TOP` 是 CNN 推理核心。
9. `display_top` 和 `hdmi_mixer` 生成 HDMI 图像及 OSD。
10. `lcd_mode_display` 通过独立 SPI GPIO 显示模式和延迟状态。

## 4. 主要模块说明

### `design_top_wrapper.v`

整个工程的顶层连接模块。

负责：

- 顶层端口和板级 GPIO。
- PLL 时钟连接。
- 摄像头、ISP、DDR、图像处理、CNN、HDMI 的连接。
- LCD 五线 SPI 输出。
- `latency_monitor` 事件接入。
- LCD 状态延迟桥接。

当前 LCD 顶层输出：

```text
O_lcd_scl
O_lcd_sda
O_lcd_rst
O_lcd_dc
O_lcd_cs
```

### `isp_top.v` / `ISP_preprocess_top.v`

ISP 前端。当前 AWB 不再使用实时除法器，而是固定增益乘法和饱和处理，保留原有 96/128 位像素打包链路。

### `awb.v`

AWB 当前版本是资源优化重点：

- 删除了原来的逐有效周期除法器。
- 保留四像素 RGB 增益乘法。
- 保留 RGB 饱和截断。
- 保留原始 96 位像素数据格式和流水线接口。

这是当前已确认资源可接受的版本，建议冻结，不要重新引入实时除法。

### `DDR_top.v`、`video_in.v`、`video_out.v`

四帧 DDR 缓存及读写仲裁。

功能包括：

- 摄像头域 FIFO 写入。
- DDR 写突发。
- HDMI 域 DDR 读出。
- 帧缓冲轮换。
- 帧龄诊断 `O_latency_frames`。

**冻结边界：** 这三个模块是画面稳定性的核心。LCD 和延迟显示不得改变 DDR 地址、FIFO 复位、FIFO 读写使能、帧指针或 DDR 仲裁。当前延迟监控已改为独立 `latency_monitor`，后续不要把时间戳重新写回 DDR 数据路径。

### `img_processing.v`

图像处理链：

```text
RGB -> RGB2YCbCr -> Sobel -> histogram_equalization -> auto_exposure
```

输出根据 `I_mode` 选择：

- 原图。
- 灰度。
- 二值化。
- Sobel。
- 数字自动曝光。
- 直方图均衡化。
- 预览模式由后级 CNN/OSD 使用。

### `control_top.v`

按键和拨码控制：

- KEY1：目标检测亮度阈值 `35/45/55/65/75`。
- KEY2：目标连接间隔 `1..4`。
- KEY3：算法模式后退。
- KEY4：算法模式前进。
- SW4：强制原图。
- SW1..SW3：目标预览编号。

模式编码：

```text
000 ORIGINAL
001 GRAY
010 BINARY
011 SOBEL
100 AUTO_EXP
101 EQUALIZE
110 DOWNSAMPLE/PREVIEW
```

### `digit_multi_bbox.v`

对处理后的亮度图进行多目标数字区域检测，输出最多 8 个框的坐标和有效标志，并把灰度帧写入供后续裁剪使用的 RAM。

### `bbox_gray_downsampler.v`

按目标框提取方形区域并生成 28×28 灰度输入。当前版本使用生成的 RAM IP，包含裁剪、排序和采样控制。

### `bbox_cnn_adapter.v`

负责 HDMI 像素时钟域和 CNN 时钟域之间的 mailbox 握手：

- 接收 784 个裁剪像素。
- 写入 CNN database。
- 控制 `GO`。
- 检测 `STOP`。
- 接收 4 bit 识别结果。
- 跨域返回结果。
- 提供 CNN 延迟测量的开始/完成事件。

### `cnn/TOP.v`

CNN 推理核心。输入固定 28×28，结果为 4 bit 数字。核心推理周期基本稳定；如果需要观察调度和 mailbox 波动，应使用 `latency_monitor` 的完整事件统计，而不是只统计 `GO -> STOP`。

### `display_top.v` / `hdmi_mixer.v`

负责 HDMI 时序、视频像素对齐和 OSD：

- Logo。
- 算法状态和帧计数。
- 多目标框。
- CNN 数字标签。
- 28×28 预览。
- 右上角 CAM/CNN 延迟 HUD。

`hdmi_mixer.v` 是组合逻辑和时序压力较大的模块。任何修改都应优先避免在逐像素路径中加入除法、大规模乘法或新的多层数组选择器。

### `latency_monitor.v`

独立延迟统计模块，不参与 DDR 数据通路：

- 50 MHz `I_sys_clk` 生成微秒计数器。
- 摄像头帧起始通过 Gray 码和 toggle 跨域。
- HDMI 首个有效帧事件产生 CAM 延迟。
- CNN 开始/完成事件产生 CNN 延迟。

当前 CAM 值是最新摄像头帧起点与 HDMI monitor 帧起点之间的近似观测值，不是同一匹配帧的严格端到端延迟。显示单位为微秒，再由 OSD 转换为毫秒。

### `lcd_hw_test.v`

名称虽然带 `test`，但不是测试台；它是 LCD 的实际硬件初始化和清屏控制器，必须参与综合。

负责：

- LCD 复位。
- ST7789 类初始化命令。
- 设置窗口。
- RGB565 整屏填充。

不要删除。`lcd_mode_display.v` 实例化了它。

### `lcd_mode_display.v`

LCD SPI 状态页面渲染器：

- 显示七种算法模式。
- 显示整数毫秒延迟。
- 通过 `lcd_status_bridge` 接收 HDMI 域延迟状态。
- 使用 SPI 发送文字像素。
- 当前已修正窗口、`RAMWR`、RGB565 高低字节顺序和像素状态机。

由于 LCD SPI 刷新速度低，模式/延迟只应在状态变化时刷新；不要改成连续整屏刷新。

### `lcd_status_bridge.v`

将 HDMI 域的 CAM 延迟状态通过稳定数据加 toggle/ack 跨到 50 MHz 系统时钟域，并使用串行除法转换成毫秒。有效位和数值保持到下一次状态更新。

### LCD 引脚

`user_source/constraints_source/pin.adc` 中的当前 LCD 约束：

```text
O_lcd_scl -> P9
O_lcd_sda -> R7
O_lcd_rst -> R6
O_lcd_dc  -> T5
O_lcd_cs  -> U7
```

请按已验证物理接线连接 LCD，不要依据板卡丝印或不同版本手册推断 GPIO 名称。

## 5. 当前已有功能

- SC500 MIPI 摄像头采集。
- RAW10 解包和 BGGR demosaic。
- 固定增益、资源优化后的 AWB。
- DDR 四帧缓存。
- HDMI 720p 输出。
- 原图、灰度、二值、Sobel、数字自动曝光、直方图均衡化和预览模式。
- 多目标数字区域检测，最多 8 个目标。
- 28×28 目标裁剪和 CNN 数字推理。
- HDMI 目标框、数字标签和预览图显示。
- HDMI 右上角 CAM/CNN 延迟显示。
- SPI LCD 显示模式和延迟状态。
- 按键/拨码切换算法和目标预览。

## 6. 建议冻结模块

以下模块建议作为后续开发的冻结边界，除非发现明确的功能错误或上板故障：

1. `DDR_top.v`
2. `video_in.v`
3. `video_out.v`
4. `ISP_preprocess_top.v`
5. `isp_top.v`
6. `awb.v`
7. `ph1p35_ddr/` 下的 DDR IP 和生成 RTL
8. `user_source/ip_source/` 下的 PLL/FIFO/BRAM IP
9. `SC500CS_top.v` 中的 MIPI/摄像头配置链路
10. `cnn/TOP.v` 及其 CNN 基础算子

原因：这些模块已经经过较多板级调试，改动容易重新引入右侧/左侧截断、像素错位、反色或布线失败。

可修改但需要谨慎：

- `hdmi_mixer.v`：只做局部 OSD 或低复杂度优化。
- `display_top.v`：只增加旁路显示接口，不改变视频读数时序。
- `latency_monitor.v`：只修改测量定义，不接入 DDR 数据控制。
- `lcd_mode_display.v`：只修改 LCD 独立刷新逻辑，不影响视频时钟域。

## 7. 当前已知问题和限制

### LCD

最近上板曾出现 LCD 闪烁和整体时序恶化。已修正的高风险协议问题包括：

- 窗口结束地址。
- `RAMWR` 命令。
- RGB565 高低字节顺序。
- 首像素发送状态。
- 逐像素除法/取模路径。
- 延迟刷新节流。

目前只完成 RTL 编译检查，尚未完成新的综合、布线和上板确认。下一步应重点观察 LCD 是否仍闪烁，以及主视频时序是否恢复。

### 延迟

延迟显示是诊断/展示功能，不应被当作精确仪器测量。物理显示器的内部缓存、扫描和面板响应时间未包含在 FPGA 统计内。

### 仿真

ModelSim `vlog` 编译可用于语法和模块连接检查。当前环境中的 `vsim` 曾报：

```text
Error: can't read "FileWatch(fileName)": no such element in array
```

因此不能仅依据已有测试台文件声称行为仿真通过。用户已明确后续 LCD 主要通过上板验证。

### 综合/布线

助手不执行综合、布局布线或下载。由用户在 Tang Dynasty 中完成，并检查：

- 资源占用。
- 关键路径。
- SWNS/HWNS。
- LCD 新增逻辑是否恶化 HDMI/DDR 时序。

## 8. ModelSim RTL 编译方法

Windows PowerShell 示例：

```powershell
& "D:\ModelSim\modelsim_ase\win32aloem\vlog.exe" `
  -work "C:\Temp\lab_ex3_isp_work" `
  "user_source\hdl_source\lcd_hw_test.v" `
  "user_source\hdl_source\lcd_mode_display.v" `
  "user_source\hdl_source\lcd_status_bridge.v" `
  "user_source\hdl_source\latency_monitor.v" `
  "user_source\hdl_source\design_top_wrapper.v"
```

检查：

```text
Errors: 0, Warnings: 0
```

这只代表列出的 RTL 编译通过，不代表综合、布线或硬件显示正常。

## 9. 后续工作建议

1. 先在 Tang Dynasty 重新加载 `camera_to_dsi_display.al`，确认 `lcd_hw_test.v` 已加入源文件列表。
2. 确认 `pin.adc` 只加载一次，不要重复手动添加。
3. 重新综合但暂不立即布线，先查看 LCD 逻辑是否被推导为合理规模。
4. 检查关键路径是否落在 `hdmi_mixer`、LCD 状态桥或新增 LCD 渲染逻辑。
5. 通过布线后 bit 上板，先确认主视频无截断/反色，再确认 LCD 初始化、模式和延迟显示。
6. 任何后续优化先在 LCD 独立模块或 OSD 层完成，不要修改 DDR/ISP 主路径。

## 10. Git 注意事项

当前工作区包含大量工具生成物修改和未跟踪日志。提交时只应选择源码、约束、工程清单和必要文档；不要把综合数据库、bitstream、锁文件、运行日志作为源码提交。

当前 LCD、延迟监控和交接文档相关改动尚未自动提交或推送。下一位协作者开始工作前，应先执行：

```powershell
git status --short --branch
git diff --stat
```


## 11. 运动检测开发进展（2026-10-15）

- 阶段 1、2 已完成 TRACK(111) 模式、多目标 ID 跟踪和中心坐标显示，用户初步上板反馈效果可接受。详见 `doc/digit_tracking_stage12.md`。
- 阶段三已完成独立硬件帧差及黄色运动块提示，尚待用户综合、布局布线和上板验证。详见 `doc/motion_detection_stage3.md`。
- 帧差复用已有 4 bit 灰度 RAM，在采集 bank 写入前读取其历史同地址内容，不新增整帧 BRAM。它是同 bank 历史图像的间隔帧差，不能宣称严格相邻帧差；范围沿用 ROI X=198..1022、Y=18..702。
- `digit_multi_bbox.v` 新增局部预读地址选择和数据旁路，原写入、bank 调度及检测状态机未改动。CNN 忙时保留其 bank 的读取，冲突时放弃帧差参考。未修改 DDR、ISP、摄像头或 CNN 核心。
- 新模块：`frame_diff_motion.v`、`motion_block_osd.v`；均已加入工程清单。TRACK 面板新增 DIFF:WAIT/READY/LIGHT。尚无方向箭头，尚未将帧差与跟踪状态联合判断。
- 当前 `sim/run_digit_tracking.ps1` 执行七次行为仿真，均已通过，编译与各仿真 Errors: 0, Warnings: 0；包括真实安路灰度 RAM IP 模型与行为 RAM 模型的先读后写/CNN 读口回归。
- 本机 `vsim -batch` 可以运行这些行为测试；交互式 `-c` 仍可能出现前文 FileWatch 错误。真实 RAM 模型需安路 PH1P_LOGIC_ERAM 及 PH1P_PHY_GSR，脚本已接入，不要将仿真厂商模型加入综合工程。


## 12. 跟踪器 ERAM 优化（2026-10-15）

- 用户已逐项测试并确认阶段三效果达标。最新修改是针对 u_digit_motion_tracker 的 ERAM 资源优化，尚待生成 IP、综合和上板验证。
- 跟踪器改为串行共享运算 + 16 bit × 256 简单双口同步 RAM，历史/检测/待显示记录都进入 RAM。新增自有适配模块 `digit_tracker_state_ram.v`，已加入工程清单；顶层明确 USE_ERAM_IP=1。
- 用户需要在 Tang Dynasty 手动创建 `digit_tracker_state_ram_ip`，16 bit × 256、地址 8 bit、Common Clock、NOREG，无 CE/OCE/Byte Enable/ECC/初始化文件。完整指南：`doc/digit_tracker_eram_ip.md`。真实生成 IP 当前尚不存在，不能直接宣称可综合或资源降幅已确认。
- 为省掉整组 pending 输出寄存器，新增 I_vblank，连接 processed_video_vsync；显示数据在垂直消隐内预读，下一 active frame 起点发布 valid/count。有效视频期间输出保持稳定，接口数据在消隐内允许变化。
- 11 次行为测试已通过，包含 ERAM 厂商原语、行为 RAM、两种模式各 120 帧对旧实现的可见结果/状态对照、短消隐拒绝与重试、真实 VTC 消隐和连续帧更新，原阶段三回归也通过。最长计算耗时 3987 周期只是该测试观察值。
- `sim/digit_tracker_state_ram_ip_sim.v` 是仅仿真的厂商原语绑定，`sim/reference/` 是旧实现参考，禁止加入综合。用户生成约定路径下的真实 IP 后，`sim/run_digit_tracking.ps1` 自动改用真实 IP 封装/RTL，再运行全部测试。


## 13. 真实跟踪 RAM IP 接入修复（2026-10-15）

用户实际生成的 IP 名为 `digit_tracker_state_ram`，配置为 16×256、NOREG、公共时钟，参数正确。该名字与早期自有适配器冲突，且工程清单缺失适配器条目，导致报参数和端口不存在。现已将自有模块和文件统一改名 `digit_tracker_state_ram_adapter`，内部实例化真实 IP `digit_tracker_state_ram`，并补入 `.al`。无需重建 IP。回归脚本已指向真实生成目录；仿真备用绑定仅在真实 IP 缺失时使用。最新名称和说明以 `doc/digit_tracker_eram_ip.md` 为准。


## 14. 再生成 IP 后的最终接入方式（2026-10-15）

当前真实 IP 名称为 `digit_tracker_state_ram_adapter`，目录为 `td_project/al_ip/digit_tracker_state_ram_adapter`，内部依赖 `ram_123e56a8af8e`，16×256/NOREG 配置正确。保留该生成 IP，不再改名。跟踪器现在直接在 `g_state_eram` 中按 dia/addra/wea/clka/dob/addrb 原生端口实例化 IP；已移除自有同名适配器和工程清单的旧自有适配器条目，避免重复命名。行为 RAM 模型移入跟踪器自身的 USE_ERAM_IP=0 分支。回归脚本已指向最新 IP。最新接入说明以 `doc/digit_tracker_eram_ip.md` 为准，前面各历史段落中的模块命名不再作为当前配置。


## 15. 阶段四：八方向箭头（2026-10-15）

- 用户已确认 ERAM 优化版本效果很好。现已完成阶段四坐标位移箭头，尚待用户重新综合、布局布线和上板。详见 `doc/digit_motion_stage4.md`。
- `digit_motion_tracker.v` 在既有 ERAM 的 0xC0..0xFF 保存每 ID 的平滑中心、参考中心和方向/窗口状态，未增加 ERAM 实例，无需重新生成现有 `digit_tracker_state_ram_adapter` IP。
- 默认 HISTORY_INTERVAL=4、START_DISTANCE=8、STOP_DISTANCE=3、STOP_CONFIRM=2；平滑、位移与停止时间均按有效目标更新次数。新 ID、漏检后恢复和模式重入重新建立参考。显示原始坐标保持不变。
- 新增 `digit_motion_arrow_osd.v`，已加入 `.al`。固定 32x32 橙色八方向箭头，框右侧优先、右边缘改左侧、垂直裁切并避开右上延迟 HUD。8 个目标共享图形计算器，两级流水对齐，重叠时低 ID 窗口优先。
- 显示记录中心 X 字高四位为箭头有效位及方向，低 12 位仍为原始中心。有效帧中保持稳定，消隐期间随框与坐标预载。
- 阶段三黄色帧差与箭头独立工作，尚未实现阶段五联合确认，也未因运动改变绿色跟踪框颜色。
- 当前回归脚本共 15 次行为运行，均通过且 Errors: 0, Warnings: 0，包括两种 RAM 模式方向测试、旧版对照、真实 VTC、箭头字形、实际 HDMI mixer 颜色/图层对齐及原阶段三缓存测试。对照测试观察最长计算耗时 4149 周期。未执行综合、布局布线或下载。


## 16. 阶段五：联合确认与蓝框（2026-10-16）

- 用户确认阶段四上板效果可接受。本次完成第五阶段，移动数字框按用户要求采用蓝色（0000FF），静止绿色，箭头仍为橙色。详见 `doc/digit_motion_stage5.md`。
- 顶层开启 `REQUIRE_FRAME_DIFF=1`。原坐标位移候选与同次检测框内的有效帧差活动共同确认移动，蓝框与箭头共用掩码。框内活动按 270 块串行扫描，使用既有 ERAM 历史偏移 5 保存 4 次有效更新保持计数。
- `frame_diff_motion` 暴露本次采集完成事件及元数据；检测器将它与接受分析的采集绑定，经分析/待发布/帧边界随框传递；跟踪器再作整批快照。避免直接拿最新黄色块匹配旧检测框，CNN bank 占用和参考无效时不形成错误证据。
- 当前对应采集参考无效、全局光照变化、目标丢失或模式退出会撤销/隐藏确认。重新获得目标需重建坐标运动参考。黄色轮廓和面板仍展示最新独立帧差，可能比框对应的证据更新。
- 不新增整帧缓存、不新增或重建 IP。跨模块对齐新增 4×270 bit 元数据暂存及少量控制；扫描器为单目标共享，8 个目标最多增加 2160 扫描周期。实际资源和时序尚待用户综合、布线核验。
- 回归扩展为 17 次行为运行，真实 ERAM 与行为 RAM 均覆盖联合判断、单路证据抑制、活动保持、全局/无效拒绝、8 个 ID 输入置换、输入快照和 ROI 尾块；实际 mixer 检查蓝框/绿框/橙色箭头/旧模式红框，真实 VTC 开启联合路径。完整回归 Errors: 0、Warnings: 0。未执行综合、布局布线或下载。
- 块级活动可能包含框旁同块手部；框抖动或误匹配仍可能导致假确认，不是精确像素掩码或外观重识别。帧差仍是同 bank 历史间隔帧差。


## 17. 第五阶段后原图割裂排查（2026-10-16）

- 用户反馈第五阶段 bit 中原始视频也横向割裂，且 GRAY、TRACK、强制原图等所有模式均存在。
- 检查用户最新 19:07:59 布线报告：HDMI 75 MHz 同域最差 setup slack -0.251 ns，4 个负 slack 在 Logo ROM 地址口；另有中央文字译码到最终 RGB 路径 -0.036 ns / 13 级逻辑。全工程 SWNS=-0.634 ns、HWNS=-0.595 ns，仍有其他跨域相关违例。时序未收敛是已确认问题，但尚不能证明就是撕裂唯一根因。
- 本次只改 `hdmi_mixer.v`：框命中/颜色和中央文字命中提前一级计算并寄存，Logo 行偏移提前一级计算，减少最终 RGB 级组合逻辑。原输出 RGB/DE/HS/VS 延迟保持不变，蓝框联合判断保留，未改 DDR/FIFO/ISP/摄像头或 SDC/IP。
- 新增全帧变化像素回归 `hdmi_mixer_pixel_stream_tb.sv` 和仅仿真的 `sim/reference/hdmi_mixer_pre_counter_pipeline.v`。前者检查行首行尾、真实 Logo、八框红绿蓝与逐像素文字参考；后者禁止加入综合。
- `sim/run_digit_tracking.ps1` 扩展为 18 次行为运行，全部通过，Errors: 0、Warnings: 0；新增测试独立检查 2,174,912 个背景/边框像素及 76,800 个 Logo 像素。新实现必须重新综合、布线并上板验证，不能将行为等价或旧时序报告当作硬件修复证明。详见 `doc/video_tearing_stage5.md`。


## 18. 用户验收与 main 发布（2026-10-16）

用户对显示流水调整后的版本反馈“效果不错，这一版符合预期”，并要求推送至对应仓库 main。发布内容包含运动检测/跟踪、蓝框与箭头、ERAM IP、显示流水修正及所需 LCD 源码/约束，附回归脚本与交接文档。18 次行为回归已通过；用户上板验收不代表全部 STA 违例均已收敛，后续构建仍须检查新的时序报告。发布不包含本地实现数据库、bit 文件、锁文件、仿真日志及独立 CNN_example 参考目录。
