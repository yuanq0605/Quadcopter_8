;=====================================================================
;  main.s   ——   SBUS 遥控器接收与解析（接收机主体）
;                 v2：单缓冲，DMA 直接搬进 25 字节，不用环形缓冲区
;
;  ★ 本文件只负责"收 + 解析"，不含任何调试输出。
;    往电脑发数据的逻辑（USART2 / PA2 / 40 字节上传帧 / 心跳）全部在
;    debug_uart.s 里，可以整块扔掉，见下面的"如何剔除"。
;
;    接收：USART6 (PC7) + DMA2_Stream1 + IDLE 中断  ← 反相器后的 SBUS
;
;  目标芯片 : STM32F401RET6  (LQFP64，512KB Flash / 96KB SRAM)
;  工具链   : Keil MDK (armasm 语法)
;
;  引脚分配：
;    PC7  = USART6_RX (AF8)  ← SBUS（接收机 → 反相器 → PC7）
;    PA2  = USART2_TX (AF7)  → 调试输出，由 debug_uart.s 配置
;
;  ================= 如何剔除调试输出（只留接收机） =================
;    第 0 节的 DEBUG_UART 是总开关：
;      DEBUG_UART = 1 → 正常编译，debug_uart.s 必须一起加入工程（默认）
;      DEBUG_UART = 0 → 本文件不再引用 debug_uart.s 的任何符号，
;                       把 debug_uart.s 从工程 Remove 掉也能链接通过，
;                       而且 PA2 / USART2 完全不会被初始化。
;    推荐两步都做（改 0 + 移除文件）；只改 0 也能跑，只是代码还占 Flash。
;    注意：只移除文件却不改 0，会报 L6218E: Undefined symbol Debug_xxx。
;
;  ============ 这一版和 v1（环形缓冲）的区别 ============
;  上一版：DMA 循环模式 → 256 字节环形缓冲区 → 中断算长度 → 主循环拷贝再解析。
;  这一版：DMA 普通模式 → 只有 25 字节的 rx_buf → 中断判"是不是正好 25 个" →
;          满了就交给主循环解析，没满就判定这帧坏了、直接重装 DMA 重新收。
;
;  为什么这样也不会错位：
;    IDLE 中断是在"总线已经安静了一个字节时间"之后才触发的，也就是这一波
;    数据已经彻底发完了。此时：
;      NDTR == 0  → 正好收到 25 个字节，是完整一帧；
;      NDTR != 0  → 只收到 25-NDTR 个，这帧被截断了，丢掉。
;    两种情况下我们都会把 DMA 重新装填成 NDTR=25、写指针回到 buf[0]，
;    所以下一波数据一定从第 0 个字节开始写 —— 天然对齐，不会错位。
;
;  代价：
;    DMA 在这一帧收满后是停住的，要等主循环解析完再重新装填。
;    如果主循环被卡住超过一个 SBUS 帧周期（14ms），这一帧就会丢。
;    本工程主循环很闲（解析约 50us），完全够用。
;    如果以后主循环变重，就换回 v1 的环形缓冲方案（已备份）。
;
;  手册引用（页码为印刷页码，可直接翻页核对）：
;    RM0368 Rev6 = STM32F401xB/C xD/E Reference manual
;    PM0214 Rev4 = STM32F3/F4 系列 Cortex-M4 内核编程手册
;    DS9716 Rev3 = STM32F401xD/E DataSheet (DataSheet-f401re.pdf)
;
;  代码组织（对应文档"流程梳理"第 2~6 步）：
;    asm_main           → 第 3、4 步：先配时钟，再配外设，最后开中断
;    Clock_Init         → 第 3 步：HSI 16MHz --PLL--> 84MHz
;    GPIO_Init          → 第 4 步：PC7 → USART6_RX
;    DMA2_Stream1_Init  → 第 4 步：DMA2 Stream1 Ch5，普通模式，NDTR=25
;    USART6_Init        → 第 4 步：100k / 8E2 / 开 IDLE 中断 / 开 DMA 请求
;    DMA_Rearm          →         把 DMA 重新装填成"再收 25 字节"
;    NVIC_Init          → 第 4 步：使能 IRQ71
;    USART6_IRQHandler  → 第 5 步：判满/判残，满则置标志，残则重装
;    SBUS_Task          → 第 6 步：主循环查标志 → 校验头尾 → 解析 → 重装
;    SBUS_Unpack        →         11-bit 位拼接 → channels[16]
;
;    ---- 以下在 debug_uart.s（可剔除）----
;    Debug_UART_Init    →         PA2 复用 + USART2 115200 8N1
;    Debug_OnFrame      →         收到一帧有效数据 → 打包上传
;    Debug_OnIdle       →         这一轮没数据 → 心跳计时
;=====================================================================


;=====================================================================
;  0. 编译开关
;=====================================================================
;  1 = 带 UART2 调试输出（需要 debug_uart.s 一起参与编译）
;  0 = 纯接收机（debug_uart.s 可以从工程里删掉）
DEBUG_UART      EQU     1

