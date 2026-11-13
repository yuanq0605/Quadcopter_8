;=====================================================================
;  start.s   ——   STM32F401RE 汇编启动文件（Keil MDK / armasm 语法）
;
;  职责（对应你文档"流程梳理"第 1 步）：
;    1) 建立中断向量表：第 0 个字 = 栈顶初值，第 1 个字 = 复位入口，
;       之后按中断号顺序排列各个异常/中断服务函数的入口地址
;    2) 把 .data 段（有初值的全局变量）从 Flash 拷贝到 SRAM
;    3) 把 .bss / ZI 段（无初值的全局变量）在 SRAM 里清零
;    4) 设置 VTOR，跳到 main.s 的 asm_main
;
;  手册引用：
;    RM0368 Rev6  = STM32F401xB/C xD/E Reference manual
;    PM0214 Rev4  = STM32F3/F4 系列 Cortex-M4 内核编程手册
;  页码都是手册印刷页码，可直接翻到该页核对。
;=====================================================================

;---------------------------------------------------------------------
; 一、栈（Stack）
;    Cortex-M4 的栈是"满递减"：SP 初值 = 栈区最高地址，压栈时 SP 先减。
;    __initial_sp 这个标号写在 SPACE 之后，正好落在栈区末尾（最高地址）。
;---------------------------------------------------------------------
Stack_Size      EQU     0x00000800              ; 2 KB

                AREA    STACK, NOINIT, READWRITE, ALIGN=3
Stack_Mem       SPACE   Stack_Size
__initial_sp                                    ; ← 这就是向量表第 0 个字

;---------------------------------------------------------------------
; 二、中断向量表
;    PM0214 P39  Figure 11：向量表结构
;      0x00 : 初始 SP
;      0x04 : Reset
;      0x08 : NMI         0x0C : HardFault
;      0x10 : MemManage   0x14 : BusFault    0x18 : UsageFault
;      0x2C : SVCall      0x38 : PendSV      0x3C : SysTick
;      0x40 : IRQ0 ...    每个 IRQ 占 4 字节
;    公式：  IRQn 的向量地址 = 0x40 + 4 × n
;            USART2 是 IRQ38  →  0x40 + 4×38 = 0xD8
;            （RM0368 P204  Table 38 给出了每个 IRQ 的编号和地址）
;
;    注意：这里填的必须是"函数标号"，且该函数必须存在于工程里，
;          否则链接报 undefined symbol。没实现的统一指向 Default_Handler。
;---------------------------------------------------------------------
                AREA    RESET, DATA, READONLY, ALIGN=4
                EXPORT  __Vectors
                EXPORT  __Vectors_End
                EXPORT  __Vectors_Size

__Vectors       DCD     __initial_sp                    ; 0x00 初始 SP
                DCD     Reset_Handler                   ; 0x04 Reset
                DCD     NMI_Handler                     ; 0x08
                DCD     HardFault_Handler               ; 0x0C
                DCD     MemManage_Handler               ; 0x10
                DCD     BusFault_Handler                ; 0x14
                DCD     UsageFault_Handler              ; 0x18
                DCD     0                               ; 0x1C 保留
                DCD     0                               ; 0x20 保留
                DCD     0                               ; 0x24 保留
                DCD     0                               ; 0x28 保留
                DCD     SVC_Handler                     ; 0x2C
                DCD     DebugMon_Handler                ; 0x30
                DCD     0                               ; 0x34 保留
                DCD     PendSV_Handler                  ; 0x38
                DCD     SysTick_Handler                 ; 0x3C
