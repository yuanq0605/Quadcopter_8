#include "stm32f10x.h"                  // Device header
#include "BLE.h"
#include "Sleep.h"
#include "LED.h"

int main(void)
{
	LED_Init();
	BLE_Init();
	float num = -2.0f;
	//float arr[9] = {-9.0f, -8.0f, -7.0f, -6.0f, -5.0f, -4.0f, -3.0f, -2.0f, -1.0f};
	while (1)
	{
		if (GPIO_ReadInputDataBit(GPIOA, GPIO_Pin_6) != Bit_SET)
		{
			Sleep(100);
			continue;
		}
		BLE_Send_Float(num);
		num += 0.1f;
		/*
		BLE_Send_9Float(arr);
		for (int i = 0; i <= 8; i++) arr[i] += 0.1f;
		*/
		Sleep(500);
	}
}
