	AREA CODE_SEG, CODE, READONLY	; 开启程序代码段
	EXPORT main			; 对外暴露main标签
	EXPORT USART1_IRQHandler	; 对外暴露USART1中断函数

main	; 主程序入口标签

	;=======================开启GPIOA和USART1时钟========================
	LDR		R0, =0x40023830	; 将RCC_AHB1ENR地址加载到R0
	LDR		R1, [R0]	; 读取RCC_AHB1ENR的值
	ORR		R1, R1, #1	; 将bit0置1，使能GPIOA时钟
	STR		R1, [R0]	; 将修改后的值写回RCC_AHB1ENR
	LDR		R0, =0x40023844	; 将RCC_APB2ENR地址加载到R0
	LDR		R1, [R0]	; 读取RCC_APB2ENR的值
	ORR		R1, R1, #(1 << 4)	; 将bit4置1，使能USART1时钟
	STR		R1, [R0]	; 将修改后的值写回RCC_APB2ENR

	;=======================配置PA9和PA10为USART1========================
	LDR		R0, =0x40020000	; 将GPIOA_MODER地址加载到R0
	LDR		R1, [R0]	; 读取GPIOA_MODER的值
	AND		R1, R1, #(~(0x3 << 18))	; 清除PA9模式位
	AND		R1, R1, #(~(0x3 << 20))	; 清除PA10模式位
	ORR		R1, R1, #(0x2 << 18)	; PA9设置为复用功能模式
	ORR		R1, R1, #(0x2 << 20)	; PA10设置为复用功能模式
	STR		R1, [R0]	; 将修改后的值写回GPIOA_MODER
	LDR		R0, =0x4002000C	; 将GPIOA_PUPDR地址加载到R0
	LDR		R1, [R0]	; 读取GPIOA_PUPDR的值
	AND		R1, R1, #(~(0x3 << 18))	; 清除PA9上下拉配置
	AND		R1, R1, #(~(0x3 << 20))	; 清除PA10上下拉配置
	ORR		R1, R1, #(0x1 << 20)	; PA10设置为上拉输入
	STR		R1, [R0]	; 将修改后的值写回GPIOA_PUPDR
	LDR		R0, =0x40020024	; 将GPIOA_AFRH地址加载到R0
	LDR		R1, [R0]	; 读取GPIOA_AFRH的值
	AND		R1, R1, #(~(0xF << 4))	; 清除PA9的复用功能选择位
	AND		R1, R1, #(~(0xF << 8))	; 清除PA10的复用功能选择位
	ORR		R1, R1, #(0x7 << 4)	; PA9选择AF7，即USART1_TX
	ORR		R1, R1, #(0x7 << 8)	; PA10选择AF7，即USART1_RX
	STR		R1, [R0]	; 将修改后的值写回GPIOA_AFRH

	;==========================配置USART1===============================
	LDR		R0, =0x40011008	; 将USART1_BRR地址加载到R0
	LDR		R1, =0x0683	; 16MHz时钟下9600波特率的BRR值
	STR		R1, [R0]	; 将BRR值写入USART1_BRR
	LDR		R0, =0x4001100C	; 将USART1_CR1地址加载到R0
	LDR		R1, =0x202C	; 使能USART、收发器和RXNE接收中断
	STR		R1, [R0]	; 将配置值写入USART1_CR1
	LDR		R0, =0xE000E104	; 将NVIC_ISER1地址加载到R0
	LDR		R1, =(1 << 5)	; USART1中断号37对应ISER1的bit5
	STR		R1, [R0]	; 使能USART1中断

	;==========================初始化浮点数据============================
	LDR		R0, =0xC0000000	; 将-2.0f的IEEE-754编码加载到R0
	VMOV		S0, R0	; 将R0中的浮点编码复制到S0

	;============================主循环===============================
main_loop	; 主循环标签
	BL		send_float	; 发送当前S0中的浮点数据
	LDR		R0, =0x3DCCCCCD	; 将+0.1f的IEEE-754编码加载到R0
	VMOV		S1, R0	; 将R0中的浮点编码复制到S1
	VADD.F32	S0, S0, S1	; S0 = S0 + 0.1f
	MOVS		R0, #500	; R0设置为500，准备延时500ms
	BL		delay_sub	; 跳转至延时子程序
	B		main_loop	; 跳转回主循环

	;============================发送子程序=============================