;---------------------- 外部中断 IRQ0 ~ IRQ84 ------------------------
                DCD     Default_Handler                 ; 0x40 IRQ0  WWDG
                DCD     Default_Handler                 ; 0x44 IRQ1  PVD(EXTI16)
                DCD     Default_Handler                 ; 0x48 IRQ2  TAMP_STAMP(EXTI21)
                DCD     Default_Handler                 ; 0x4C IRQ3  RTC_WKUP(EXTI22)
                DCD     Default_Handler                 ; 0x50 IRQ4  FLASH
                DCD     Default_Handler                 ; 0x54 IRQ5  RCC
                DCD     Default_Handler                 ; 0x58 IRQ6  EXTI0
                DCD     Default_Handler                 ; 0x5C IRQ7  EXTI1
                DCD     Default_Handler                 ; 0x60 IRQ8  EXTI2
                DCD     Default_Handler                 ; 0x64 IRQ9  EXTI3
                DCD     Default_Handler                 ; 0x68 IRQ10 EXTI4
                DCD     Default_Handler                 ; 0x6C IRQ11 DMA1_Stream0
                DCD     Default_Handler                 ; 0x70 IRQ12 DMA1_Stream1
                DCD     Default_Handler                 ; 0x74 IRQ13 DMA1_Stream2
                DCD     Default_Handler                 ; 0x78 IRQ14 DMA1_Stream3
                DCD     Default_Handler                 ; 0x7C IRQ15 DMA1_Stream4
                DCD     Default_Handler                 ; 0x80 IRQ16 DMA1_Stream5
                DCD     Default_Handler                 ; 0x84 IRQ17 DMA1_Stream6
                DCD     Default_Handler                 ; 0x88 IRQ18 ADC
                DCD     0                               ; 0x8C IRQ19 保留
                DCD     0                               ; 0x90 IRQ20 保留
                DCD     0                               ; 0x94 IRQ21 保留
                DCD     0                               ; 0x98 IRQ22 保留
                DCD     Default_Handler                 ; 0x9C IRQ23 EXTI9_5
                DCD     Default_Handler                 ; 0xA0 IRQ24 TIM1_BRK_TIM9
                DCD     Default_Handler                 ; 0xA4 IRQ25 TIM1_UP_TIM10
                DCD     Default_Handler                 ; 0xA8 IRQ26 TIM1_TRG_COM_TIM11
                DCD     Default_Handler                 ; 0xAC IRQ27 TIM1_CC
                DCD     Default_Handler                 ; 0xB0 IRQ28 TIM2
                DCD     Default_Handler                 ; 0xB4 IRQ29 TIM3
                DCD     Default_Handler                 ; 0xB8 IRQ30 TIM4
                DCD     Default_Handler                 ; 0xBC IRQ31 I2C1_EV
                DCD     Default_Handler                 ; 0xC0 IRQ32 I2C1_ER
                DCD     Default_Handler                 ; 0xC4 IRQ33 I2C2_EV
                DCD     Default_Handler                 ; 0xC8 IRQ34 I2C2_ER
                DCD     Default_Handler                 ; 0xCC IRQ35 SPI1
                DCD     Default_Handler                 ; 0xD0 IRQ36 SPI2
                DCD     Default_Handler                 ; 0xD4 IRQ37 USART1
                DCD     USART2_IRQHandler               ; 0xD8 IRQ38 USART2（现在只做发送，不用中断）
                DCD     0                               ; 0xDC IRQ39 保留
                DCD     Default_Handler                 ; 0xE0 IRQ40 EXTI15_10
                DCD     Default_Handler                 ; 0xE4 IRQ41 RTC_Alarm(EXTI17)
                DCD     Default_Handler                 ; 0xE8 IRQ42 OTG_FS_WKUP(EXTI18)
                DCD     0                               ; 0xEC IRQ43 保留
                DCD     0                               ; 0xF0 IRQ44 保留
                DCD     0                               ; 0xF4 IRQ45 保留
                DCD     0                               ; 0xF8 IRQ46 保留
                DCD     Default_Handler                 ; 0xFC IRQ47 DMA1_Stream7
                DCD     0                               ; 0x100 IRQ48 保留
                DCD     Default_Handler                 ; 0x104 IRQ49 SDIO
                DCD     Default_Handler                 ; 0x108 IRQ50 TIM5
                DCD     Default_Handler                 ; 0x10C IRQ51 SPI3
                DCD     0                               ; 0x110 IRQ52 保留
                DCD     0                               ; 0x114 IRQ53 保留
                DCD     0                               ; 0x118 IRQ54 保留
                DCD     0                               ; 0x11C IRQ55 保留
                DCD     Default_Handler                 ; 0x120 IRQ56 DMA2_Stream0
                DCD     Default_Handler                 ; 0x124 IRQ57 DMA2_Stream1
                DCD     Default_Handler                 ; 0x128 IRQ58 DMA2_Stream2
                DCD     Default_Handler                 ; 0x12C IRQ59 DMA2_Stream3
                DCD     Default_Handler                 ; 0x130 IRQ60 DMA2_Stream4
                DCD     0                               ; 0x134 IRQ61 保留
                DCD     0                               ; 0x138 IRQ62 保留
                DCD     0                               ; 0x13C IRQ63 保留
                DCD     0                               ; 0x140 IRQ64 保留
                DCD     0                               ; 0x144 IRQ65 保留
                DCD     0                               ; 0x148 IRQ66 保留
                DCD     Default_Handler                 ; 0x14C IRQ67 OTG_FS
                DCD     Default_Handler                 ; 0x150 IRQ68 DMA2_Stream5
                DCD     Default_Handler                 ; 0x154 IRQ69 DMA2_Stream6
                DCD     Default_Handler                 ; 0x158 IRQ70 DMA2_Stream7
                DCD     USART6_IRQHandler               ; 0x15C IRQ71 USART6 ★SBUS 接收用这个
                DCD     Default_Handler                 ; 0x160 IRQ72 I2C3_EV
                DCD     Default_Handler                 ; 0x164 IRQ73 I2C3_ER
                DCD     0                               ; 0x168 IRQ74 保留
                DCD     0                               ; 0x16C IRQ75 保留
                DCD     0                               ; 0x170 IRQ76 保留
                DCD     0                               ; 0x174 IRQ77 保留
                DCD     0                               ; 0x178 IRQ78 保留
                DCD     0                               ; 0x17C IRQ79 保留
                DCD     0                               ; 0x180 IRQ80 保留
                DCD     Default_Handler                 ; 0x184 IRQ81 FPU
                DCD     0                               ; 0x188 IRQ82 保留
                DCD     0                               ; 0x18C IRQ83 保留
                DCD     Default_Handler                 ; 0x190 IRQ84 SPI4