;=====================================================================
;  0. 寄存器地址表
;     基地址出处：RM0368 P38 / P39  Table 1
;                "STM32F401xB/C and STM32F401xD/E register boundary addresses"
;=====================================================================
; ---- 系统控制 ----
FLASH_ACR       EQU     0x40023C00      ; RM0368 P38 边界表 / P60 寄存器说明
PWR_CR          EQU     0x40007000      ; RM0368 P39 边界表 / P87 寄存器说明
RCC_CR          EQU     0x40023800      ; RM0368 P38 / P103
RCC_PLLCFGR     EQU     0x40023804      ; RM0368 P105
RCC_CFGR        EQU     0x40023808      ; RM0368 P107（SW/SWS 位定义在 P109）
RCC_AHB1ENR     EQU     0x40023830      ; RM0368 P118
RCC_APB1ENR     EQU     0x40023840      ; RM0368 P119（USART2EN/PWREN 在 P120）
RCC_APB2ENR     EQU     0x40023844      ; RM0368 P122（USART6EN=bit5，P123）

; ---- GPIOC（基地址 0x4002 0800，RM0368 P38）----
GPIOC_MODER     EQU     0x40020800      ; RM0368 P158
GPIOC_OSPEEDR   EQU     0x40020808      ; RM0368 P159
GPIOC_PUPDR     EQU     0x4002080C      ; RM0368 P160
GPIOC_AFRL      EQU     0x40020820      ; RM0368 P162（PC7 的 AF 在 bit31:28）

; ---- USART6（基地址 0x4001 1400，RM0368 P39）—— 收 SBUS ----
;      寄存器偏移与 USART2 完全相同，只是基地址不同
USART6_SR       EQU     0x40011400      ; RM0368 P548（IDLE=bit4，P549）
USART6_DR       EQU     0x40011404      ; RM0368 P551
USART6_BRR      EQU     0x40011408      ; RM0368 P551
USART6_CR1      EQU     0x4001140C      ; RM0368 P551（各使能位 P552~P553）
USART6_CR2      EQU     0x40011410      ; RM0368 P554（STOP[1:0]=bit13:12）
USART6_CR3      EQU     0x40011414      ; RM0368 P555（DMAR=bit6，P556）

; ---- DMA2（基地址 0x4002 6400，RM0368 P38）----
;      Stream1 的寄存器偏移 = 0x10 + 0x18 × 1 = 0x28（RM0368 P191）
DMA2_LISR       EQU     0x40026400      ; RM0368 P188
DMA2_LIFCR      EQU     0x40026408      ; RM0368 P190
DMA2_S1CR       EQU     0x40026428      ; RM0368 P191
DMA2_S1NDTR     EQU     0x4002642C      ; RM0368 P194
DMA2_S1PAR      EQU     0x40026430      ; RM0368 P195
DMA2_S1M0AR     EQU     0x40026434      ; RM0368 P195
DMA2_S1FCR      EQU     0x4002643C      ; RM0368 P196

; ---- NVIC ----
;      IRQ71(USART6) → ISER2(0xE000E108) bit7         PM0214 P195
;      IRQ71(USART6) → IPR17(0xE000E444) bit31:24     PM0214 P200
NVIC_ISER2      EQU     0xE000E108
NVIC_IPR17      EQU     0xE000E444


;=====================================================================
;  1. 参数
;=====================================================================
SBUS_FRAME_LEN  EQU     25              ; SBUS 一帧固定 25 字节
                                        ; 同时也是 DMA 的 NDTR 初值：
                                        ; 只收 25 个，收满就停，天然对齐
SBUS_HEAD       EQU     0x0F            ; 帧头
SBUS_TAIL       EQU     0x00            ; 帧尾

;=====================================================================
;  2. 内存划分（第 2 步）
;
;     RM0368 P40 §2.3.1：F401xD/E 有 96KB SRAM，起始 0x2000 0000。
;     这些缓冲区全部放 .bss（由 start.s 清零），不占栈空间——
;     这正是你文档"空间陷阱"那段说的做法。
;=====================================================================
;  ★ 这里必须写 NOINIT：
;    armasm 里只有 SPACE 没有初值的段，默认仍会被当成"带初值的数据"，
;    在 Flash 里生成一大片 0 再开机拷到 RAM（map 里显示为 Data RW）。
;    加上 NOINIT 才是真正的 .bss/ZI 段：不占 Flash，由 start.s 的
;    Zero_Bss 循环清零（map 里显示为 Zero RW）。ST 的 STACK 段同理。
                AREA    SBUS_RAM, NOINIT, READWRITE, ALIGN=3

rx_buf          SPACE   SBUS_FRAME_LEN ; ★ DMA 唯一的落点，只有 25 字节
                                        ;   收满 25 个 DMA 就自动停，
                                        ;   不会有"写过头"这回事
                ALIGN   4               ; 25 不是 4 的倍数，补 3 个字节，
                                        ; 让后面的变量仍然按字（4 字节）对齐
channels        SPACE   64              ; 16 通道 × 4 字节，解析结果
frame_ready     SPACE   4               ; ISR 置 1：rx_buf 里有一帧完整的 25 字节
rx_err_cnt      SPACE   4               ; 统计：IDLE 时没凑满 25 字节的次数（残帧）
frame_bad_cnt   SPACE   4               ; 统计：凑满 25 字节但头/尾不对的次数
sbus_flags      SPACE   4               ; 帧标志字节（bit5 丢帧 / bit4 失控保护）
sbus_ch17       SPACE   4               ; 数字通道 17（bit7）
sbus_ch18       SPACE   4               ; 数字通道 18（bit6）
sbus_ok_cnt     SPACE   4               ; 合法帧计数（调试用）
heartbeat       SPACE   4               ; 主循环心跳（调试用）
data_ok         SPACE   4               ; 上电自检结果：1 = .data 拷贝正常