send_float	; BLE浮点数据发送子程序标签
	PUSH		{R4-R7, LR}	; 保存本子程序使用的寄存器和返回地址
	LDR		R4, =packet	; 将数据包缓冲区地址加载到R4
	MOVS		R5, #0xAA	; 设置数据包帧头
	STRB		R5, [R4]	; 将帧头写入packet[0]
	VMOV		R5, S0	; 将S0的32位浮点编码复制到R5
	STRB		R5, [R4, #1]	; 写入浮点数最低字节
	LSR		R6, R5, #8	; 将浮点数右移8位
	STRB		R6, [R4, #2]	; 写入浮点数第2字节
	LSR		R6, R5, #16	; 将浮点数右移16位
	STRB		R6, [R4, #3]	; 写入浮点数第3字节
	LSR		R6, R5, #24	; 将浮点数右移24位
	STRB		R6, [R4, #4]	; 写入浮点数最高字节
	LDRB		R5, [R4, #1]	; 读取第1个浮点数字节
	LDRB		R6, [R4, #2]	; 读取第2个浮点数字节
	EOR		R5, R5, R6	; 计算前两个字节的异或
	LDRB		R6, [R4, #3]	; 读取第3个浮点数字节
	EOR		R5, R5, R6	; 将第3个字节加入异或结果
	LDRB		R6, [R4, #4]	; 读取第4个浮点数字节
	EOR		R5, R5, R6	; 将第4个字节加入异或结果
	STRB		R5, [R4, #5]	; 将校验结果写入packet[5]

	MOVS		R7, #0	; R7作为当前发送字节索引
send_next	; 发送下一个字节标签
	LDR		R0, =0x40011000	; 将USART1_SR地址加载到R0
send_wait	; 等待发送数据寄存器为空
	LDR		R1, [R0]	; 读取USART1_SR
	TST		R1, #(1 << 7)	; 判断TXE标志是否为1
	BEQ		send_wait	; TXE为0时继续等待
	LDRB		R1, [R4, R7]	; 读取packet[R7]中的数据
	STRB		R1, [R0, #4]	; 将数据写入USART1_DR
	ADD		R7, R7, #1	; 发送索引加1
	CMP		R7, #6	; 判断6个字节是否发送完成
	BLO		send_next	; 未完成则发送下一个字节
	POP		{R4-R7, PC}	; 恢复寄存器并返回主循环

	;============================延时子程序=============================
delay_sub	; 延时子程序标签，R0为延时毫秒数
	CMP		R0, #0	; 判断R0是否为0
	BEQ		delay_done	; R0为0时直接返回
delay_outer	; 延时外层循环标签
	LDR		R1, =4000	; 设置1ms内层循环计数器
delay_inner	; 延时内层循环标签
	SUB		R1, R1, #1	; 计数器执行自减操作
	CMP		R1, #0	; 判断R1是否为0
	BNE		delay_inner	; R1不为0则继续内层循环
	SUB		R0, R0, #1	; 已完成1ms，剩余毫秒数减1
	BNE		delay_outer	; R0不为0则继续外层循环
delay_done	; 延时完成标签
	BX		LR	; 跳转回调用者

	;==========================USART1中断===============================
USART1_IRQHandler	; USART1中断服务函数标签
	PUSH		{R0-R3, R12, LR}	; 保存中断服务函数使用的寄存器
	LDR		R0, =0x40011000	; 将USART1_SR地址加载到R0
	LDR		R1, [R0]	; 读取USART1_SR
	TST		R1, #(1 << 5)	; 判断RXNE接收非空标志是否为1
	BEQ		irq_done	; RXNE为0时跳过接收处理
	LDRB		R2, [R0, #4]	; 读取USART1_DR并取得接收数据
	; 读取DR后直接丢弃接收字节，不再控制LED
irq_done	; USART1中断结束标签
	TST		R1, #(1 << 3)	; 判断是否发生接收溢出错误
	BEQ		irq_return	; 没有溢出错误时直接返回
	LDRB		R2, [R0, #4]	; 再次读取USART1_DR，清除残留错误状态
irq_return	; 中断返回标签
	POP		{R0-R3, R12, PC}	; 恢复现场并返回主程序

	NOP		; 使代码段长度对齐到4字节，避免数据段前自动补齐
	AREA DATA_SEG, DATA, READWRITE, ALIGN=2	; 开启数据段，按4字节边界对齐
packet	SPACE 6	; 分配6字节BLE数据包缓冲区

	END