__Vectors_End

__Vectors_Size  EQU     __Vectors_End - __Vectors

;---------------------------------------------------------------------
; 三、复位入口
;    PM0214 P41："On reset, the processor ... loads the PC with the
;    reset vector"；RM0368 P41 §2.4 也说明了 BOOT0=0 时从 Flash 启动。
;---------------------------------------------------------------------
                AREA    |.text|, CODE, READONLY, ALIGN=4
                PRESERVE8
                THUMB

;---------------------------------------------------------------------
; ENTRY：告诉链接器"入口是 Reset_Handler"。
;   写上它可以让映像的入口点明确，配合工程里的 --entry=Reset_Handler
;   双保险。（注意：光靠它并不能阻止链接器去拉 C 库，真正的原因见
;   下面 IMPORT asm_main 上面的说明。）
;---------------------------------------------------------------------
                ENTRY

                EXPORT  Reset_Handler
;---------------------------------------------------------------------
; ★ 入口函数叫 asm_main，不叫 main —— 这是有原因的，别改回去！
;
;   ARMCC/armlink 有一个"贴心"行为：只要映像里存在名为 main 的符号，
;   链接器就会自动 "Adding startup reference: __main"，把 C 库的
;   启动代码（__rt_entry / __scatterload / 半主机 __user_initial_stackheap）
;   一起拉进来。而半主机版的 __user_initial_stackheap 在 scatter 分散
;   加载模式下无法确定堆区，于是报：
;     L6915E: Library reports error: The semihosting
;     __user_initial_stackheap cannot reliably set up a usable heap
;     region if scatter loading is in use
;   这个行为与 --entry=Reset_Handler 无关（加了也一样），唯一的办法
;   就是不要用 main 这个名字。asmLight 那份工程叫 asm_main 正是这个道理。
;---------------------------------------------------------------------
                IMPORT  asm_main

; 下面 4 个是 armlink 按 scatter 文件里的区域名自动生成的符号，
; 用来告诉我们各段在 Flash / SRAM 中的实际起止地址。
; 官方默认 scatter（uVision "Use Memory Layout from Target Dialog"）里
; 区域名就是 ER_IROM1 和 RW_IRAM1，与你 asmLight 工程的 .sct 一致。
                IMPORT  |Image$$ER_IROM1$$RO$$Limit|     ; RO 段末尾 = .data 初值在 Flash 的起始
                IMPORT  |Image$$RW_IRAM1$$RW$$Base|      ; .data 在 SRAM 的起始
                IMPORT  |Image$$RW_IRAM1$$ZI$$Base|      ; .bss(ZI) 起始（也是 .data 的结束）
                IMPORT  |Image$$RW_IRAM1$$ZI$$Limit|     ; .bss(ZI) 结束

