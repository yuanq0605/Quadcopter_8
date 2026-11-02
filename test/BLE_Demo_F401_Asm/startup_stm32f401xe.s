; STM32F401RE启动文件

                PRESERVE8                   ; 保证栈按照8字节边界对齐
                THUMB                      ; 使用Thumb指令集

Stack_Size      EQU     0x00000400       ; 分配1KB主栈空间
                AREA    STACK, NOINIT, READWRITE, ALIGN=3 ; 开启栈空间段
Stack_Mem       SPACE   Stack_Size       ; 分配Stack_Size字节的栈空间
__initial_sp                            ; 栈顶地址标签

                AREA    RESET, DATA, READONLY ; 开启向量表段
                EXPORT  __Vectors              ; 对外暴露向量表起始标签
                EXPORT  __Vectors_End          ; 对外暴露向量表结束标签
                IMPORT  main                    ; 引用main.s中的主程序入口
                IMPORT  USART1_IRQHandler       ; 引用main.s中的USART1中断函数

__Vectors       DCD     __initial_sp      ; 填写初始主栈指针
                DCD     Reset_Handler     ; 复位后首先执行的入口
                DCD     NMI_Handler       ; 不可屏蔽中断
                DCD     HardFault_Handler ; 硬件错误异常
                DCD     MemManage_Handler ; MPU存储器管理异常
                DCD     BusFault_Handler  ; 总线错误异常
                DCD     UsageFault_Handler ; 用法错误异常
                DCD     0                  ; 保留向量
                DCD     0                  ; 保留向量
                DCD     0                  ; 保留向量
                DCD     0                  ; 保留向量
                DCD     SVC_Handler        ; SVC系统调用异常
                DCD     DebugMon_Handler   ; 调试监视异常
                DCD     0                  ; 保留向量
                DCD     PendSV_Handler     ; PendSV异常
                DCD     SysTick_Handler    ; SysTick异常

                ; STM32F401外部中断向量表，USART1中断号为37
                DCD     Default_Handler             ; 0  WWDG
                DCD     Default_Handler             ; 1  PVD
                DCD     Default_Handler             ; 2  TAMP_STAMP
                DCD     Default_Handler             ; 3  RTC_WKUP
                DCD     Default_Handler             ; 4  FLASH
                DCD     Default_Handler             ; 5  RCC
                DCD     Default_Handler             ; 6  EXTI0
                DCD     Default_Handler             ; 7  EXTI1
                DCD     Default_Handler             ; 8  EXTI2
                DCD     Default_Handler             ; 9  EXTI3
                DCD     Default_Handler             ; 10 EXTI4
                DCD     Default_Handler             ; 11 DMA1_Stream0
                DCD     Default_Handler             ; 12 DMA1_Stream1
                DCD     Default_Handler             ; 13 DMA1_Stream2
                DCD     Default_Handler             ; 14 DMA1_Stream3
                DCD     Default_Handler             ; 15 DMA1_Stream4
                DCD     Default_Handler             ; 16 DMA1_Stream5
                DCD     Default_Handler             ; 17 DMA1_Stream6
                DCD     Default_Handler             ; 18 ADC
                DCD     Default_Handler             ; 19 Reserved
                DCD     Default_Handler             ; 20 Reserved
                DCD     Default_Handler             ; 21 Reserved
                DCD     Default_Handler             ; 22 Reserved
                DCD     Default_Handler             ; 23 EXTI9_5
                DCD     Default_Handler             ; 24 TIM1_BRK_TIM9
                DCD     Default_Handler             ; 25 TIM1_UP_TIM10
                DCD     Default_Handler             ; 26 TIM1_TRG_COM_TIM11
                DCD     Default_Handler             ; 27 TIM1_CC
                DCD     Default_Handler             ; 28 TIM2
                DCD     Default_Handler             ; 29 TIM3
                DCD     Default_Handler             ; 30 TIM4
                DCD     Default_Handler             ; 31 I2C1_EV
                DCD     Default_Handler             ; 32 I2C1_ER
                DCD     Default_Handler             ; 33 I2C2_EV
                DCD     Default_Handler             ; 34 I2C2_ER
                DCD     Default_Handler             ; 35 SPI1
                DCD     Default_Handler             ; 36 SPI2
                DCD     USART1_IRQHandler           ; 37 USART1，接收蓝牙数据
                DCD     Default_Handler             ; 38 USART2
                DCD     Default_Handler             ; 39 Reserved
                DCD     Default_Handler             ; 40 EXTI15_10
                DCD     Default_Handler             ; 41 RTC_Alarm
                DCD     Default_Handler             ; 42 OTG_FS_WKUP
                DCD     Default_Handler             ; 43 Reserved
                DCD     Default_Handler             ; 44 Reserved
                DCD     Default_Handler             ; 45 Reserved
                DCD     Default_Handler             ; 46 Reserved
                DCD     Default_Handler             ; 47 DMA1_Stream7
                DCD     Default_Handler             ; 48 Reserved
                DCD     Default_Handler             ; 49 SDIO
                DCD     Default_Handler             ; 50 TIM5

__Vectors_End                           ; 向量表结束标签

                AREA    CODE_SEG, CODE, READONLY, ALIGN=2 ; 开启程序代码段，按4字节边界对齐

Reset_Handler   PROC
                EXPORT  Reset_Handler        ; 对外暴露复位入口
                ;=======================开启FPU访问权限=======================
                LDR     R0, =0xE000ED88      ; 将SCB_CPACR地址加载到R0
                LDR     R1, [R0]              ; 读取SCB_CPACR寄存器的值
                ORR     R1, R1, #0x00F00000   ; 开启CP10和CP11的完全访问权限
                STR     R1, [R0]              ; 将修改后的值写回SCB_CPACR
                DSB                          ; 等待前面的存储操作完成
                ISB                          ; 刷新流水线中的指令
                ;==========================设置主栈==========================
                LDR     SP, =__initial_sp     ; 将栈顶地址加载到主栈指针SP
                ;==========================进入主程序========================
                LDR     R0, =main             ; 将main入口地址加载到R0
                BX      R0                     ; 跳转到main程序
                ENDP

NMI_Handler     PROC
                EXPORT  NMI_Handler
                B       .                     ; 未处理异常停留在当前地址
                ENDP
HardFault_Handler PROC
                EXPORT  HardFault_Handler
                B       .
                ENDP
MemManage_Handler PROC
                EXPORT  MemManage_Handler
                B       .
                ENDP
BusFault_Handler PROC
                EXPORT  BusFault_Handler
                B       .
                ENDP
UsageFault_Handler PROC
                EXPORT  UsageFault_Handler
                B       .
                ENDP
SVC_Handler     PROC
                EXPORT  SVC_Handler
                B       .
                ENDP
DebugMon_Handler PROC
                EXPORT  DebugMon_Handler
                B       .
                ENDP
PendSV_Handler  PROC
                EXPORT  PendSV_Handler
                B       .
                ENDP
SysTick_Handler PROC
                EXPORT  SysTick_Handler
                B       .
                ENDP

Default_Handler PROC
                EXPORT  Default_Handler
                B       .                     ; 未使用中断统一进入死循环
                ENDP

                NOP                         ; 使代码段长度对齐到4字节，避免自动补齐警告
                END
