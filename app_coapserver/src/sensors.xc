#include <platform.h>
#include "i2c.h"
#include "sensors.h"

#define DEBUG 1

#ifdef DEBUG
#include "print.h"
#endif

#define HTU21D_ADDR 0x40

#define HTU21D_CMD_TH  0xe3
#define HTU21D_CMD_TNH 0xf3
#define HTU21D_CMD_HH  0xe5
#define HTU21D_CMD_HNH 0xf5
#define HTU21D_CMD_WR  0xe6
#define HTU21D_CMD_RD  0xe7
#define HTU21D_CMD_RST 0xfe

#define MPL3115A2_ADDR 0x60

#define MPL3115A2_STATUS      0x00
#define MPL3115A2_OUT_P_MSB   0x01
#define MPL3115A2_OUT_P_CSB   0x02
#define MPL3115A2_OUT_P_LSB   0x03
#define MPL3115A2_OUT_T_MSB   0x04
#define MPL3115A2_OUT_T_LSB   0x05
#define MPL3115A2_WHO_AM_I    0x0C
#define MPL3115A2_PT_DATA_CFG 0x13
#define MPL3115A2_CTRL_REG1   0x26

// I2C Ports
// Prototype area on the XC-2 board
on stdcore[0] : struct r_i2c proto = {
    XS1_PORT_1K,  // D34 SCL
    XS1_PORT_1L,  // D35 SDA
    10000  // 10 kHz clock ticks
};

void mpl3115a2_init(void);
void htu21d_init(void);

void sensors_init(void) {
    unsigned t;
    timer tmr;

    i2c_master_init(proto);

    // Delay for 20 ms, in case chips are booting
    tmr :> t;
    tmr when timerafter(t + 2000000) :> void;

    htu21d_init();
    mpl3115a2_init();
}

void htu21d_init(void) {
    unsigned char data[1];

    unsigned t;
    timer tmr;

    // Delay for 15 ms in case the HTU21D is booting
    tmr :> t;
    tmr when timerafter(t + 1500000) :> void;

    // Perform a soft reset
    i2c_master_write_reg(HTU21D_ADDR, HTU21D_CMD_RST, data, 0, proto);
    // Delay for 15 ms to let HTU21D boot
    tmr :> t;
    tmr when timerafter(t + 1500000) :> void;

    // Set 8-bit/12-bit humidity/temperature precision
    i2c_master_read_reg(HTU21D_ADDR, HTU21D_CMD_RD, data, 1, proto);
    data[0] &= 0x7F;  // MSB 0
    data[0] |= 0x01;  // LSB 1
    i2c_master_write_reg(HTU21D_ADDR, HTU21D_CMD_WR, data, 1, proto);
}

signed long htu21d_temp(void) {
    unsigned char data[3];
    unsigned short x;

    // Temperature measurement, hold master
    i2c_master_read_reg(HTU21D_ADDR, HTU21D_CMD_TH, data, 3, proto);
    x = (data[0] << 8) + (data[1] & 0xFC);
    // Fixed precision, 2 significant figures after the decimal
    return ((1098 * x) >> 12) - 4685;
}

signed long htu21d_humid(void) {
    unsigned char data[3];
    unsigned short x;

    // Humidity measurement, hold master
    i2c_master_read_reg(HTU21D_ADDR, HTU21D_CMD_HH, data, 3, proto);
    x = (data[0] << 8) + (data[1] & 0xFC);
    // Fixed precision, no figures after the decimal
    // TODO perform temperature compensation
    return ((125 * x) >> 16) - 6;
}

void mpl3115a2_init(void) {
    unsigned char data[1];

    /* Set to barometer, standby with an OSR = 128 */
    data[0] = 0x38;
    i2c_master_write_reg(MPL3115A2_ADDR, MPL3115A2_CTRL_REG1, data, 1, proto);

    /* Enable data flags in PT_DATA_CFG */
    // Not essential
    data[0] = 0x07;
    i2c_master_write_reg(MPL3115A2_ADDR, MPL3115A2_PT_DATA_CFG, data, 1, proto);

    /* Set Active */
    data[0] = 0x39;
    i2c_master_write_reg(MPL3115A2_ADDR, MPL3115A2_CTRL_REG1, data, 1, proto);

#ifdef DEBUG
    i2c_master_read_reg(MPL3115A2_ADDR, MPL3115A2_WHO_AM_I, data, 1, proto);
    printstr("MPL3115A2 WHO_AM_I = ");
    printintln(data[0]);
#endif
}

unsigned long mpl3115a2_pres(void) {
    unsigned char data[3];
    unsigned long x;

    i2c_master_read_reg(MPL3115A2_ADDR, MPL3115A2_OUT_P_MSB, data, 3, proto);
    x = (data[0] << 12) + (data[1] << 4) + (data[2] >> 4);  // 20-bit register
    return x;  // Pascal, 18+2 bits fixed precision
}

signed short mpl3115a2_temp(void) {
    unsigned char data[2];
    signed short x;

    i2c_master_read_reg(MPL3115A2_ADDR, MPL3115A2_OUT_T_MSB, data, 2, proto);
    x = (data[0] << 4) + (data[1] >> 4);  // 12-bit register
    return x;  // Celsius, 2's complement, 8+4 bits fixed precision (fractional bits are not signed)
}