Reset_Handler
;---------------------------------------------------------------------
; 3.1  拷贝 .data：Flash(初值) → SRAM(变量实体)
;      源: Image$$ER_IROM1$$RO$$Limit
;      目的: Image$$RW_IRAM1$$RW$$Base  ~  Image$$RW_IRAM1$$ZI$$Base
;---------------------------------------------------------------------
                LDR     R0, =|Image$$ER_IROM1$$RO$$Limit|
                LDR     R1, =|Image$$RW_IRAM1$$RW$$Base|
                LDR     R2, =|Image$$RW_IRAM1$$ZI$$Base|
Copy_Data
                CMP     R1, R2
                BEQ     Copy_Data_End
                LDR     R3, [R0], #4            ; 从 Flash 取一个字，指针 +4
                STR     R3, [R1], #4            ; 写进 SRAM，指针 +4
                B       Copy_Data
Copy_Data_End

;---------------------------------------------------------------------
; 3.2  .bss(ZI) 清零
;      范围: Image$$RW_IRAM1$$ZI$$Base ~ Image$$RW_IRAM1$$ZI$$Limit
;      你文档里 rx_buf / frame_buf / channels 这些缓冲区都在这里，
;      不清零的话上电后它们是随机值，状态机会瞎跑。
;---------------------------------------------------------------------
                LDR     R1, =|Image$$RW_IRAM1$$ZI$$Base|
                LDR     R2, =|Image$$RW_IRAM1$$ZI$$Limit|
                MOV     R3, #0
Zero_Bss
                CMP     R1, R2
                BEQ     Zero_Bss_End
                STR     R3, [R1], #4
                B       Zero_Bss
Zero_Bss_End

;---------------------------------------------------------------------
; 3.3  重定位向量表
;      PM0214 P212 VTOR(0xE000ED08)。复位后 VTOR=0，Flash 被别名到
;      0x00000000 所以也能正常工作；显式写一遍，将来搬到 SRAM 跑也不用改。
;---------------------------------------------------------------------
                LDR     R0, =0xE000ED08
                LDR     R1, =0x08000000
                STR     R1, [R0]
                DSB
                ISB

;---------------------------------------------------------------------
; 3.4  进入 asm_main（main.s）
;---------------------------------------------------------------------
                LDR     R0, =asm_main
                BX      R0

;---------------------------------------------------------------------
; 四、默认中断处理
;    未实现的中断都落到这里。这里故意写成死循环而不是直接返回：
;    真进了不该进的中断，停下来比"带病继续跑"更容易定位问题。
;---------------------------------------------------------------------
Default_Handler
                B       Default_Handler

;---------------------------------------------------------------------
; 五、弱定义（[WEAK]）
;    这里先给一个空实现，main.s 里若用 EXPORT 定义了同名函数，
;    链接器会自动改用 main.s 的强定义，不用回来改向量表。
;---------------------------------------------------------------------
                EXPORT  NMI_Handler             [WEAK]
                EXPORT  HardFault_Handler       [WEAK]
                EXPORT  MemManage_Handler       [WEAK]
                EXPORT  BusFault_Handler        [WEAK]
                EXPORT  UsageFault_Handler      [WEAK]
                EXPORT  SVC_Handler             [WEAK]
                EXPORT  DebugMon_Handler        [WEAK]
                EXPORT  PendSV_Handler          [WEAK]
                EXPORT  SysTick_Handler         [WEAK]
                EXPORT  USART2_IRQHandler       [WEAK]
                EXPORT  USART6_IRQHandler       [WEAK]

NMI_Handler
HardFault_Handler
MemManage_Handler
BusFault_Handler
UsageFault_Handler
SVC_Handler
DebugMon_Handler
PendSV_Handler
SysTick_Handler
USART2_IRQHandler
USART6_IRQHandler
                B       Default_Handler

                END
