	AREA RESET, DATA, READONLY	; 开启向量表段
	DCD 0x20018000	; 填写栈顶地址（STM32F401RE的SRAM顶端）
	DCD Reset_Handler	; 复位处理函数标签
		
	AREA CODE_SEG, CODE, READONLY	; 开启程序代码段
	EXPORT Reset_Handler	; 对外暴露Reset_Handler标签，让向量表可以引用该符号
Reset_Handler	; 定义Reset_Handler复位入口标签
	
	;=======================开启GPIOA的时钟==========================
	LDR		R0, =0x40023830	; 将RCC_AHB1ENR绝对物理地址（RCC起始地址0x40023800 + 偏移量0x30）加载到R0
	LDR		R1, [R0]	; 将寄存器R0指向的寄存器的存储值读取到寄存器R1中
	ORR		R1, R1, #1	; 将寄存器R1的bit0置1，使能GPIOA的时钟
	STR		R1, [R0]	; 将修改后的值写回R0指向的寄存器RCC_AHB1ENR
	
	;===================配置PA5为通用推挽输出模式====================
	LDR		R0, =0x40020000	; 将GPIOA_MODER绝对物理地址（GPIOA起始地址0x40020000 + 偏移量0x0）加载到R0
	LDR		R1, [R0]	; 将寄存器R0指向的寄存器的存储值读取到寄存器R1中
	AND		R1, R1, #(~(0x3 << 10))	; 将寄存器R1的bit10、bit11置0
	ORR		R1, R1, #(0x1 << 10)	; 将寄存器R1的bit10置1
	STR		R1, [R0]	; 将修改后的值写回R0指向的寄存器GPIOA_MODER
	LDR		R0, =0x40020004	; 将GPIOA_OTYPER绝对物理地址（GPIOA起始地址0x40020000 + 偏移量0x4）加载到R0
	LDR		R1, [R0]	; 将寄存器R0指向的寄存器的存储值读取到寄存器R1中
	AND		R1, R1, #(~(0x1 << 5))	; 将寄存器R1的bit5置0
	STR		R1, [R0]	; 将修改后的值写回R0指向的寄存器GPIOA_OTYPER
	LDR		R0, =0x40020008	; 将GPIOA_OSPEEDR绝对物理地址（GPIOA起始地址0x40020000 + 偏移量0x8）加载到R0
	LDR		R1, [R0]	; 将寄存器R0指向的寄存器的存储值读取到寄存器R1中
	AND		R1, R1, #(~(0x3 << 10))	; 将寄存器R1的bit10、bit11置0
	STR		R1, [R0]	; 将修改后的值写回R0指向的寄存器GPIOA_OSPEEDR
	LDR		R0, =0x4002000C	; 将GPIOA_PUPDR绝对物理地址（GPIOA起始地址0x40020000 + 偏移量0xC）加载到R0
	LDR		R1, [R0]	; 将寄存器R0指向的寄存器的存储值读取到寄存器R1中
	AND		R1, R1, #(~(0x3 << 10))	; 将寄存器R1的bit10、bit11置0
	STR		R1, [R0]	; 将修改后的值写回R0指向的寄存器GPIOA_PUPDR
	
	;============================主循环==============================
main_loop	; 主循环标签
	
	LDR		R0, =0x40020018	; 将GPIOA_BSRR绝对物理地址（GPIOA起始地址0x40020000 + 偏移量0x18）加载到R0
	LDR		R1, =0x00000020	; BSRR低16位：置位PA5
	STR		R1, [R0]	; 将修改后的值写回R0指向的寄存器GPIOA_BSRR
	
	BL		delay_sub	;	跳转至延时子程序
	
	LDR		R0, =0x40020018	; 将GPIOA_BSRR绝对物理地址（GPIOA起始地址0x40020000 + 偏移量0x18）加载到R0
	LDR		R1, =0x00200000	; BSRR高16位：复位PA5
	STR		R1, [R0]	; 将修改后的值写回R0指向的寄存器GPIOA_BSRR
	
	BL		delay_sub	;	跳转至延时子程序
	
	B 		main_loop	;	跳转至主循环入口
	
	
	;============================子程序===============================
delay_sub	; 延时子程序标签
	LDR		R2, =0x250000	; 选取R2作为循环计数器，0x500000作为计数器初始值
delay_inner	; 循环内部标签
		SUB		R2, R2, #1	; 计数器执行自减操作
		CMP		R2, #0	; 判断R2是否为0，将条件标志位置为R2 - 0
		BNE		delay_inner	; 若条件标志位不为0则跳转至delay_inner
		BX		LR	; 跳转回主循环
	
	END
	
	