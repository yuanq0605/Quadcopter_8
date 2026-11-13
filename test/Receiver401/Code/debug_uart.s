;=====================================================================
;  debug_uart.s  ——  【可整块剔除的调试输出模块】
;
;  作用：把 main.s 解析出来的 16 个通道，打包成固定 40 字节的帧，
;        从 USART2 (PA2) 以 115200 8N1 发给电脑（配 sbus_viewer.py 显示）。
;
;  ★ 这个文件是"可插拔"的，接收机本体不依赖它：
;     · 它是唯一配置 PA2 / USART2 的地方，main.s 完全不碰这两个外设；
;     · main.s 里只有两处调用（Debug_OnFrame / Debug_OnIdle），
;       而且都用 IF DEBUG_UART <> 0 包着。
;
;  ★ 剔除调试功能（两步，建议都做）：
;     1) 打开 main.s，把顶部 DEBUG_UART EQU 1 改成 0；
;     2) 在 Keil 工程里把这个 debug_uart.s 从分组中 Remove。
;    做完这两步，固件里不会再有 USART2 / PA2 / 40 字节协议的任何痕迹，
;    接收、解析、DMA 重装逻辑完全不受影响。
;
;  和 main.s 的接口：
;    IMPORT  channels     16 通道 × 4 字节，main.s 的 SBUS_Unpack 写
;    IMPORT  sbus_flags   标志字节，bit5 丢帧 / bit4 失控保护
;  对外提供（main.s 里 IMPORT）：
;    Debug_UART_Init      PA2 复用 + USART2 初始化
;    Debug_OnFrame        主循环解析出一帧合法数据后调用
;    Debug_OnIdle         主循环这一轮没解析到数据时调用
;
;  手册引用（页码为印刷页码）：
;    RM0368 Rev6 = STM32F401xB/C xD/E Reference manual
;    DS9716 Rev3 = STM32F401xD/E DataSheet
;=====================================================================


;=====================================================================
;  0. 寄存器地址（只列本文件用到的）
;     基地址出处：RM0368 P38 / P39 Table 1
;=====================================================================
RCC_AHB1ENR     EQU     0x40023830      ; RM0368 P118（GPIOAEN = bit0）
RCC_APB1ENR     EQU     0x40023840      ; RM0368 P119（USART2EN = bit17，P120）

; ---- GPIOA（基地址 0x4002 0000，RM0368 P38）—— 只用来配 PA2 ----
GPIOA_MODER     EQU     0x40020000      ; RM0368 P158
GPIOA_OSPEEDR   EQU     0x40020008      ; RM0368 P159
GPIOA_AFRL      EQU     0x40020020      ; RM0368 P162

; ---- USART2（基地址 0x4000 4400，RM0368 P39）—— 发数据给电脑 ----
USART2_SR       EQU     0x40004400      ; RM0368 P548（TXE = bit7，P549）
USART2_DR       EQU     0x40004404      ; RM0368 P551
USART2_BRR      EQU     0x40004408      ; RM0368 P551
USART2_CR1      EQU     0x4000440C      ; RM0368 P551
USART2_CR2      EQU     0x40004410      ; RM0368 P554
USART2_CR3      EQU     0x40004414      ; RM0368 P555


;=====================================================================
;  1. 参数
;=====================================================================
TX_FRAME_LEN    EQU     40              ; 上传给电脑的帧长（固定）
TX_HEAD1        EQU     0xA5            ; 上传帧头 1
TX_HEAD2        EQU     0x5A            ; 上传帧头 2
TX_TAIL         EQU     0x5C            ; 上传帧尾
TX_TYPE_SBUS    EQU     0x01            ; 类型：16 通道 SBUS 数据

CH_CENTER       EQU     1024            ; 通道中位（心跳帧用）

;---- 诊断用心跳：长时间收不到有效 SBUS 时，主动发一帧"无数据"包 -----
;     目的：把"串口坏了"和"遥控器没数据"区分开。
;     主循环一次大约 0.2~0.3us，0x100000 次 ≈ 0.25 秒发一次。
;     调试完想只关心真实数据，把 HB_LOOPS 改成 0（0 表示永不发心跳）。
HB_LOOPS        EQU     0x100000


