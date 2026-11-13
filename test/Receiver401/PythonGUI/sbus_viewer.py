#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SBUS 16 通道上位机 —— 配套 STM32F401 «挑战点8»

功能：
  1. 自动搜索 / 刷新 / 选择当前可用串口（带设备描述）
  2. 自选波特率、数据位、校验、停止位，只接收不发送
  3. 16 个通道用条形图动态刷新（不是刷屏的流水日志）
  4. 显示帧率、总帧数、校验错误数，以及 SBUS 的丢帧/失控保护/CH17/CH18 标志

帧格式（与 main.s 里的 SBUS_SendFrame 严格一致，固定 40 字节）：
    偏移  内容
      0    0xA5            帧头 1
      1    0x5A            帧头 2
      2    0x01            类型：SBUS 通道数据
      3    seq             帧序号 0~255
      4    CH1..CH16       每个 uint16 小端（0~2047），共 32 字节
     36    flags           bit7 CH17 / bit6 CH18 / bit5 丢帧 / bit4 失控保护
     37    0x00            保留
     38    sum             byte0~37 累加取低 8 位
     39    0x5C            帧尾

依赖：pip install pyserial
运行：python sbus_viewer.py
自检：python sbus_viewer.py --selftest      （不需要串口，验证解析器）
"""

import os
import sys
import json
import time
import struct
import threading

# ---------------------------------------------------------------- 协议常量
FRAME_LEN = 40
HEAD = b"\xA5\x5A"
TAIL = 0x5C
TYPE_SBUS = 0x01

CH_COUNT = 16
CH_MIN, CH_MAX = 0, 2047
CH_CENTER = 1024

# SBUS 标志位
FLAG_CH17 = 0x80
FLAG_CH18 = 0x40
FLAG_LOST = 0x20      # 上一帧丢失
FLAG_FAILSAFE = 0x10  # 接收机进入失控保护


# ---------------------------------------------------------------- 解析器
class SbusParser:
    """从字节流里切出 40 字节帧。与界面无关，方便单独测试。"""

    def __init__(self):
        self.buf = bytearray()
        self.frames = 0        # 校验通过的帧数
        self.errors = 0        # 校验失败/错位的次数
        self.seq_gap = 0       # 序号不连续（丢帧）的次数
        self.last_seq = None

    def feed(self, data):
        """喂入原始字节，返回本次新解析出的帧列表。"""
        self.buf.extend(data)
        out = []

        # 防止一直收到垃圾把内存撑爆
        if len(self.buf) > 8192:
            del self.buf[:-128]

        while True:
            i = self.buf.find(HEAD)
            if i < 0:
                # 没有帧头：只留最后一个字节（可能是下一帧的 0xA5）
                if self.buf:
                    del self.buf[:-1]
                break
            if i > 0:
                del self.buf[:i]          # 丢掉帧头之前的杂字节
            if len(self.buf) < FRAME_LEN:
                break                      # 还没收够一帧，等下次

            frame = bytes(self.buf[:FRAME_LEN])
            if frame[FRAME_LEN - 1] == TAIL and (sum(frame[:38]) & 0xFF) == frame[38]:
                ch = struct.unpack_from("<16H", frame, 4)
                flags = frame[36]
                seq = frame[3]

                # 序号连续性检查（可用来观察丢帧）
                if self.last_seq is not None and (self.last_seq + 1) & 0xFF != seq:
                    self.seq_gap += 1
                self.last_seq = seq

                self.frames += 1
                out.append((ch, flags, seq))
                del self.buf[:FRAME_LEN]
            else:
                # 帧尾或校验不对：只丢 1 字节，重新对齐
                self.errors += 1
                del self.buf[:1]
        return out


# ---------------------------------------------------------------- 串口读取线程
class Reader(threading.Thread):
    def __init__(self, ser, parser, on_frame, on_error):
        super().__init__(daemon=True)
        self.ser = ser
        self.parser = parser
        self.on_frame = on_frame
        self.on_error = on_error
        self.running = True

    def run(self):
        while self.running:
            try:
                n = self.ser.in_waiting
                data = self.ser.read(n if n else 1)
                if data:
                    for item in self.parser.feed(data):
                        self.on_frame(*item)
            except Exception as e:          # 拔线、驱动异常等
                if self.running:
                    self.on_error(str(e))
                break

    def stop(self):
        self.running = False


# ---------------------------------------------------------------- 界面
def make_ui():
    import tkinter as tk
    from tkinter import ttk
    return tk, ttk


BG = "#f5f7fa"
CARD = "#ffffff"
TRACK = "#e6eaf0"
FILL = "#2f80ed"
FILL_MID = "#27ae60"
TICK = "#b9c2cf"
TEXT = "#1f2933"
MUTED = "#6b7785"
WARN = "#e74c3c"


def run_gui():
    try:
        import serial
        from serial.tools import list_ports
    except ImportError:
        print("缺少 pyserial，请先执行：  pip install pyserial")
        sys.exit(1)

    import tkinter as tk
    from tkinter import ttk, messagebox

    cfg_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sbus_viewer.json")

    # ---------------- 配置持久化 ----------------
    def load_cfg():
        try:
            with open(cfg_path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return {}

    def save_cfg(d):
        try:
            with open(cfg_path, "w", encoding="utf-8") as f:
                json.dump(d, f, ensure_ascii=False, indent=2)
        except Exception:
            pass

    cfg = load_cfg()

    root = tk.Tk()
    root.title("SBUS 16 通道监视器 — STM32F401")
    root.geometry("820x780")
    root.minsize(720, 700)
    root.configure(bg=BG)

    style = ttk.Style()
    try:
        style.theme_use("clam")
    except Exception:
        pass
    style.configure("TLabel", background=BG, foreground=TEXT, font=("Microsoft YaHei UI", 9))
    style.configure("TCheckbutton", background=BG, foreground=TEXT)
    style.configure("TButton", font=("Microsoft YaHei UI", 9))
    style.configure("TCombobox", font=("Consolas", 10))

    # ---------------- 顶部：串口设置 ----------------
    top = tk.Frame(root, bg=CARD, bd=0, highlightthickness=1,
                   highlightbackground="#dde3ea")
    top.pack(fill="x", padx=12, pady=(12, 6))

    row1 = tk.Frame(top, bg=CARD)
    row1.pack(fill="x", padx=12, pady=(10, 4))

    tk.Label(row1, text="串口", bg=CARD, fg=TEXT,
             font=("Microsoft YaHei UI", 9)).pack(side="left")
    port_var = tk.StringVar()
    port_box = ttk.Combobox(row1, textvariable=port_var, width=34, state="readonly")
    port_box.pack(side="left", padx=(6, 6))

    def refresh_ports(select_keep=True):
        ports = list(list_ports.comports())
        items = []
        for p in ports:
            desc = p.description or ""
            if p.manufacturer:
                desc = f"{desc} · {p.manufacturer}" if desc else p.manufacturer
            items.append(f"{p.device} — {desc}" if desc else p.device)
        port_box["values"] = items
        if items:
            keep = None
            if select_keep and port_var.get() in items:
                keep = port_var.get()
            elif cfg.get("port") in items:
                keep = cfg["port"]
            port_var.set(keep or items[0])
        else:
            port_var.set("")
        status_var.set(f"找到 {len(items)} 个串口" if items else "没有找到任何串口，检查 USB 线和驱动")
        return items

    tk.Button(row1, text="刷新", command=lambda: refresh_ports(False),
              font=("Microsoft YaHei UI", 9), relief="flat",
              bg="#eef2f7", activebackground="#e2e8f0", padx=10
              ).pack(side="left", padx=(0, 14))

    tk.Label(row1, text="波特率", bg=CARD, fg=TEXT,
             font=("Microsoft YaHei UI", 9)).pack(side="left")
    baud_var = tk.StringVar(value=str(cfg.get("baud", 115200)))
    baud_box = ttk.Combobox(row1, textvariable=baud_var, width=9,
                            values=["9600", "19200", "38400", "57600", "115200",
                                    "230400", "460800", "921600"])
    baud_box.pack(side="left", padx=(6, 14))

    tk.Label(row1, text="校验", bg=CARD, fg=TEXT,
             font=("Microsoft YaHei UI", 9)).pack(side="left")
    parity_var = tk.StringVar(value=cfg.get("parity", "N"))
    ttk.Combobox(row1, textvariable=parity_var, width=4,
                 values=["N", "E", "O", "M", "S"], state="readonly"
                 ).pack(side="left", padx=(6, 14))

    tk.Label(row1, text="停止位", bg=CARD, fg=TEXT,
             font=("Microsoft YaHei UI", 9)).pack(side="left")
    stop_var = tk.StringVar(value=str(cfg.get("stop", "1")))
    ttk.Combobox(row1, textvariable=stop_var, width=4,
                 values=["1", "1.5", "2"], state="readonly"
                 ).pack(side="left", padx=(6, 14))

    tk.Label(row1, text="数据位", bg=CARD, fg=TEXT,
             font=("Microsoft YaHei UI", 9)).pack(side="left")
    bits_var = tk.StringVar(value=str(cfg.get("bits", "8")))
    ttk.Combobox(row1, textvariable=bits_var, width=3,
                 values=["8", "7"], state="readonly"
                 ).pack(side="left", padx=(6, 0))

    row2 = tk.Frame(top, bg=CARD)
    row2.pack(fill="x", padx=12, pady=(2, 10))

    status_var = tk.StringVar(value="未连接")
    status_lbl = tk.Label(row2, textvariable=status_var, bg=CARD, fg=MUTED,
                          font=("Microsoft YaHei UI", 9), anchor="w")
    status_lbl.pack(side="left", fill="x", expand=True)

    btn_open = tk.Button(row2, text="打开串口", width=12,
                         font=("Microsoft YaHei UI", 9, "bold"),
                         relief="flat", bg="#2f80ed", fg="white",
                         activebackground="#1c6fd8", activeforeground="white")
    btn_open.pack(side="right")

    # ---------------- 中部：16 通道 ----------------
    mid = tk.Frame(root, bg=CARD, highlightthickness=1,
                   highlightbackground="#dde3ea")
    mid.pack(fill="both", expand=True, padx=12, pady=6)

    header = tk.Frame(mid, bg=CARD)
    header.pack(fill="x", padx=14, pady=(8, 2))
    tk.Label(header, text="通道", bg=CARD, fg=MUTED, width=5, anchor="w",
             font=("Microsoft YaHei UI", 8)).pack(side="left")
    tk.Label(header, text="0", bg=CARD, fg=MUTED, font=("Consolas", 8)).pack(side="left")
    tk.Label(header, text="位置（0 ~ 2047，中间刻度 = 1024）", bg=CARD, fg=MUTED,
             font=("Microsoft YaHei UI", 8)).pack(side="left", padx=(6, 0))

    ch_rows = []
    BAR_W, BAR_H = 380, 16

    for i in range(CH_COUNT):
        row = tk.Frame(mid, bg=CARD)
        row.pack(fill="x", padx=14, pady=1)

        name = tk.Label(row, text=f"CH{i + 1:d}", bg=CARD, fg=TEXT, width=5, anchor="w",
                        font=("Consolas", 10, "bold"))
        name.pack(side="left")

        cv = tk.Canvas(row, width=BAR_W, height=BAR_H, bg=CARD,
                       highlightthickness=0, bd=0)
        cv.pack(side="left", padx=(4, 10))
        track = cv.create_rectangle(0, 3, BAR_W, BAR_H - 3, fill=TRACK, outline="")
        # 中点刻度
        cx = BAR_W * CH_CENTER / CH_MAX
        cv.create_line(cx, 0, cx, BAR_H, fill=TICK)
        bar = cv.create_rectangle(0, 3, 0, BAR_H - 3, fill=FILL, outline="")

        val = tk.Label(row, text="----", bg=CARD, fg=TEXT, width=6, anchor="e",
                       font=("Consolas", 11))
        val.pack(side="left")
        us = tk.Label(row, text="", bg=CARD, fg=MUTED, width=8, anchor="e",
                      font=("Consolas", 9))
        us.pack(side="left", padx=(8, 0))

        ch_rows.append({"cv": cv, "bar": bar, "val": val, "us": us})

    # ---------------- 底部：统计与标志 ----------------
    bot = tk.Frame(root, bg=CARD, highlightthickness=1,
                   highlightbackground="#dde3ea")
    bot.pack(fill="x", padx=12, pady=(6, 12))

    stat = tk.Frame(bot, bg=CARD)
    stat.pack(fill="x", padx=14, pady=(10, 6))

    fps_var = tk.StringVar(value="帧率 -- Hz")
    total_var = tk.StringVar(value="总帧 0")
    err_var = tk.StringVar(value="错误 0")
    gap_var = tk.StringVar(value="序号跳变 0")

    for v in (fps_var, total_var, err_var, gap_var):
        tk.Label(stat, textvariable=v, bg=CARD, fg=TEXT,
                 font=("Consolas", 10)).pack(side="left", padx=(0, 22))

    flagbar = tk.Frame(bot, bg=CARD)
    flagbar.pack(fill="x", padx=14, pady=(0, 10))

    def chip(parent, text):
        lbl = tk.Label(parent, text="● " + text, bg="#eef2f7", fg=MUTED,
                       font=("Microsoft YaHei UI", 9), padx=8, pady=2)
        lbl.pack(side="left", padx=(0, 8))
        return lbl

    chip_ok = chip(flagbar, "数据正常")
    chip_lost = chip(flagbar, "丢帧")
    chip_fail = chip(flagbar, "失控保护")
    chip_17 = chip(flagbar, "CH17")
    chip_18 = chip(flagbar, "CH18")

    # ---------------- 状态 ----------------
    latest = {"ch": None, "flags": 0, "t": 0.0}
    lock = threading.Lock()
    parser = SbusParser()
    reader = None
    ser = None
    last_frames = 0
    last_t = time.time()
    fps = 0.0

    def on_frame(ch, flags, seq):
        with lock:
            latest["ch"] = ch
            latest["flags"] = flags
            latest["t"] = time.time()

    def on_error(msg):
        root.after(0, lambda: do_close(f"串口异常：{msg}"))

    # ---------------- 打开 / 关闭 ----------------
    def do_open():
        nonlocal reader, ser, last_frames, last_t
        if ser is not None:
            do_close("已断开")
            return

        sel = port_var.get()
        if not sel:
            messagebox.showwarning("没有串口", "请先点『刷新』并选择一个串口。")
            return
        device = sel.split(" — ")[0].strip()

        # 打开前再确认一次这个口还在（防止刚拔掉）
        avail = [p.device for p in list_ports.comports()]
        if device not in avail:
            messagebox.showerror("串口不可用", f"{device} 当前不在设备列表里，请刷新后重试。")
            refresh_ports(False)
            return

        try:
            baud = int(baud_var.get())
        except ValueError:
            messagebox.showerror("参数错误", "波特率必须是整数。")
            return

        pmap = {"N": serial.PARITY_NONE, "E": serial.PARITY_EVEN,
                "O": serial.PARITY_ODD, "M": serial.PARITY_MARK,
                "S": serial.PARITY_SPACE}
        smap = {"1": serial.STOPBITS_ONE, "1.5": serial.STOPBITS_ONE_POINT_FIVE,
                "2": serial.STOPBITS_TWO}
        bmap = {"8": serial.EIGHTBITS, "7": serial.SEVENBITS}

        try:
            ser = serial.Serial(
                port=device,
                baudrate=baud,
                bytesize=bmap.get(bits_var.get(), serial.EIGHTBITS),
                parity=pmap.get(parity_var.get(), serial.PARITY_NONE),
                stopbits=smap.get(stop_var.get(), serial.STOPBITS_ONE),
                timeout=0.05,
            )
        except Exception as e:
            ser = None
            messagebox.showerror("打开失败", f"{device} 打不开：\n{e}\n\n"
                                             "常见原因：被别的软件占用、驱动没装、口选错了。")
            return

        parser.__init__()          # 重置统计
        last_frames = 0
        last_t = time.time()
        reader = Reader(ser, parser, on_frame, on_error)
        reader.start()

        btn_open.configure(text="关闭串口", bg="#e74c3c", activebackground="#c0392b")
        set_status(f"已连接 {device} @ {baud} "
                   f"{bits_var.get()}{parity_var.get()}{stop_var.get()}", "#27ae60")
        save_cfg({"port": sel, "baud": baud, "parity": parity_var.get(),
                  "stop": stop_var.get(), "bits": bits_var.get()})

    def do_close(msg="已断开"):
        nonlocal reader, ser
        if reader:
            reader.stop()
            reader = None
        if ser:
            try:
                ser.close()
            except Exception:
                pass
            ser = None
        btn_open.configure(text="打开串口", bg="#2f80ed", activebackground="#1c6fd8")
        set_status(msg, MUTED)

    def set_status(text, color=MUTED):
        status_var.set(text)
        status_lbl.configure(fg=color)

    def on_btn():
        if ser is None:
            do_open()
        else:
            do_close()

    btn_open.configure(command=on_btn)

    # ---------------- 定时刷新界面 ----------------
    def tick():
        nonlocal last_frames, last_t, fps
        now = time.time()

        with lock:
            ch = latest["ch"]
            flags = latest["flags"]
            t = latest["t"]

        # 帧率：每秒统计一次
        if now - last_t >= 1.0:
            fps = (parser.frames - last_frames) / (now - last_t)
            last_frames = parser.frames
            last_t = now
            fps_var.set(f"帧率 {fps:5.1f} Hz")

        total_var.set(f"总帧 {parser.frames}")
        err_var.set(f"错误 {parser.errors}")
        gap_var.set(f"序号跳变 {parser.seq_gap}")

        if ch is None:
            # 还没收到数据
            for r in ch_rows:
                r["val"].configure(text="----", fg=MUTED)
                r["us"].configure(text="")
                r["cv"].coords(r["bar"], 0, 3, 0, BAR_H - 3)
            for c in (chip_ok, chip_lost, chip_fail, chip_17, chip_18):
                c.configure(bg="#eef2f7", fg=MUTED)
        else:
            fresh = (now - t) < 1.0
            for i, r in enumerate(ch_rows):
                v = ch[i]
                v = CH_MIN if v < CH_MIN else (CH_MAX if v > CH_MAX else v)
                x = BAR_W * v / CH_MAX
                r["cv"].coords(r["bar"], 0, 3, x, BAR_H - 3)
                r["val"].configure(text=f"{v:4d}", fg=TEXT if fresh else MUTED)
                # 常见的 SBUS→PWM 映射：192~1792 → 1000~2000us
                us = 1000 + (v - 192) * 1000 / 1600
                r["us"].configure(text=f"{us:6.0f} us")

            def paint(widget, on, color):
                if on:
                    widget.configure(bg=color, fg="white")
                else:
                    widget.configure(bg="#eef2f7", fg=MUTED)

            lost = bool(flags & FLAG_LOST)
            fail = bool(flags & FLAG_FAILSAFE)
            paint(chip_ok, fresh and not lost and not fail, "#27ae60")
            paint(chip_lost, lost, "#e67e22")
            paint(chip_fail, fail, "#e74c3c")
            paint(chip_17, bool(flags & FLAG_CH17), "#2f80ed")
            paint(chip_18, bool(flags & FLAG_CH18), "#2f80ed")

            if ser is not None and not fresh:
                set_status("串口已打开，但 1 秒内没有收到合法数据："
                           "检查波特率是否 115200、TX/RX 是否接反", "#e67e22")

        root.after(33, tick)     # ~30fps 刷新，够顺滑又不吃 CPU

    def on_close():
        do_close()
        root.destroy()

    root.protocol("WM_DELETE_WINDOW", on_close)

    refresh_ports(False)
    # 有保存过的串口就优先选它
    if cfg.get("port") and cfg["port"] in (port_box["values"] or ()):
        port_var.set(cfg["port"])

    tick()
    root.mainloop()


# ---------------------------------------------------------------- 自检
def selftest():
    """不需要串口，构造几帧数据验证解析器（含坏帧、分段到达）。"""
    import random

    def build(ch, flags=0, seq=0):
        f = bytearray(40)
        f[0], f[1], f[2], f[3] = 0xA5, 0x5A, 0x01, seq
        struct.pack_into("<16H", f, 4, *ch)
        f[36] = flags
        f[37] = 0
        f[38] = sum(f[:38]) & 0xFF
        f[39] = 0x5C
        return bytes(f)

    ok = True
    rnd = random.Random(7)

    # 1) 普通帧
    p = SbusParser()
    ch = [1024] * 16
    frames = p.feed(build(ch, 0, 0))
    print(f"[1] 单帧解析: {len(frames)} 帧, 通道0={frames[0][0][0] if frames else None}", end="  ")
    ok &= len(frames) == 1 and frames[0][0][0] == 1024
    print("OK" if ok else "FAIL")

    # 2) 16 个通道填满边界值
    p = SbusParser()
    vals = [0, 1, 2, 1023, 1024, 1025, 2045, 2046, 2047] + [rnd.randint(0, 2047) for _ in range(7)]
    frames = p.feed(build(vals, 0xD0, 5))
    got = list(frames[0][0]) if frames else []
    print(f"[2] 边界值还原: {got[:4]}... flags=0x{frames[0][1]:02X}" if frames else "[2] 无帧")
    ok &= got == vals
    print("    ", "OK" if got == vals else "FAIL")

    # 3) 分段到达（模拟串口一次只读到几个字节）
    p = SbusParser()
    data = build([100 + i for i in range(16)], 0, 1)
    got = []
    for i in range(0, len(data), 7):
        got += p.feed(data[i:i + 7])
    print(f"[3] 拆成 7 字节一片喂入: 解析出 {len(got)} 帧", end="  ")
    ok &= len(got) == 1
    print("OK" if len(got) == 1 else "FAIL")

    # 4) 坏帧（校验错）后紧跟好帧，应能自动重新对齐
    p = SbusParser()
    bad = bytearray(build([500] * 16, 0, 2))
    bad[38] ^= 0xFF
    good = build([600] * 16, 0, 3)
    frames = p.feed(bytes(bad) + good)
    print(f"[4] 坏帧后重同步: 好帧 {len(frames)} 个, 错误计 {p.errors}", end="  ")
    ok &= len(frames) == 1 and frames[0][0][0] == 600
    print("OK" if len(frames) == 1 and frames[0][0][0] == 600 else "FAIL")

    # 5) 前面塞垃圾字节
    p = SbusParser()
    frames = p.feed(b"\x00\x11\x22" + build([777] * 16, 0, 4))
    print(f"[5] 帧前有垃圾: 解析出 {len(frames)} 帧", end="  ")
    ok &= len(frames) == 1
    print("OK" if len(frames) == 1 else "FAIL")

    # 6) 序号跳变检测
    p = SbusParser()
    p.feed(build([1] * 16, 0, 10))
    p.feed(build([1] * 16, 0, 13))     # 跳了 3
    print(f"[6] 序号跳变计数: {p.seq_gap} (期望 1)", end="  ")
    ok &= p.seq_gap == 1
    print("OK" if p.seq_gap == 1 else "FAIL")

    print("\n总结:", "全部通过" if ok else "有用例失败")
    return 0 if ok else 1


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    run_gui()
