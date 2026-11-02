#include "soft_i2c.h"

// F103 72MHz 下的微秒延时，如果数据读不出，把 40 改大（比如 80）
void I2C_Delay(void)
{
    for (uint8_t i = 0; i < 100; i++) __NOP();
}

void I2C_Start(void)
{
    I2C_SDA_H();
    I2C_SCL_H(); 
    I2C_Delay();
    I2C_SDA_L(); 
    I2C_Delay(); // SCL高时，SDA由高变低 = START
    I2C_SCL_L(); 
    I2C_Delay();
}

void I2C_Stop(void) // 完美修复的 STOP 时序
{
    I2C_SDA_L(); 
    I2C_SCL_H(); 
    I2C_Delay();
    I2C_SDA_H(); 
    I2C_Delay(); // SCL高时，SDA由低变高 = STOP
}

uint8_t I2C_SendByte(uint8_t Byte)
{
    for (uint8_t i = 0; i < 8; i++)
    {
        if (Byte & (0x80 >> i)) I2C_SDA_H();
        else I2C_SDA_L();
        I2C_Delay();
        I2C_SCL_H(); 
        I2C_Delay(); 
        I2C_SCL_L(); 
        I2C_Delay();
    }
    return I2C_ReceiveAck();
}

uint8_t I2C_ReceiveByte(void)
{
    uint8_t Byte = 0x00;
    I2C_SDA_H();
    for (uint8_t i = 0; i < 8; i++)
    {
        I2C_SCL_H(); 
        I2C_Delay();
        if (I2C_SDA_READ() == GPIO_PIN_SET) Byte |= (0x80 >> i);
        I2C_SCL_L(); 
        I2C_Delay();
    }
    return Byte;
}

void I2C_SendAck(uint8_t AckBit)
{
    if (AckBit == 0) I2C_SDA_L(); 
    else I2C_SDA_H(); // 0=ACK, 1=NACK
    I2C_Delay(); 
    I2C_SCL_H(); 
    I2C_Delay(); 
    I2C_SCL_L(); 
    I2C_Delay();
}

uint8_t I2C_ReceiveAck(void)
{
    uint8_t Ack;
    I2C_SDA_H(); 
    I2C_Delay();
    I2C_SCL_H(); 
    I2C_Delay();
    Ack = I2C_SDA_READ();
    I2C_SCL_L(); 
    I2C_Delay();
    return Ack;
}

void I2C_BusRecovery(void)
{
    I2C_SDA_H();
    for (uint8_t i = 0; i < 9; i++) { 
        I2C_SCL_L(); 
        I2C_Delay(); 
        I2C_SCL_H(); 
        I2C_Delay(); 
    }
    I2C_Start(); 
    I2C_Stop();
}

void I2C_WriteReg(uint8_t devAddr, uint8_t regAddr, uint8_t data)
{
    I2C_Start(); 
    I2C_SendByte(devAddr); 
    I2C_SendByte(regAddr); 
    I2C_SendByte(data); 
    I2C_Stop();
}

uint8_t I2C_ReadReg(uint8_t devAddr, uint8_t regAddr)
{
    uint8_t data;
    I2C_Start(); 
    I2C_SendByte(devAddr); 
    I2C_SendByte(regAddr);
    I2C_Start(); 
    I2C_SendByte(devAddr | 1);
    data = I2C_ReceiveByte(); 
    I2C_SendAck(1); 
    I2C_Stop();
    return data;
}

void I2C_ReadBytes(uint8_t devAddr, uint8_t regAddr, uint8_t *buf, uint16_t len)
{
    I2C_Start(); 
    I2C_SendByte(devAddr); 
    I2C_SendByte(regAddr);
    I2C_Start(); 
    I2C_SendByte(devAddr | 1);
    for (uint16_t i = 0; i < len; i++) {
        buf[i] = I2C_ReceiveByte();
        if (i == len - 1) I2C_SendAck(1); else I2C_SendAck(0);
    }
    I2C_Stop();
}
