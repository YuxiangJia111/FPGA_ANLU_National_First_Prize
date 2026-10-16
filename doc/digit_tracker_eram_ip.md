# 数字跟踪器 ERAM 接入说明（当前版本）

更新时间：2026-10-15。阶段三已通过用户上板测试；ERAM 资源优化版本仍需重新综合、布局布线和上板验证。

## 1. 当前模块名称与连接

用户最新生成的真实 IP 为：

```text
digit_tracker_state_ram_adapter
```

目录为：

```text
td_project/al_ip/digit_tracker_state_ram_adapter/
```

保留该 IP 名称和生成文件，无需再次改名或生成。现在 `digit_motion_tracker.v` 在 `g_state_eram` 内直接实例化该 IP，使用它的原生端口：

```verilog
digit_tracker_state_ram_adapter u_state_ram (
    .dia   (ram_write_data),
    .addra (ram_write_addr),
    .wea   (ram_write_en),
    .clka  (I_clk),
    .dob   (ram_read_data),
    .addrb (ram_read_addr)
);
```

已移除同名的自有适配器模块及源文件。生成 IP 不含 USE_ERAM_IP 参数，也不含 I_clk/I_write_data 等自定义端口，因此不能用以前的适配器实例写法调用它。

`USE_ERAM_IP` 仍是跟踪器自身的参数，顶层保持 1。值为 0 时仅选用跟踪器内部的行为 RAM，供仿真回归使用。

## 2. 已生成 IP 的参数核对

已检查最新封装 `digit_tracker_state_ram_adapter.v` 及其依赖 `RTL/ram_123e56a8af8e.v`，配置如下：

| 项目 | 配置 |
| --- | --- |
| 模块名 | digit_tracker_state_ram_adapter |
| 类型 | Simple Dual Port RAM，写 A、读 B |
| 存储实现 | EMB20K / ERAM |
| A/B 数据位宽 | 16 bit |
| A/B 深度 | 256 words |
| A/B 地址位宽 | 8 bit |
| 时钟 | 公共时钟，SYNC，仅引出 clka |
| A 端使能 | Always Enable，并引出 wea 控制写入 |
| B 端使能 | Always Enable |
| 输出寄存器 | None / NOREG |
| 初始化、Byte Enable、ECC | 不启用 |

NOREG 仅关闭额外输出寄存器；RAM 仍为同步读、一拍延迟。当前 FSM 已按这一延迟安排请求和取数。

应有端口：`dia[15:0]、addra[7:0]、wea、clka、dob[15:0]、addrb[7:0]`。

## 3. 工程清单与操作

当前 `.al` 保留真实 IP 的 XML 引用：

```text
al_ip/digit_tracker_state_ram_adapter/digit_tracker_state_ram_adapter.xml
```

生成 IP 的封装及 RTL 由该 IP 引用管理，不需要再添加自有适配器。已清除旧的以下自有源码引用：

```text
../user_source/hdl_source/digit_tracker_state_ram.v
../user_source/hdl_source/digit_tracker_state_ram_adapter.v
```

请重新加载 `td_project/camera_to_dsi_display.al` 后综合，确保工具读取磁盘上的最新源码和清单。

不要将 `sim/digit_tracker_state_ram_ip_sim.v` 或 `sim/reference/` 的旧跟踪器加入综合。前者仅在真实 IP 缺失时作为仿真备用绑定，模块名随当前真实 IP 保持一致。

## 4. 资源优化结构

历史跟踪、当前检测、下帧显示三组记录进入一个 16×256 ERAM 实例。中心/尺寸运算和绝对差运算采用串行共享，避免原来的多组坐标数组和宽多路选择。

| 字地址 | 内容 |
| --- | --- |
| 0x00～0x3F | 8 个历史目标，每个 8 字 |
| 0x40～0x7F | 8 个当前检测记录，每个 8 字 |
| 0x80～0xBF | 8 个待显示记录，每个 8 字 |
| 0xC0～0xFF | 阶段四/五运动历史，每个 ID 使用前 6 字，后 2 字保留 |

目标/检测记录字段为 xmin、xmax、ymin、ymax、cx、cy、width、height，分别占 16-bit 字的低 12 bit。显示记录前 6 字低 12 bit 相同，最后两字为中心 X、Y 的四位 BCD。阶段四在显示记录的中心 X 字高 4 bit 携带箭头有效位及方向，原始中心不变。方向历史格式及操作见 `digit_motion_stage4.md`，无需重新生成 IP。

仍保留单周期输入快照、并行显示输出、有效位、漏检计数和少量运算寄存器。不能在重新综合前承诺具体 Slice 降幅。目标是用一个小容量 ERAM IP 实例消除主要坐标数组及重复暂存，实际映射块数和面积以工具报告为准。

留存旧 gate.area 中 2741 是 seq 列，另有 logic LUT、ripple、f7mux 等资源，不能将其直接当作最终布局后的 Slice 数。

## 5. 消隐与帧边界

跟踪器 I_vblank 连接 processed_video_vsync，高有效。项目 720p 的 VSYNC 窗口为 5×1650=8250 个像素时钟。显示记录读出约需 130 个时钟，数据只在消隐期间逐字加载，下一帧起点更新有效掩码和目标数量。

有效画面期间坐标保持稳定；消隐期间接口数据允许变化。短消隐不足以完成预载时，隐藏未完成结果并等待下个完整窗口，不提交半组坐标。后续更改视频时序或极性时需要维持这一约束。

现有顶层每帧起点后一拍发布检测结果，跟踪器可在帧起点提交上一结果后接收新结果。忙时不接收额外检测更新。

## 6. 仿真与上板

运行：

```powershell
& 'D:\Anlogic\osd_SC500_720P\sim\run_digit_tracking.ps1'
```

脚本已指向当前真实 IP 目录；日志开头应显示 `Tracker tests use the user-generated TD IP.`，并编译 `ram_123e56a8af8e.v`。

测试包含：行为 RAM 与真实 IP 的跟踪回归、两种模式各 120 帧对旧版可见结果及状态对照、短消隐拒绝与重试、真实 VTC 连续帧发布，以及阶段三帧差、缓存复用和 CNN 读口回归。阶段四增加方向与箭头显示测试，当前共 15 次运行。

此前对照测试观察到最长计算耗时 3987 个时钟，这只是测试观察值，未作为形式证明的最坏上界。

综合时重点比较 `u_digit_motion_tracker/g_state_eram/u_state_ram` 的 ERAM 映射，以及跟踪器与整机 LUT、seq、f7mux、Slice 和 ERAM 数量。随后检查布局布线时序，并上板验证单/多牌 ID、漏检恢复、模式重入、坐标稳定、黄色帧差提示和原 CNN/PREVIEW。

助手未执行综合、布局布线或下载，最终资源与硬件效果需由用户确认。

阶段五使用历史字偏移 5 的低 4 bit 保存框内活动保持计数。偏移 4 的 bit[3] 为坐标运动候选；待显示区域中心 X 字的 bit[15] 为帧差与位移联合确认状态，同时控制蓝框和箭头。详见 `digit_motion_stage5.md`。
