# -*- coding: utf-8 -*-
# gen_report.py —— 生成实验三报告（技术章节；"问题复盘与心得"按要求留空由本人撰写）
import os
from docx import Document
from docx.shared import Pt, Cm, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, '实验三_实验报告.docx')

doc = Document()

# 页面/默认字体
style = doc.styles['Normal']
style.font.name = 'Times New Roman'
style.font.size = Pt(10.5)
style.element.rPr.rFonts.set(qn('w:eastAsia'), '宋体')


def h(text, level=1):
    p = doc.add_heading(text, level=level)
    for r in p.runs:
        r.font.name = 'Times New Roman'
        r._element.rPr.rFonts.set(qn('w:eastAsia'), '黑体')
    return p


def para(text, bold=False):
    p = doc.add_paragraph()
    r = p.add_run(text)
    r.bold = bold
    r.font.name = 'Times New Roman'
    r._element.rPr.rFonts.set(qn('w:eastAsia'), '宋体')
    return p


def bullet(text):
    p = doc.add_paragraph(text, style='List Bullet')
    for r in p.runs:
        r.font.name = 'Times New Roman'
        r._element.rPr.rFonts.set(qn('w:eastAsia'), '宋体')
    return p


def table(headers, rows):
    t = doc.add_table(rows=1, cols=len(headers))
    t.style = 'Table Grid'
    for i, hd in enumerate(headers):
        cell = t.rows[0].cells[i]
        cell.text = ''
        r = cell.paragraphs[0].add_run(hd)
        r.bold = True
        r.font.name = 'Times New Roman'
        r._element.rPr.rFonts.set(qn('w:eastAsia'), '宋体')
    for row in rows:
        cells = t.add_row().cells
        for i, v in enumerate(row):
            cells[i].text = ''
            r = cells[i].paragraphs[0].add_run(str(v))
            r.font.name = 'Times New Roman'
            r._element.rPr.rFonts.set(qn('w:eastAsia'), '宋体')
    return t


# ===== 标题 =====
title = doc.add_heading('实验三　AI+Agent 从零设计：手写数字识别 FPGA 系统', level=0)
for r in title.runs:
    r.font.name = 'Times New Roman'
    r._element.rPr.rFonts.set(qn('w:eastAsia'), '黑体')
para('实验报告（AI 为主角，如实记录过程）')

# ===== 1 实验概述 =====
h('1　实验概述', 1)
para('本实验不提供参考代码，由 AI 编码助手（Agent）在本人指挥下从零完成：'
     'MNIST 手写数字识别模型的训练与 int8 定点量化、Vivado HLS 推理核、'
     'Vivado 集成（UART 解帧 + 推理核 + 数码管/LED）、上板闭环与识别时间统计。')
para('硬件平台：达芬奇开发板（xc7a35tfgg484-2，50MHz），板载 CH340 USB 转串口、'
     '6 位共阳极数码管、LED[3:0]。工具链：Vivado / Vivado HLS 2018.3。')
para('本人承担三个角色：信息官（把开发板/引脚/版本/验收标准完整喂给 AI）、'
     '指挥官（分解任务、审核方案、决定反馈）、验收员（按检查点逐项用数据检验）。')

# ===== 2 系统方案与决策 =====
h('2　系统方案与决策论证', 1)
para('数据链路：上位机画板（28×28 黑底白字）→ 串口发帧 → FPGA 解帧 → HLS 定点推理 → '
     '数码管（最右位）+ LED[3:0] 显示 → 回传结果 → 上位机计时。')

h('2.1　帧协议', 2)
para('自定义帧：帧头 0xA5 0x5A（2B）| 长度 0x0310=784（2B）| 序号（1B）| 图像 784B | '
     'CRC16-CCITT（2B），共 791B。')
bullet('帧头用于重同步；长度字段校验帧完整性；序号用于上位机丢帧检测；'
       'CRC16 覆盖 [长度..图像]，错包直接丢弃并回 IDLE 重找帧头。')
bullet('回传 1 字节类别（0..9）；错帧不回或回 0xEE 后继续等待。')

h('2.2　预处理（重心居中）', 2)
para('上位机做灰度质心居中：把笔迹质心平移到 28×28 画布中心，再按 MNIST 分布归一化。'
     '理由：MNIST 训练集数字大致居中，现场手写位置随机，不居中会使激活分布偏移、识别率崩，'
     '且验收现场无法补救。该处理放上位机最简单，FPGA 只处理已居中的图。')

