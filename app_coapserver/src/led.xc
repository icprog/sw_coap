#include <platform.h>

out port x0ledB = PORT_LED_0_1;

void ledon() {
    x0ledB <: 1;
}

void ledoff() {
    x0ledB <: 0;
}