;---------------------------------------------------------------------
; 下面这个变量故意"带初值"，有两个用处：
;   1) 让映像里真的存在 .data 段（RW），start.s 的拷贝代码才有事可做，
;      链接器也才会生成 Image$$RW_IRAM1$$RW$$Base 这类符号；
;   2) 上电自检：在调试器 Watch 窗口看 sbus_magic，
;      等于 0x5A5A1234 说明 .data 从 Flash 拷到 SRAM 成功了；
;      如果是随机值，说明 start.s 里 Copy_Data 那段没跑对。
;---------------------------------------------------------------------
                AREA    SBUS_INIT, DATA, READWRITE, ALIGN=3
sbus_magic      DCD     0x5A5A1234


;=====================================================================
;  3. 代码
;=====================================================================
                AREA    SBUS_CODE, CODE, READONLY, ALIGN=3
                PRESERVE8
                THUMB

                EXPORT  asm_main
                EXPORT  USART6_IRQHandler

;---- 给 debug_uart.s 读取的共享数据 ---------------------------------
;     channels  : 16 通道 × 4 字节（只用低 11 位），由 SBUS_Unpack 写
;     sbus_flags: 标志字节（bit5 丢帧 / bit4 失控保护），由 SBUS_Unpack 写
;     这两个是本文件"对外产出"的结果，谁想读都 IMPORT 即可。
                EXPORT  channels
                EXPORT  sbus_flags

;---- 调试模块（debug_uart.s）提供的三个入口 -------------------------
;     IF 包起来的好处：DEBUG_UART=0 时这几行不参与汇编，
;     整个 main.s 里就不会留下任何对 debug_uart.s 的引用。
                IF      DEBUG_UART <> 0
                IMPORT  Debug_UART_Init
                IMPORT  Debug_OnFrame
                IMPORT  Debug_OnIdle
                ENDIF

;---------------------------------------------------------------------
;  asm_main
;
;  ★ 名字必须是 asm_main，绝对不能叫 main：
;    armlink 只要发现映像里有 main 符号，就会自动
;    "Adding startup reference: __main"，把 C 库启动代码拉进来，
;    在 scatter 分散加载模式下必报 L6915E。
;    （实测：--entry=Reset_Handler 也挡不住这个行为，只有改名有效。）
;
;  顺序不能乱：RCC 时钟 → GPIO 复用 → DMA → USART → NVIC
;  理由：DMA/USART 的寄存器只有在时钟打开后才能写；USART 的 DMAR 位
;        打开后 DMA 请求才有效，所以 DMA 要先配好；NVIC 最后开，
;        避免外设还没初始化完就进中断。
;---------------------------------------------------------------------
asm_main
                BL      Clock_Init              ; 第 3 步：时钟（必须最先）

;---- 上电自检：start.s 有没有把 .data 从 Flash 拷到 SRAM ------------
;     sbus_magic 定义时带初值 0x5A5A1234，属于 .data 段。
;     启动文件里的 Copy_Data 跑对了，这里读出来才是这个值。
;     结果放进 data_ok（1=正常，0=拷贝失败），调试看这一个变量就够。
;
;     ★ 这里必须"真的读一次"：如果 sbus_magic 没人引用，链接器会把
;       整个 SBUS_INIT 段当成无用段删掉（map 里会写
;       "Removing main.o(SBUS_INIT)"），那样 .data 段就不存在了，
;       start.s 里 Image$$RW_IRAM1$$RW$$Base 会变成未定义符号。
;---------------------------------------------------------------------
                LDR     R0, =sbus_magic
                LDR     R1, [R0]
                LDR     R2, =0x5A5A1234
                CMP     R1, R2
                MOVEQ   R3, #1
                MOVNE   R3, #0
                LDR     R0, =data_ok
                STR     R3, [R0]

                BL      GPIO_Init               ; 第 4 步：RCC + GPIO 复用（PC7 / PA2）
                BL      DMA2_Stream1_Init       ;         DMA（要在 USART6 开 DMAR 之前配好）
                BL      USART6_Init             ;         接收：100k 8E2 + IDLE 中断
                IF      DEBUG_UART <> 0
                BL      Debug_UART_Init         ;         调试输出：115200 8N1（debug_uart.s）
                ENDIF
                BL      NVIC_Init               ;         NVIC（最后开，避免半初始化就进中断）

Main_Loop
                BL      SBUS_Task               ; 第 6 步：有数据就解析，没数据立即返回

;--------------- 这里放飞控的其他任务（姿态解算、PID、电机输出…）------
;   例：  BL   IMU_Update
;         BL   PID_Control
;         BL   Motor_Output
;---------------------------------------------------------------------
                LDR     R0, =heartbeat          ; 心跳 +1，调试器里看它在涨
                LDR     R1, [R0]                ; 就说明主循环没卡死
                ADD     R1, R1, #1
                STR     R1, [R0]

                B       Main_Loop