h('2.3　网络结构', 2)
table(['层', '输出尺寸', '说明'],
      [['输入', '28×28×1', 'uint8 → 标准化 → 256 项 LUT 映射为 int8'],
       ['Conv1', '26×26×16', '3×3 valid, 16 通道, ReLU'],
       ['MaxPool1', '13×13×16', '2×2'],
       ['Conv2', '11×11×32', '3×3 valid, 32 通道, ReLU'],
       ['MaxPool2', '5×5×32', '2×2'],
       ['Flatten', '800', '5×5×32（oc*25 + oh*5 + ow）'],
       ['FC1', '64', '800→64, ReLU'],
       ['FC2', '10', '64→10（int32 logits）']])
para('MAC 总量约 706,752，参数量 56,714。选择该结构的理由：8/16 窄网在 98.5% 平台化（无 BN、'
     '/255 输入），加宽到 16/32/64 并采用标准归一化后，测试集精度稳定 ≥99%。')

h('2.4　量化方案', 2)
para('权重 int8、激活 int8、累加 int32；每层采用 2 的幂 requant（移位实现，不额外占乘法器）。'
     'requant 规则：acc_out = sat( (acc + 2^(s-1)) >> s )，再 ReLU 并饱和到 [0,127]，'
     '与 HLS C 实现逐位一致。输入用 256 项 LUT 把「标准化后的浮点输入」映射为 int8，'
     'FPGA 侧零成本等价实现。')

h('2.5　资源预算', 2)
table(['项', '预算 / 实测'],
      [['时钟', '50 MHz（20ns）'],
       ['DSP', '预算 ≤60；实测 9'],
       ['BRAM', '实测 53/100'],
       ['LUT / FF', '实测 16% / 5%'],
       ['时序', '综合 15.9ns < 20ns（WNS 为正）']])

# ===== 3 训练与定点化结果 =====
h('3　训练与定点化结果', 1)
h('3.1　浮点训练', 2)
para('网络与上述结构一致；输入按 MNIST 标准归一化 (x/255−0.1307)/0.3081；'
     'Adam（lr 1e-3，weight decay 1e-4）+ 余弦退火，20 epochs，batch 256。')
table(['指标', '数值'],
      [['测试集精度', '99.13%'],
       ['参数量', '56,714'],
       ['训练环境', 'PyTorch 2.15.0 CPU']])

h('3.2　定点与浮点对比', 2)
table(['模型', '测试集精度', '相对浮点损失'],
      [['浮点', '99.13%', '—'],
       ['int8 定点', '99.09%', '0.04%（< 1% 达标线）']])
para('定点量化后精度仅下降 0.04 个百分点，说明 int8 + 每层 2 的幂 requant 的方案对该网络足够。')

h('3.3　定点 C 仿真一致性', 2)
para('Python 定点参考（纯 numpy 循环，与 HLS C 同构）与 HLS csim 对 1000 张测试图逐位对拍：'
     'CSIM_RESULT: 1000/1000 images bit-exact, 0 mismatches。'
     '该一致性保证了「训练/量化阶段看到的精度」与「上板实际精度」一致。')

# ===== 4 HLS 实现 =====
h('4　HLS 实现与综合', 1)
para('推理核在 Vivado HLS 2018.3 中实现（C++03，ap_int/ap_uint），综合得到 RTL 并导出为 IP。')
bullet('调用方式：loader.bat -exec vivado_hls -f <脚本>.tcl（绕开 vivado_hls.bat 的 msys tee 崩溃）。')
bullet('为让 Vivado 综合能通过，把每层的空间循环 (oc,oh,ow) 压平成单层 flat 循环 + 常数除法解索引：'
       'HLS 生成的状态机从 524 状态降到 88 状态，RTL 由 1.16MB 降到 92KB，'
       'Vivado 综合的 Cross Boundary 优化不再崩溃。')
table(['综合结果', '数值'],
      [['DSP48E', '9'],
       ['BRAM_18K', '53 / 100'],
       ['LUT', '16%'],
       ['FF', '5%'],
       ['估算时钟', '15.9 ns（< 20ns 目标）'],
       ['推理延迟', '2.34M 拍 ≈ 46.8 ms @50MHz']])

# ===== 5 识别时间 =====
h('5　识别时间构成分析与优化', 1)
para('识别时间定义为「上位机发出帧到收到结果」的总耗时。它由两部分构成：串口传输与板上推理。')
table(['波特率', '串口传输', '推理', '合计（实测）'],
      [['115200', '791B×10/115200 ≈ 68.7 ms', '≈46.8 ms', '117 ms'],
       ['1 Mbps', '791B×10/1e6 ≈ 7.9 ms', '≈46.8 ms', '57.3 ms']])
