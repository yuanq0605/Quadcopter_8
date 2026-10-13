#include "Sleep.h"

/**
* @brief  微秒级延时 (查询方式)
* @param  us: 要延时的微秒数，最大值受限于SysTick重载值的24位宽，72MHz下约为233,015us
*/
void Sleep_us(uint32_t us) {
	uint32_t temp;
// 1. 设置重装载值。核心公式：计数值 = (系统时钟 / 1,000,000) * 要延时的微秒数
// 72MHz / 1,000,000 = 72，表示每微秒需要计数72次[reference:1]。
	SysTick->LOAD = (SystemCoreClock / 1000000) * us;
// 2. 清空当前计数值
	SysTick->VAL = 0x00;
// 3. 启动定时器：使能定时器，使能中断，使用内核时钟源（HCLK）
	SysTick->CTRL = 0x00000005;
// 4. 等待计数完成。通过查询COUNTFLAG标志位（CTRL寄存器的第16位）[reference:2]
	do {
		temp = SysTick->CTRL;
	} while ((temp & 0x01) && !(temp & (1 << 16)));
// 5. 延时完成，关闭定时器
	SysTick->CTRL = 0x00000004;
// 6. 清空当前计数值
	SysTick->VAL = 0x00;
}

/**
* @brief  毫秒级延时 (基于微秒级延时实现)
* @param  ms: 要延时的毫秒数
*/
void Sleep(uint32_t ms) {
	while (ms--) {
		Sleep_us(1000); // 循环调用delay_us，每次延时1000微秒（即1毫秒）
	}
}

/**
* @brief  秒级延时 (基于毫秒级延时实现)
* @param  s: 要延时的秒数
*/
void Sleep_s(uint32_t s) {
	while (s--) {
		Sleep(1000); // 循环调用delay_us，每次延时1000微秒（即1毫秒）
	}
}