;=====================================================================
;  Clock_Init —— 把系统时钟从复位默认的 HSI 16MHz 提到 84MHz
;
;  为什么要配：RM0368 P46 §3.4.1 明确写着
;      "After reset, the CPU clock frequency is 16 MHz and 0 wait state"
;  也就是说复位后跑的是内部 HSI 16MHz，不是 8MHz，也不是 72/84MHz。
;  不配 PLL 的话 USARTDIV 全错，SBUS 一定收不对。
;
;  目标：HCLK = 84MHz，PCLK1 = 42MHz，PCLK2 = 84MHz
;        HSI 16MHz ÷ PLLM(16) × PLLN(336) ÷ PLLP(4) = 84MHz
;        VCO = 16/16×336 = 336MHz，落在 192~432MHz 合法区间（P106）
;        PLLQ = 7 → 336/7 = 48MHz（给 USB 用，本例不用，但必须写合法值）
;
;  顺序（RM0368 P46 "Increasing the CPU frequency" 的官方步骤）：
;      ① 先加 Flash 等待周期 → ② 再切时钟源
;    多一级：切之前先把 APB1 分频改成 /2，否则 PCLK1 会短时超过 42MHz。
;=====================================================================
Clock_Init
;---- ① 打开 PWR 时钟（改 VOS 必须先开这个时钟）---------------------
                LDR     R0, =RCC_APB1ENR
                LDR     R1, [R0]
                ORR     R1, R1, #0x10000000     ; bit28 PWREN（RM0368 P120）
                STR     R1, [R0]

;---- ② VOS = Scale 2（RM0368 P87，bits15:14 = 10）------------------
;     84MHz 必须用 Scale2；Scale3 最高只到 60MHz（RM0368 P46）
                LDR     R0, =PWR_CR
                LDR     R1, [R0]
                BIC     R1, R1, #0x0000C000
                ORR     R1, R1, #0x00008000
                STR     R1, [R0]

;---- ③ Flash 等待周期 = 2WS，并开预取和 I/D Cache ------------------
;     RM0368 P46 Table 6：2.7~3.6V 下 60<HCLK≤84MHz 需要 2WS
;     RM0368 P60：LATENCY=bit2:0，PRFTEN=bit8，ICEN=bit9，DCEN=bit10
                LDR     R0, =FLASH_ACR
                LDR     R1, [R0]
                ORR     R1, R1, #0x00000700     ; 预取 + I-Cache + D-Cache
                ORR     R1, R1, #0x00000002     ; LATENCY = 2
                STR     R1, [R0]
                LDR     R1, [R0]                ; 回读，确认已生效再往下走

;---- ④ 配置 PLL（RM0368 P105）--------------------------------------
;     PLLCFGR = PLLQ(7)<<24 | PLLSRC(0=HSI)<<22 | PLLP(01=÷4)<<16
;               | PLLN(336)<<6 | PLLM(16)
;             = 0x07015410
                LDR     R0, =RCC_PLLCFGR
                LDR     R1, =0x07015410
                STR     R1, [R0]

;---- ⑤ 使能 PLL，等 PLLRDY（RCC_CR bit24=PLLON，bit25=PLLRDY）------
                LDR     R0, =RCC_CR
                LDR     R1, [R0]
                ORR     R1, R1, #0x01000000
                STR     R1, [R0]
Wait_PLL
                LDR     R1, [R0]
                TST     R1, #0x02000000
                BEQ     Wait_PLL

;---- ⑥ 先把 APB1 改成 ÷2（RM0368 P108，PPRE1=bit12:10）-------------
;     APB1 最高 42MHz（P108 原文 Caution），84/2 = 42 刚好
                LDR     R0, =RCC_CFGR
                LDR     R1, [R0]
                BIC     R1, R1, #0x00001C00     ; 清 PPRE1[2:0]
                ORR     R1, R1, #0x00001000     ; 100 = AHB/2
                STR     R1, [R0]

;---- ⑦ 切换系统时钟到 PLL：SW = 10，再等 SWS 变成 10 --------------
                LDR     R1, [R0]
                BIC     R1, R1, #0x00000003     ; 清 SW[1:0]
                ORR     R1, R1, #0x00000002     ; SW = 10 → PLL
                STR     R1, [R0]
Wait_SW
                LDR     R1, [R0]
                AND     R1, R1, #0x0000000C     ; SWS[3:2]（P109）
                CMP     R1, #0x00000008         ; 10<<2，表示确实切过去了
                BNE     Wait_SW
                DSB
                ISB
                BX      LR

;---------------------------------------------------------------------
;  如果要用外部晶振（HSE），只改 ④ 这一处：
;    8MHz  晶振(Nucleo 板载 X3)：PLLM=8  → PLLCFGR = 0x07415408
;                                 （PLLQ=7, PLLSRC=1, PLLP=÷4, PLLN=336, PLLM=8）
;    25MHz 晶振(你们 .ioc 里写的是 25MHz)：PLLM=25 → PLLCFGR = 0x07415419
;    并且要在 ⑤ 之前先打开 HSE 并等 HSERDY：
;        LDR R0,=RCC_CR
;        LDR R1,[R0]
;        ORR R1,R1,#0x00010000      ; HSEON = bit16（RM0368 P104）
;        STR R1,[R0]
;    HSE_Ready
;        LDR R1,[R0]
;        TST R1,#0x00020000         ; HSERDY = bit17
;        BEQ HSE_Ready
;  为什么建议最终用 HSE：DS9716 P80 HSI 精度表——25℃ 时 ±1%，
;  -10~85℃ 时 ±4%。100kbps 的 8E2 一帧 12 位，累计误差超过约 4% 就会
;  采错位；实验室常温下 ±1% 能用，真机上天建议换晶振。
;  注意：换 HSE 后 PCLK1 仍是 42MHz，BRR 不用改。
;---------------------------------------------------------------------