;=====================================================================
;  2. 变量
;
;  ★ 必须写 NOINIT：
;    armasm 里只有 SPACE 没有初值的段，默认仍会被当成"带初值的数据"，
;    在 Flash 里生成一大片 0 再开机拷到 RAM（map 里显示为 Data RW）。
;    加 NOINIT 才是真正的 .bss/ZI 段：不占 Flash，由 start.s 清零。
;=====================================================================
                AREA    DEBUG_RAM, NOINIT, READWRITE, ALIGN=3

tx_frame        SPACE   TX_FRAME_LEN    ; 待发送的 40 字节上传帧
tx_seq          SPACE   4               ; 帧序号 0~255 循环（丢帧时电脑端能看出来）
idle_cnt        SPACE   4               ; 连续多少轮主循环没解析到有效帧（心跳计时）
hb_seq          SPACE   4               ; 心跳帧里 CH1 的递增值


;=====================================================================
;  3. 代码
;=====================================================================
                AREA    DEBUG_CODE, CODE, READONLY, ALIGN=3
                PRESERVE8
                THUMB

                IMPORT  channels                ; 来自 main.s
                IMPORT  sbus_flags              ; 来自 main.s

                EXPORT  Debug_UART_Init
                EXPORT  Debug_OnFrame
                EXPORT  Debug_OnIdle


;=====================================================================
;  Debug_UART_Init —— PA2 复用为 USART2_TX，115200 / 8N1，只发不收
;
;  DS9716 P45 Table 9 "Alternate function mapping"：PA2 的 AF07 = USART2_TX
;
;  BRR：USART2 挂在 APB1，fCK = PCLK1 = 42MHz
;      USARTDIV = 42 000 000 / (16 × 115 200) = 22.786
;      BRR[15:4] = 22 = 0x16
;      BRR[3:0]  = 0.786 × 16 ≈ 13 = 0xD
;      → BRR = 0x16D   (实际 115068bps，误差 +0.06%)
;
;  ★ 注意：这里是唯一打开 GPIOA 时钟的地方。
;    main.s 的 GPIO_Init 只开 GPIOC + DMA2，不碰 GPIOA。
;=====================================================================
Debug_UART_Init
;---- RCC：GPIOA + USART2 -------------------------------------------
                LDR     R0, =RCC_AHB1ENR
                LDR     R1, [R0]
                ORR     R1, R1, #0x00000001     ; bit0  GPIOAEN（RM0368 P118）
                STR     R1, [R0]

                LDR     R0, =RCC_APB1ENR
                LDR     R1, [R0]
                ORR     R1, R1, #0x00020000     ; bit17 USART2EN（RM0368 P120）
                STR     R1, [R0]

;---- PA2 = 复用功能：MODER[5:4] = 10（RM0368 P158）------------------
                LDR     R0, =GPIOA_MODER
                LDR     R1, [R0]
                BIC     R1, R1, #0x00000030
                ORR     R1, R1, #0x00000020
                STR     R1, [R0]

;---- PA2 = 高速：OSPEEDR[5:4] = 11（RM0368 P159）-------------------
                LDR     R0, =GPIOA_OSPEEDR
                LDR     R1, [R0]
                BIC     R1, R1, #0x00000030
                ORR     R1, R1, #0x00000030
                STR     R1, [R0]

;---- PA2 = AF7：AFRL[11:8] = 0111（RM0368 P162）-------------------
                LDR     R0, =GPIOA_AFRL
                LDR     R1, [R0]
                BIC     R1, R1, #0x00000F00
                ORR     R1, R1, #0x00000700
                STR     R1, [R0]

;---- 先关 UE，保证 BRR/CR2/CR3 可以安全写入 ------------------------
                LDR     R0, =USART2_CR1
                MOV     R1, #0
                STR     R1, [R0]

;---- BRR = 0x16D ---------------------------------------------------
                LDR     R0, =USART2_BRR
                LDR     R1, =0x0000016D
                STR     R1, [R0]

;---- CR2：1 个停止位 -----------------------------------------------
                LDR     R0, =USART2_CR2
                MOV     R1, #0
                STR     R1, [R0]

