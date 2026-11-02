#ifndef __SOFT_I2C_H
#define __SOFT_I2C_H

#include "main.h"

// 引脚宏定义（与CubeMX中配置的一致）
#define I2C_SCL_PIN  GPIO_PIN_8
#define I2C_SCL_PORT GPIOB
#define I2C_SDA_PIN  GPIO_PIN_9
#define I2C_SDA_PORT GPIOB

// 读写宏（利用HAL库）
#define I2C_SCL_H()  HAL_GPIO_WritePin(I2C_SCL_PORT, I2C_SCL_PIN, GPIO_PIN_SET)
#define I2C_SCL_L()  HAL_GPIO_WritePin(I2C_SCL_PORT, I2C_SCL_PIN, GPIO_PIN_RESET)
#define I2C_SDA_H()  HAL_GPIO_WritePin(I2C_SDA_PORT, I2C_SDA_PIN, GPIO_PIN_SET)
#define I2C_SDA_L()  HAL_GPIO_WritePin(I2C_SDA_PORT, I2C_SDA_PIN, GPIO_PIN_RESET)
#define I2C_SDA_READ() HAL_GPIO_ReadPin(I2C_SDA_PORT, I2C_SDA_PIN)

void I2C_Delay(void);
void I2C_Start(void);
void I2C_Stop(void);
uint8_t I2C_SendByte(uint8_t Byte);
uint8_t I2C_ReceiveByte(void);
void I2C_SendAck(uint8_t AckBit);
uint8_t I2C_ReceiveAck(void);
void I2C_BusRecovery(void);

void I2C_WriteReg(uint8_t devAddr, uint8_t regAddr, uint8_t data);
uint8_t I2C_ReadReg(uint8_t devAddr, uint8_t regAddr);
void I2C_ReadBytes(uint8_t devAddr, uint8_t regAddr, uint8_t *buf, uint16_t len);

#endif