;=====================================================================
;  GPIO_Init —— PC7 复用为 USART6_RX
;
;  DS9716 P45 Table 9 "Alternate function mapping"：
;      PC6 = USART6_TX (AF08),  PC7 = USART6_RX (AF08)
;      （PA2 = USART2_TX 的配置在 debug_uart.s 里，本文件不碰 GPIOA）
;
;  ★ PC7 的复用号在 AFRL 的最高 4 位：AFRL[31:28]
;    （AFRL 管每个端口的 0~7 号引脚，每引脚 4 位，PC7 正好是最后一个）
;=====================================================================
GPIO_Init
                LDR     R0, =RCC_AHB1ENR
                LDR     R1, [R0]
                ORR     R1, R1, #0x00000004     ; bit2  GPIOCEN（RM0368 P118）
                ORR     R1, R1, #0x00400000     ; bit22 DMA2EN （RM0368 P118）
                STR     R1, [R0]

;---- PC7 = 复用功能：MODER[15:14] = 10（RM0368 P158）---------------
                LDR     R0, =GPIOC_MODER
                LDR     R1, [R0]
                LDR     R2, =0x0000C000
                BIC     R1, R1, R2
                ORR     R1, R1, #0x00008000
                STR     R1, [R0]

;---- PC7 = 高速：OSPEEDR[15:14] = 11（RM0368 P159）-----------------
                LDR     R0, =GPIOC_OSPEEDR
                LDR     R1, [R0]
                LDR     R2, =0x0000C000
                BIC     R1, R1, R2
                ORR     R1, R1, R2
                STR     R1, [R0]

;---- PC7 = 上拉：PUPDR[15:14] = 01（RM0368 P160）-------------------
;     反相后的 SBUS 空闲是高电平，上拉可保证接收机没插时线路不被拉低
                LDR     R0, =GPIOC_PUPDR
                LDR     R1, [R0]
                LDR     R2, =0x0000C000
                BIC     R1, R1, R2
                ORR     R1, R1, #0x00004000
                STR     R1, [R0]

;---- PC7 = AF8：AFRL[31:28] = 1000（RM0368 P162）------------------
                LDR     R0, =GPIOC_AFRL
                LDR     R1, [R0]
                LDR     R2, =0xF0000000
                BIC     R1, R1, R2
                ORR     R1, R1, #0x80000000
                STR     R1, [R0]
                BX      LR


;=====================================================================
;  USART6_Init —— 100000bps / 8 数据位 / 偶校验 / 2 停止位（8E2）
;
;  ★ 换到 USART6 后最容易踩的一脚：USART6 挂在 **APB2** 上，
;    而 USART2 挂在 APB1 上，两者时钟不同！
;        USART2：PCLK1 = 42MHz  →  BRR = 0x1A4
;        USART6：PCLK2 = 84MHz  →  BRR = 0x348   ← 直接用 0x1A4 会慢一倍
;
;  BRR 计算（RM0368 P551，过采样 16 时 USARTDIV = fCK / (16 × 波特率)）：
;      USARTDIV = 84 000 000 / (16 × 100 000) = 52.5
;      BRR[15:4] = 整数部分 52 = 0x34
;      BRR[3:0]  = 小数部分 0.5 × 16 = 8
;      → BRR = 0x348
;
;  ★ 顺带纠正你文档里的一个数字：
;      "16MHz 下 BRR 正好是 0x0A" 是不对的。16MHz 时 USARTDIV = 10.0，
;      BRR = 10<<4 = 0xA0。写成 0x0A 等于 USARTDIV = 0.625，
;      实际波特率会变成 1.6Mbps（快 16 倍），SBUS 必然收不到。
;=====================================================================
USART6_Init
                LDR     R0, =RCC_APB2ENR
                LDR     R1, [R0]
                ORR     R1, R1, #0x00000020     ; bit5 USART6EN（RM0368 P123）
                STR     R1, [R0]

;---- 先关 UE，保证 BRR/CR2/CR3 可以安全写入 ------------------------
                LDR     R0, =USART6_CR1
                MOV     R1, #0
                STR     R1, [R0]

;---- BRR = 0x348 ---------------------------------------------------
                LDR     R0, =USART6_BRR
                LDR     R1, =0x00000348
                STR     R1, [R0]

;---- CR2：STOP[1:0] = 10 → 2 个停止位（RM0368 P554）---------------
                LDR     R0, =USART6_CR2
                MOV     R1, #0x00002000
                STR     R1, [R0]

;---- CR3：DMAR = 1，允许 USART 向 DMA 发接收请求（RM0368 P556）----
                LDR     R0, =USART6_CR3
                MOV     R1, #0x00000040
                STR     R1, [R0]

;---- CR1：UE | PCE | IDLEIE | RE（RM0368 P552~P553）--------------
;     bit13 UE=1      串口使能
;     bit12 M=0       8 数据位
;     bit10 PCE=1     偶校验（PS=0 即偶校验）
;     bit4  IDLEIE=1  空闲中断使能 ← 这是帧结束的通知机制
;     bit2  RE=1      接收使能
;     = 0x2000 | 0x0400 | 0x0010 | 0x0004 = 0x2414
                LDR     R0, =USART6_CR1
                LDR     R1, =0x00002414
                STR     R1, [R0]
                BX      LR


