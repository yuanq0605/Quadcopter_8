#include "BLE.h"

void BLE_Init()
{
// 启动 GPIOA 和 USART2 的时钟
	RCC_APB1PeriphClockCmd(RCC_APB1Periph_USART2, ENABLE);
	RCC_APB2PeriphClockCmd(RCC_APB2Periph_GPIOA, ENABLE);

	GPIO_InitTypeDef GPIO_InitStructure;
	GPIO_InitStructure.GPIO_Speed = GPIO_Speed_50MHz;
// PA2 (TX) 配置为复用推挽输出
	GPIO_InitStructure.GPIO_Pin = GPIO_Pin_2;
	GPIO_InitStructure.GPIO_Mode = GPIO_Mode_AF_PP;
	GPIO_Init(GPIOA, &GPIO_InitStructure);
// PA3 (RX) 配置为浮空输入
	GPIO_InitStructure.GPIO_Pin = GPIO_Pin_3;
	GPIO_InitStructure.GPIO_Mode = GPIO_Mode_IN_FLOATING;
	GPIO_Init(GPIOA, &GPIO_InitStructure);
// PA6 (STATE) 配置为上拉输入
	GPIO_InitStructure.GPIO_Pin = GPIO_Pin_6;
	GPIO_InitStructure.GPIO_Mode = GPIO_Mode_IPU;
	GPIO_Init(GPIOA, &GPIO_InitStructure);

// USART 初始化 (9600、输入输出、无流控、无校验、8位长、停止位1位)
	USART_InitTypeDef USART_InitStructure;
	USART_InitStructure.USART_BaudRate = 9600;
	USART_InitStructure.USART_Mode = USART_Mode_Tx | USART_Mode_Rx;
	USART_InitStructure.USART_HardwareFlowControl = USART_HardwareFlowControl_None;
	USART_InitStructure.USART_Parity = USART_Parity_No;
	USART_InitStructure.USART_WordLength = USART_WordLength_8b;
	USART_InitStructure.USART_StopBits = USART_StopBits_1;
	USART_Init(USART2, &USART_InitStructure);
	USART_Cmd(USART2, ENABLE);

// 第一步：在外设层面使能中断
	USART_ITConfig(USART2, USART_IT_RXNE, ENABLE);
// 含义：当USART2的RXNE（接收数据寄存器非空）事件发生时，向NVIC发出中断请求

// 第二步：在NVIC层面使能中断通道并设置优先级
	NVIC_InitTypeDef NVIC_InitStructure;
	NVIC_InitStructure.NVIC_IRQChannel = USART2_IRQn;         // 选择USART2的中断通道
	NVIC_InitStructure.NVIC_IRQChannelPreemptionPriority = 1; // 抢占优先级
	NVIC_InitStructure.NVIC_IRQChannelSubPriority = 1;        // 子优先级
	NVIC_InitStructure.NVIC_IRQChannelCmd = ENABLE;           // 使能这个通道
	NVIC_Init(&NVIC_InitStructure);
}

// 第三步：编写中断服务函数（函数名必须和启动文件中的向量表一致！）
void USART2_IRQHandler(void) {
    // 判断是哪个事件触发了中断
    if(USART_GetITStatus(USART2, USART_IT_RXNE) != RESET) {
        uint16_t data = USART_ReceiveData(USART2); // 读取数据（读DR会自动清除RXNE标志）
        if (data == 'A')
		{
			Light_up();
		}
		else
		{
			Light_down();
		}
    }
}

void BLE_Send_Float(float num)
{
	uint8_t pack[6];
	pack[0] = 0xAA;
	memcpy(&pack[1], &num, 4);
	pack[5] = 0;
	for (int i = 1; i <= 4; i++)
		pack[5] ^= pack[i];
	for (int i = 0; i <= 5; i++)
	{
		while(USART_GetFlagStatus(USART2, USART_FLAG_TXE) == RESET);
		USART_SendData(USART2, pack[i]);
	}
}

/*
void BLE_Send_9Float(float num[9])
{
	uint8_t pack[16];
	pack[0] = 0xAA;
	for (uint8_t i = 0; i <= 6; i += 3)
	{
		pack[1] = i;
		memcpy(&pack[2], num + i, 12);
	}
}
*/
