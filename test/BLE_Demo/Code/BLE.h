#ifndef __BLE__
#define __BLE__

#include "LED.h"
#include <string.h>
#include "stm32f10x.h"                  // Device header
void BLE_Init(void);
void BLE_Send_Float(float num);
//void BLE_Send_9Float(float num[9]);

#endif