;=====================================================================
;  DMA2_Stream1_Init —— USART6_RX 的 DMA 通道
;
;  映射关系：RM0368 P171 Table 29 "DMA2 request mapping"
;            Channel 5 那一行，Stream 1 列 = USART6_RX
;            （Stream 2 / Channel 5 也可以，Stream 6、7 是 USART6_TX）
;
;  ★ 注意 DMA 控制器换了：USART2_RX 在 DMA1，USART6_RX 在 **DMA2**。
;    DMA2 的基地址是 0x4002 6400（RM0368 P38），Stream1 偏移 0x28。
;
;  ★ 这一版用【普通模式】而不是循环模式：
;      NDTR = 25，收满 25 个字节后 DMA 自动把 EN 清零并停下来
;      （RM0368 P176：普通模式下 "the stream is disabled"）。
;      所以 rx_buf 永远只可能被写 25 个字节，不会越界、不会绕回。
;      下一次再收，由 DMA_Rearm 把 NDTR 重新装成 25 并使能。
;=====================================================================
DMA2_Stream1_Init
;---- 先关流，才能改配置（SxCR 的多数位要求 EN=0）------------------
                LDR     R0, =DMA2_S1CR
                MOV     R1, #0
                STR     R1, [R0]
Wait_EN0
                LDR     R1, [R0]
                TST     R1, #0x00000001         ; EN 真的变 0 了吗
                BNE     Wait_EN0

;---- 清掉 Stream1 的全部中断标志（RM0368 P188/P190）---------------
;     流0~3 在 LISR/LIFCR，流1 占 bit6(CFEIF) 8 9 10 11
                LDR     R0, =DMA2_LIFCR
                LDR     R1, =0x00000F40
                STR     R1, [R0]

;---- 外设地址 = &USART6_DR（RM0368 P195）--------------------------
                LDR     R0, =DMA2_S1PAR
                LDR     R1, =0x40011404
                STR     R1, [R0]

;---- 内存地址 = rx_buf（只有 25 字节）-----------------------------
                LDR     R0, =DMA2_S1M0AR
                LDR     R1, =rx_buf
                STR     R1, [R0]

;---- 传输个数 = 25（RM0368 P194）----------------------------------
                LDR     R0, =DMA2_S1NDTR
                MOV     R1, #SBUS_FRAME_LEN
                STR     R1, [R0]

;---- FIFO 控制 = 0：直接模式，不分频不打包（RM0368 P196）----------
                LDR     R0, =DMA2_S1FCR
                MOV     R1, #0
                STR     R1, [R0]

;---- 配置寄存器（RM0368 P191~P193）--------------------------------
;     CHSEL[2:0] = 101 → 通道 5        (bit27:25)  → 0x0A000000
;     MBURST/PBURST = 00 单次传输
;     PL[1:0]   = 00 低优先级
;     MSIZE/PSIZE = 00 字节
;     MINC      = 1  内存地址递增      (bit10)     → 0x00000400
;     PINC      = 0  外设地址固定（永远是 DR）
;     CIRC      = 0  普通模式（不是循环！）          ← 和上一版的唯一区别
;     DIR[1:0]  = 00 外设→内存         (bit7:6)
;     EN        = 1  使能              (bit0)      → 0x00000001
                LDR     R0, =DMA2_S1CR
                LDR     R1, =0x0A000401
                STR     R1, [R0]
                BX      LR


;=====================================================================
;  DMA_Rearm —— 把 DMA 重新装填成"再收 25 字节"
;
;  什么时候调用：
;    · 中断里发现残帧（NDTR != 0），立刻重装准备收下一帧；
;    · 主循环解析完一帧之后，重装准备收下一帧。
;
;  为什么每次都要"先关 EN、等它真变 0、再写 NDTR"：
;    SxNDTR 只有在 EN=0 时才允许写（RM0368 P191 "protected ... only if EN is '0'"），
;    边收边写会被硬件忽略，表现就是"怎么都不工作"。
;
;  顺带把 RXNE/ORE/IDLE 清掉（读 SR → 读 DR）：
;    上一帧残留下来的字节如果不清，重装之后 DMA 会立刻把它搬进 buf[0]，
;    数据就错位了。这是单缓冲方案里很关键的一步。
;
;  入参：无；出参：无；破坏 R0~R3
;=====================================================================
DMA_Rearm
                LDR     R0, =DMA2_S1CR
                LDR     R1, [R0]
                BIC     R1, R1, #0x00000001     ; EN = 0
                STR     R1, [R0]
DR_WaitEN0
                LDR     R1, [R0]
                TST     R1, #0x00000001
                BNE     DR_WaitEN0