para('优化措施：把 UART 波特率从 115200 提升到 1 Mbps（50MHz÷50 精确分频）。'
     '实测 117 ms → 57.3 ms，提升约 2.05 倍，识别正确率不变（49/50）。')
para('瓶颈分析：1 Mbps 后串口仅占约 8 ms，推理的 46.8 ms 成为主要瓶颈。'
     '进一步的优化方向是重构推理核（例如用 8~16 路 MAC 阵列流水），'
     '但这会带来 DSP 面积与速度的取舍——本期采用「资源优先」的串行结构保证能放进 35T，'
     '把提速留作后续工作。')

# ===== 6 上板验证 =====
h('6　上板验证与健壮性', 1)
h('6.1　识别正确率', 2)
para('从 MNIST 测试集抽取 100 张，经 COM6 逐帧发送，FPGA 返回识别结果：'
     '99/100 正确（与定点仿真 99.09% 一致），平均 117 ms/帧；'
     '1 Mbps 版本 49/50 正确，平均 57.3 ms/帧。')
h('6.2　健壮性', 2)
para('对三类异常做了注入测试，要求「不卡死、能重同步」：')
table(['异常', '处理', '结果'],
      [['图像字节翻转（CRC 错）', 'CRC 校验失败 → 丢弃、回 IDLE 重找帧头', '下一帧正常识别'],
       ['300 字节随机乱码', '无帧头 → 丢弃', '下一帧正常识别'],
       ['截断帧（只发 200 字节）', '串口空闲 >2ms 超时 → 强制回 IDLE', '下一帧正常识别']])
para('截断帧最初会导致接收状态机卡在「等剩余图像字节」，把随后的一帧吃掉；'
     '加入串口空闲超时重同步后，三类异常均可自动恢复。')

# ===== 7 复盘与心得 =====
h('7　问题复盘与心得（本人独立撰写）', 1)
para('（此节按要求由本人独立撰写，留空。）', bold=False)
para('')
para('。' * 1)
para('【提示：可从以下角度写——信息给到什么程度 AI 就做到什么程度；'
     '哪些环节 AI 一次通过、哪些必须人工纠偏；'
     '「先方案后代码」「小步闭环」「一次只改一处」在实际中的效果；'
     '对 AI 可靠边界的认识。】')

# ===== 8 AI 使用声明 =====
h('8　AI 使用声明', 1)
para('本实验以 AI 编码助手为主角完成设计与实现。AI 承担了：环境搭建、'
     '模型训练与量化、HLS 推理核、RTL 集成、构建脚本与调试；'
     '本人承担了：信息组织（开发板/引脚/版本/验收标准）、方案审核、'
     '上板接线与现场验证、反馈事实（报错日志/现象）以及本报告的复盘部分。'
     '完整交互记录见附录 A（logs/AI_LOG.md）。')

# ===== 附录 A =====
h('附录 A　AI 交互日志摘要', 1)
para('完整逐轮记录见 lab3_/logs/AI_LOG.md（含 T2~T5 覆盖计数与首次通过率统计）。'
     '关键节点：')
table(['轮次', '目的', '结果'],
      [['1', 'T2 上下文包', '发现指导书写 C:\\Xilinx 路径本机不存在，写入路径真相表'],
       ['2~3', 'T3 环境脚本化', '直连 pypi 超时→清华镜像；venv 沙箱权限问题→完全权限'],
       ['4~5', 'T4 约束迭代', '窄网 98.6% 不达标→加宽+归一化→99.13%'],
       ['6~7', 'T3/T4 定点+csim', '定点 99.09%、csim 1000/1000 逐位一致'],
       ['8', 'T4 综合', 'PIPELINE 全展开 DSP 346 放不下→资源优先基线'],
       ['9~10', 'T5 故障', 'HLS 调用/下载/idx 解析/权重语法等 bug 定位'],
       ['11~12', 'T5→修复', '导出 IP 的 core_revision 溢出→补丁修复'],
       ['13~14', 'T3 上板', '全链路 RTL + 回环/全链路 bitstream'],
       ['15~17', 'T5 烧写/优化', '便携 Vivado 无硬件管理器→xsct 烧写；FSM 524→88 压平'],
       ['18~20', 'T3/T4 实测', '99/100@115200、健壮性补超时、1Mbps 117→57ms']])

doc.save(OUT)
print('REPORT_SAVED', OUT)
