#ifndef __SLEEP__
#define __SLEEP__

#include "stm32f10x.h"                  // Device header
void Sleep_us(uint32_t us);
void Sleep_s(uint32_t s);
void Sleep(uint32_t ms);

#endif