;---- 清 USART 的接收标志（读 SR 再读 DR）--------------------------
                LDR     R0, =USART6_SR
                LDR     R1, [R0]
                LDR     R2, [R0, #4]            ; 读 DR：清 RXNE/ORE/IDLE

;---- 清 DMA 中断标志 ----------------------------------------------
                LDR     R0, =DMA2_LIFCR
                LDR     R1, =0x00000F40
                STR     R1, [R0]

;---- NDTR 重新装成 25 ---------------------------------------------
                LDR     R0, =DMA2_S1NDTR
                MOV     R1, #SBUS_FRAME_LEN
                STR     R1, [R0]

;---- 重新使能 ------------------------------------------------------
                LDR     R0, =DMA2_S1CR
                LDR     R1, [R0]
                ORR     R1, R1, #0x00000001
                STR     R1, [R0]
                BX      LR


;=====================================================================
;  NVIC_Init —— 使能 USART6 中断（IRQ71）
;  USART6 在向量表里的地址 = 0x40 + 4×71 = 0x15C（RM0368 P205 Table 38）
;  IRQ71 属于 64~95 组 → ISER2 的 bit(71-64)=7（PM0214 P195）
;  优先级在 IPR17（71÷4=17，余 3）的 bit31:24（PM0214 P200）
;=====================================================================
NVIC_Init
                LDR     R0, =NVIC_IPR17             ; 优先级寄存器（PM0214 P200）
                LDR     R1, [R0]
                LDR     R2, =0xFF000000
                BIC     R1, R1, R2                  ; IRQ71 占 bit31:24
                ORR     R1, R1, #0x20000000         ; 抢占优先级 0x20
                STR     R1, [R0]

                LDR     R0, =NVIC_ISER2
                MOV     R1, #0x00000080             ; bit7 → IRQ71
                STR     R1, [R0]
                BX      LR


;=====================================================================
;  USART6_IRQHandler —— 第 5 步：中断里判"满没满"
;
;  和上一版（算长度）不同，这一版只需要回答一个问题：
;      这一波数据，是不是正好 25 个字节？
;
;      NDTR == 0  → 是。25 个字节已经在 rx_buf 里躺好了，置标志交给主循环。
;      NDTR != 0  → 不是。说明这帧被截断了（干扰/丢字节），
;                   丢掉它，把 DMA 重装成"再收 25 个"，等下一帧。
;
;  三种细节：
;    ① 清 IDLE 只能"读 SR → 读 DR"（RM0368 P549，F4 没有 ICR 寄存器）。
;       读 DR 不会抢 DMA 的数据：IDLE 置位时总线已经安静了至少一个字节时间。
;    ② 如果主循环还没把上一帧取走（frame_ready 仍为 1），这一帧直接不要，
;       否则会把主循环正在读的 rx_buf 覆盖掉。
;    ③ 残帧重装要和主循环共用 DMA_Rearm，避免两处逻辑不一致。
;
;  ★ 只用 R0~R3：Cortex-M4 进中断时硬件自动压栈 R0~R3/R12/LR/PC/xPSR，
;    这样连 PUSH/POP 都省了。唯一例外是调用 DMA_Rearm 要保护一下 LR。
;=====================================================================
USART6_IRQHandler
                LDR     R0, =USART6_SR
                LDR     R1, [R0]
                TST     R1, #0x00000010             ; bit4 = IDLE ?
                BEQ     USART6_ISR_Exit             ; 不是就走人

                LDR     R2, [R0, #4]                ; 读 DR：完成 SR→DR 清除序列
                                                    ; （顺带清 RXNE/ORE）

;---- 上一帧还没被主循环取走？那这一帧就不要了 ----------------------
                LDR     R0, =frame_ready
                LDR     R1, [R0]
                CMP     R1, #0
                BNE     USART6_ISR_Exit

;---- 核心判断：NDTR 是不是 0 ---------------------------------------
                LDR     R0, =DMA2_S1NDTR
                LDR     R1, [R0]
                CMP     R1, #0
                BNE     ISR_ShortFrame              ; 没满 25 个 → 残帧

;---- 满帧：只置标志，绝不在这里解析 --------------------------------
                LDR     R0, =frame_ready
                MOV     R1, #1
                STR     R1, [R0]
                B       USART6_ISR_Exit

;---- 残帧：记账 + 重装，等下一帧 -----------------------------------
ISR_ShortFrame
                LDR     R0, =rx_err_cnt
                LDR     R1, [R0]
                ADD     R1, R1, #1
                STR     R1, [R0]

                PUSH    {R4, LR}                    ; 8 字节，保持栈对齐
                BL      DMA_Rearm
                POP     {R4, LR}

USART6_ISR_Exit
                BX      LR


;=====================================================================
;  SBUS_Task —— 第 6 步：主循环里解析
;
;  总共四步：
;    ① 看 frame_ready；没有就立刻返回，不拖累飞控
;    ② 校验帧头 0x0F / 帧尾 0x00（DMA 只负责搬字节，不负责判断对错）
;    ③ 合法 → 位拼接出 16 通道 →（如果编了调试）交给 Debug_OnFrame
;       不合法 → 记一笔 frame_bad_cnt，丢掉
;    ④ 不管对错，最后都要 DMA_Rearm，让 DMA 重新收下一帧
;
;  ★ 为什么"先重装、后清标志"：
;    如果先清 frame_ready 再重装，这中间 DMA 还是停的，一旦来了新的 IDLE，
;    中断会把标志又置 1；等我们重装完，主循环就会把同一帧解析两次。
;    反过来先重装（DMA 开始工作）再清标志，就不会有这个问题。
;
;  ★ 调试输出只有两个挂载点（都用 IF DEBUG_UART 包着）：
;      Debug_OnFrame —— 解析出一帧合法数据时
;      Debug_OnIdle  —— 这一轮没解析到数据时
;    把 DEBUG_UART 改成 0，这两处就完全不产生代码，
;    本文件与 debug_uart.s 之间一个符号引用都不剩。
;=====================================================================
SBUS_Task
                PUSH    {R4-R6, LR}

;---- ① 取标志 ------------------------------------------------------
                CPSID   I                           ; 关中断，保证读到的是完整状态
                LDR     R0, =frame_ready
                LDR     R1, [R0]
                CPSIE   I
                CMP     R1, #0
                BEQ     ST_Idle                     ; 没有新帧

                LDR     R4, =rx_buf                 ; R4 = 这 25 字节的首地址

;---- ② 校验帧头帧尾 ------------------------------------------------
;     帧头不对：说明这一波数据根本不是从帧头开始的（干扰/错位）
;     帧尾不对：说明中间丢了字节，长度虽然凑够 25 但内容是错的
                LDRB    R5, [R4]
                CMP     R5, #SBUS_HEAD
                BNE     ST_Bad
                LDRB    R5, [R4, #24]
                CMP     R5, #SBUS_TAIL
                BNE     ST_Bad

;---- ③ 解析出 16 通道 ---------------------------------------------
                MOV     R0, R4
                BL      SBUS_Unpack                 ; 11-bit 位拼接 → channels[]

;---- ③' 可选：把这一帧发给电脑 -----------------------------------
                IF      DEBUG_UART <> 0
                BL      Debug_OnFrame
                ENDIF
                B       ST_Reload

ST_Bad
                LDR     R0, =frame_bad_cnt
                LDR     R1, [R0]
                ADD     R1, R1, #1
                STR     R1, [R0]

;---- ④ 重装 DMA，然后清标志 ---------------------------------------
ST_Reload
                BL      DMA_Rearm
                LDR     R0, =frame_ready
                MOV     R1, #0
                STR     R1, [R0]

                POP     {R4-R6, LR}
                BX      LR

;---- ⑤ 这一轮没有新帧 ---------------------------------------------
;     可选：交给调试模块做心跳计时（长时间没数据就发"我还活着"）
ST_Idle
                IF      DEBUG_UART <> 0
                BL      Debug_OnIdle
                ENDIF
                POP     {R4-R6, LR}
                BX      LR


;=====================================================================
;  SBUS_Unpack —— 11-bit 位拼接，把 22 字节还原成 16 个通道
;
;  入参： R0 = 帧首地址（frame[0]=0x0F）
;
;  原理：16 个通道低位在前、连续打包，第 n 个通道的起始位 = n×11。
;        所以对第 n 通道：
;            byte_index = (n×11) >> 3
;            bit_offset = (n×11) & 7
;            取 frame[1+byte_index] 起的 3 个字节拼成 24 位小端值，
;            右移 bit_offset 位，再取低 11 位即可。
;        3 个字节够用，因为 bit_offset + 11 ≤ 18 < 24。
;
;  以 CH1 为例：n=0 → byte_index=0, bit_offset=0
;             value = frame[1] | frame[2]<<8 | frame[3]<<16
;             取低 11 位 = frame[1] | (frame[2]&0x07)<<8
;             与你文档里的 CH1 公式完全一致。
;
;  出参： channels[0..15]，并更新 flags / ch17 / ch18 / 计数
;=====================================================================
SBUS_Unpack
                MOV     R1, #0                      ; bitpos = 0
                LDR     R2, =channels               ; 输出指针
                MOV     R3, #16                     ; 还有 16 个通道
SU_Loop
                MOV     R4, R1, LSR #3              ; byte_index
                AND     R5, R1, #7                  ; bit_offset
                ADD     R6, R0, R4                  ; &frame[byte_index]
                LDRB    R7, [R6, #1]                ; frame[1+byte_index]
                LDRB    R8, [R6, #2]                ; 下一个字节
                LDRB    R9, [R6, #3]                ; 再下一个
                ORR     R7, R7, R8, LSL #8          ; 拼成 24 位小端值
                ORR     R7, R7, R9, LSL #16
                MOV     R7, R7, LSR R5              ; 右移 bit_offset 位
                MOV     R7, R7, LSL #21             ; 取低 11 位：
                MOV     R7, R7, LSR #21             ;   左移 21 再右移 21
                STR     R7, [R2], #4                ; channels[n] = value
                ADD     R1, R1, #11                 ; 下一个通道起始位
                SUBS    R3, R3, #1
                BNE     SU_Loop

;---- 标志字节 frame[23]（你文档"1 字节标志位"那一节）---------------
;     bit7 = CH17   bit6 = CH18   bit5 = 丢帧   bit4 = 失控保护
                LDRB    R4, [R0, #23]
                LDR     R5, =sbus_flags
                STR     R4, [R5]

                AND     R6, R4, #0x80               ; CH17
                LDR     R5, =sbus_ch17
                STR     R6, [R5]
                AND     R6, R4, #0x40               ; CH18
                LDR     R5, =sbus_ch18
                STR     R6, [R5]

;---- 合法帧计数 ----------------------------------------------------
                LDR     R5, =sbus_ok_cnt
                LDR     R6, [R5]
                ADD     R6, R6, #1
                STR     R6, [R5]
                BX      LR


;=====================================================================
;  本文件到此结束 —— 只剩"收 + 解析"。
;
;  调试输出（USART2 / 40 字节上传帧 / 心跳）全部在 debug_uart.s：
;    Debug_UART_Init   PA2 复用 + USART2 115200 8N1
;    Debug_OnFrame     收到有效帧 → 清零计时 + 发送 16 通道
;    Debug_OnIdle      没收到帧   → 计时满约 0.25s 发一帧"无数据"心跳
;
;  剔除方法（两步）：
;    1) 本文件顶部 DEBUG_UART EQU 1 改成 0；
;    2) 把 debug_uart.s 从 Keil 工程里 Remove。
;  剔完之后再汇编，main.s 里不会出现任何 Debug_ 符号。
;=====================================================================

                END
