#include "gy86.h"
#include <stdio.h>

uint16_t C[7]; // MS5611 校准系数

// ================== 内部静态函数 ==================
static void MPU6050_Init(void)
{
    I2C_WriteReg(MPU6050_ADDR, 0x6B, 0x80); HAL_Delay(100);
    I2C_WriteReg(MPU6050_ADDR, 0x6B, 0x00); HAL_Delay(50);
    I2C_WriteReg(MPU6050_ADDR, 0x1C, 0x18);
    I2C_WriteReg(MPU6050_ADDR, 0x1B, 0x18);
    I2C_WriteReg(MPU6050_ADDR, 0x1A, 0x03);
    I2C_WriteReg(MPU6050_ADDR, 0x19, 0x09);
}

static void HMC5883L_Init(void)
{
    // 开启 MPU6050 旁路模式
    I2C_WriteReg(MPU6050_ADDR, 0x6A, 0x00);
    I2C_WriteReg(MPU6050_ADDR, 0x37, 0x02);
    HAL_Delay(10);

    I2C_WriteReg(HMC5883L_ADDR, 0x00, 0x70);
    I2C_WriteReg(HMC5883L_ADDR, 0x01, 0x20);
    I2C_WriteReg(HMC5883L_ADDR, 0x02, 0x00);
    HAL_Delay(10);
}

static void MS5611_WriteCmd(uint8_t cmd)
{
    I2C_Start(); 
    I2C_SendByte(MS5611_ADDR); 
    I2C_SendByte(cmd); 
    I2C_Stop();
}

static uint32_t MS5611_ReadADC(void)
{
    uint8_t buf[3];
    I2C_Start();
    I2C_SendByte(MS5611_ADDR); 
    I2C_SendByte(0x00);
    I2C_Start(); 
    I2C_SendByte(MS5611_ADDR | 1);
    for (uint8_t i = 0; i < 3; i++) { 
        buf[i] = I2C_ReceiveByte(); 
        I2C_SendAck(i == 2 ? 1 : 0); 
    }
    I2C_Stop();
    return ((uint32_t)buf[0] << 16) | ((uint32_t)buf[1] << 8) | buf[2];
}

static void MS5611_Init(void)
{
    MS5611_WriteCmd(0x1E); 
    HAL_Delay(10);
    for (uint8_t i = 1; i <= 6; i++) {
        MS5611_WriteCmd(0xA0 + i * 2);
        uint8_t buf[2];
        I2C_Start(); 
        I2C_SendByte(MS5611_ADDR | 1);
        buf[0] = I2C_ReceiveByte(); 
        I2C_SendAck(0);
        buf[1] = I2C_ReceiveByte(); 
        I2C_SendAck(1); 
        I2C_Stop();
        C[i] = (buf[0] << 8) | buf[1];
    }
}

// ================== 对外接口 ==================
void GY86_Init(void)
{
    I2C_BusRecovery();
    MPU6050_Init();
    HMC5883L_Init();
    MS5611_Init();
}

void MPU6050_GetData(int16_t *ax, int16_t *ay, int16_t *az, int16_t *gx, int16_t *gy, int16_t *gz)
{
    uint8_t buf[14];
    I2C_ReadBytes(MPU6050_ADDR, 0x3B, buf, 14);
    *ax = (int16_t)((buf[0] << 8) | buf[1]);
    *ay = (int16_t)((buf[2] << 8) | buf[3]);
    *az = (int16_t)((buf[4] << 8) | buf[5]);
    *gx = (int16_t)((buf[8] << 8) | buf[9]);
    *gy = (int16_t)((buf[10] << 8) | buf[11]);
    *gz = (int16_t)((buf[12] << 8) | buf[13]);
}

void HMC5883L_GetData(int16_t *mx, int16_t *my, int16_t *mz)
{
    uint8_t buf[6];
    I2C_ReadBytes(HMC5883L_ADDR, 0x03, buf, 6);
    *mx = (int16_t)((buf[0] << 8) | buf[1]);
    *mz = (int16_t)((buf[2] << 8) | buf[3]); // 注意顺序 X, Z, Y
    *my = (int16_t)((buf[4] << 8) | buf[5]);
}

void MS5611_GetData(float *pressure, float *temperature)
{
    uint32_t D1, D2;
    MS5611_WriteCmd(0x48); HAL_Delay(10); 
    D1 = MS5611_ReadADC();
    MS5611_WriteCmd(0x58); HAL_Delay(10); 
    D2 = MS5611_ReadADC();

    int32_t dT = D2 - ((uint32_t)C[5] << 8);
    int32_t TEMP = 2000 + ((int64_t)dT * C[6]) / 8388608;
    int64_t OFF  = ((int64_t)C[2] << 16) + ((int64_t)C[4] * dT) / 128;
    int64_t SENS = ((int64_t)C[1] << 15) + ((int64_t)C[3] * dT) / 256;
    int32_t P = ((int64_t)D1 * SENS / 2097152 - OFF) / 32768;

    *temperature = TEMP / 100.0f;
    *pressure    = P / 100.0f;
}
