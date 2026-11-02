#ifndef __GY86_H
#define __GY86_H

#include "soft_i2c.h"

#define MPU6050_ADDR    0xD0
#define HMC5883L_ADDR   0x3C
#define MS5611_ADDR     0xEE

// 初始化
void GY86_Init(void);
// 读取MPU6050
void MPU6050_GetData(int16_t *ax, int16_t *ay, int16_t *az, int16_t *gx, int16_t *gy, int16_t *gz);
// 读取HMC5883L
void HMC5883L_GetData(int16_t *mx, int16_t *my, int16_t *mz);
// 读取MS5611
void MS5611_GetData(float *pressure, float *temperature);

#endif