;---- CR3：不使能任何流控/DMA ---------------------------------------
                LDR     R0, =USART2_CR3
                MOV     R1, #0
                STR     R1, [R0]

;---- CR1：UE | TE = 0x2000 | 0x0008 = 0x2008 -----------------------
;     bit13 UE=1  串口使能
;     bit3  TE=1  发送使能（只发不收，所以没开 RE）
                LDR     R0, =USART2_CR1
                LDR     R1, =0x00002008
                STR     R1, [R0]
                BX      LR


;=====================================================================
;  Debug_OnFrame —— 主循环成功解析出一帧 SBUS 后调用
;
;  做两件事：
;    ① 把"没收到数据"的计时清零（只要正常收数，就永不发心跳）；
;    ② 把 16 通道打包成 40 字节，从 USART2 发出去。
;
;  入参：无；出参：无；破坏 R0~R8
;=====================================================================
Debug_OnFrame
                PUSH    {R4, LR}                    ; 2 个寄存器 = 8 字节，保持栈对齐

                LDR     R0, =idle_cnt
                MOV     R1, #0
                STR     R1, [R0]                    ; 心跳计时清零

                BL      SBUS_SendFrame
                POP     {R4, LR}
                BX      LR


;=====================================================================
;  Debug_OnIdle —— 主循环这一轮没解析到数据时调用
;
;  维护 idle_cnt：每调用一次 +1，累加到 HB_LOOPS 就发一帧"我还活着"。
;  之所以放在主循环而不是定时器里，是因为主循环本身就一直在跑，
;  不需要额外占用一个 TIM。
;
;  ★ 如果 idle_cnt 一直涨却从不触发心跳，说明 HB_LOOPS 被改成 0 了。
;=====================================================================
Debug_OnIdle
                PUSH    {R4, LR}

                LDR     R0, =idle_cnt
                LDR     R1, [R0]
                ADD     R1, R1, #1
                STR     R1, [R0]

                LDR     R2, =HB_LOOPS
                CMP     R2, #0                      ; HB_LOOPS=0 → 关闭心跳
                BEQ     DOI_Exit
                CMP     R1, R2
                BLO     DOI_Exit

                MOV     R1, #0
                STR     R1, [R0]                    ; 计满清零
                BL      SBUS_SendNoData

DOI_Exit
                POP     {R4, LR}
                BX      LR


;=====================================================================
;  SBUS_SendNoData —— 心跳帧：告诉电脑"我活着，但没收到遥控器"
;
;  内容：CH1..CH16 = 1024（中位）、CH1 换成递增数（便于肉眼确认在刷新）、
;        flags = 0xF0（CH17/CH18/丢帧/失控 全部置位）。
;  上位机看到的表现：五个状态灯全亮、帧率只有 2~4Hz、通道值固定在 1024。
;  这就说明"串口链路是通的，问题在 SBUS 那一侧"。
;
;  ★ 这里会临时改写 channels[]（反正没收到数据时它本来就是旧值），
;    下一帧真正的 SBUS 来了，SBUS_Unpack 会把 16 个通道全部重写。
;=====================================================================
SBUS_SendNoData
                PUSH    {R4-R6, LR}

                LDR     R4, =channels
                MOV     R5, #CH_CENTER              ; 1024
                MOV     R6, #15
SND_Fill
                STR     R5, [R4], #4                ; 前 15 个通道填 1024
                SUBS    R6, R6, #1
                BNE     SND_Fill
                STR     R5, [R4]                    ; 第 16 个

                LDR     R0, =hb_seq                 ; CH1 换成递增数
                LDR     R1, [R0]
                ADD     R1, R1, #1
                AND     R1, R1, #0xFF               ; 0x7FF 不是合法立即数，0xFF 足够
                STR     R1, [R0]
                LDR     R4, =channels
                STR     R1, [R4]

                LDR     R0, =sbus_flags             ; 标志全置位
                MOV     R1, #0xF0
                STR     R1, [R0]

                BL      SBUS_SendFrame
                POP     {R4-R6, LR}
                BX      LR


