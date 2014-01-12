#include <platform.h>
#include "i2c.h"
#include "sensors.h"

// I2C Ports
// Prototype area on the XC-2 board
on stdcore[0] : struct r_i2c proto = {
    XS1_PORT_1K,  // D34 SCL
    XS1_PORT_1L,  // D35 SDA
    10000  // 10 kHz clock ticks
};

void sensors_init(void) {
    unsigned char data[1];

    unsigned t;
    timer tmr;

    // Delay for 15 ms in case the HTU21D is booting
    tmr :> t;
    tmr when timerafter(t + 1500000) :> void;

    i2c_master_init(proto);

    // Perform a soft reset
    i2c_master_write_reg(0x40, 0xFE, data, 0, proto);
    // Delay for 15 ms to let HTU21D boot
    tmr :> t;
    tmr when timerafter(t + 1500000) :> void;

    // Set 8-bit/12-bit humidity/temperature precision
    i2c_master_read_reg(0x40, 0xe7, data, 1, proto);
    data[0] &= 0x7F;  // MSB 0
    data[0] |= 0x01;  // LSB 1
    i2c_master_write_reg(0x40, 0xe6, data, 1, proto);
}

signed long htu21d_temp(void) {
    unsigned char data[3];
    unsigned short x;

    // Temperature measurement, hold master
    i2c_master_read_reg(0x40, 0xe3, data, 3, proto);
    x = (data[0] << 8) + (data[1] & 0xFC);
    // Fixed precision, 2 significant figures after the decimal
    return ((1098 * x) >> 12) - 4685;
}

signed long htu21d_humid(void) {
    unsigned char data[3];
    unsigned short x;

    // Humidity measurement, hold master
    i2c_master_read_reg(0x40, 0xe5, data, 3, proto);
    x = (data[0] << 8) + (data[1] & 0xFC);
    // Fixed precision, no figures after the decimal
    // TODO perform temperature compensation
    return ((125 * x) >> 16) - 6;
}