;=====================================================================
;  SBUS_SendFrame —— 把 16 通道打包成 40 字节，从 USART2 发给电脑
;
;  帧格式（固定 40 字节，小端）：
;    偏移  内容
;      0    0xA5        帧头 1
;      1    0x5A        帧头 2
;      2    0x01        类型：SBUS 通道数据
;      3    seq         帧序号 0~255 循环（丢帧时电脑端能看出来）
;      4    CH1 低字节
;      5    CH1 高字节       …… CH2..CH15 依次类推，每通道 2 字节 ……
;     34    CH16 低字节
;     35    CH16 高字节
;     36    flags       SBUS 标志字节原样（bit7 CH17 / bit6 CH18 /
;                                     bit5 丢帧 / bit4 失控保护）
;     37    0x00        保留，对齐用
;     38    sum         校验：byte0~37 累加，取低 8 位
;     39    0x5C        帧尾
;
;  发送方式：轮询 TXE（RM0368 P549，SR 的 bit7）。
;  40 字节 @115200 = 3.5ms，SBUS 帧周期 14ms，占 25% 时间——够用。
;  想再省 CPU 可以改成 DMA 发送（DMA2 Stream6 Channel4 = USART2_TX，
;  RM0368 P171 Table 29）。
;
;  入参：无（直接读全局 channels / sbus_flags）
;  出参：无（破坏 R0~R8）
;=====================================================================
SBUS_SendFrame
                PUSH    {R4-R8, LR}                 ; 6 个 = 24B，保持 8 字节对齐

                LDR     R4, =tx_frame               ; R4 = 帧缓冲区

;---- ① 帧头 + 类型 -------------------------------------------------
                MOV     R5, #TX_HEAD1
                STRB    R5, [R4]
                MOV     R5, #TX_HEAD2
                STRB    R5, [R4, #1]
                MOV     R5, #TX_TYPE_SBUS
                STRB    R5, [R4, #2]

;---- ② 帧序号 ------------------------------------------------------
                LDR     R5, =tx_seq
                LDR     R6, [R5]
                STRB    R6, [R4, #3]                ; 本帧用旧序号
                ADD     R6, R6, #1
                AND     R6, R6, #0xFF
                STR     R6, [R5]                    ; 下一帧 +1（0~255 循环）

;---- ③ 16 个通道，每个 2 字节小端 ----------------------------------
                LDR     R0, =channels               ; 通道数组（每项 4 字节）
                ADD     R1, R4, #4                  ; 从偏移 4 开始写
                MOV     R2, #16
SF_ChLoop
                LDRH    R3, [R0], #4                ; 取低 16 位，指针 +4
                STRH    R3, [R1], #2                ; 写 2 字节，指针 +2
                SUBS    R2, R2, #1
                BNE     SF_ChLoop

;---- ④ 标志字节 + 保留 ---------------------------------------------
                LDR     R0, =sbus_flags
                LDR     R1, [R0]
                STRB    R1, [R4, #36]
                MOV     R1, #0
                STRB    R1, [R4, #37]

;---- ⑤ 校验：byte0~37 累加取低 8 位 --------------------------------
                MOV     R7, #0                      ; R7 = 累加和
                MOV     R5, #0                      ; R5 = 下标
SF_SumLoop
                LDRB    R6, [R4, R5]
                ADD     R7, R7, R6
                ADD     R5, R5, #1
                CMP     R5, #38
                BLT     SF_SumLoop
                AND     R7, R7, #0xFF
                STRB    R7, [R4, #38]

                MOV     R5, #TX_TAIL
                STRB    R5, [R4, #39]

;---- ⑥ 逐字节发出去：等 TXE=1 再写 DR ------------------------------
                LDR     R8, =USART2_SR              ; R8 = SR 地址（循环外取一次）
                LDR     R0, =USART2_DR              ; R0 = DR 地址
                MOV     R5, #0                      ; R5 = 下标
SF_TxLoop
                LDRB    R6, [R4, R5]
SF_WaitTXE
                LDR     R7, [R8]
                TST     R7, #0x00000080             ; bit7 TXE：发送寄存器空？
                BEQ     SF_WaitTXE                  ; 没空就等
                STR     R6, [R0]                    ; 写入 DR，硬件自动发出去
                ADD     R5, R5, #1
                CMP     R5, #TX_FRAME_LEN
                BLT     SF_TxLoop

                POP     {R4-R8, LR}
                BX      LR

                END
