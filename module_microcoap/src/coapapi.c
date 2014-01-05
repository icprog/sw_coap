#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "coapapi.h"
#include "coap.h"

int coap_simple(const uint8_t inbuf[], const size_t inbuflen, uint8_t outbuf[], size_t outbuflen[1])
{
    int rc;
    coap_packet_t pkt;

    const size_t scrlen = 4096;
    uint8_t scratch_raw[scrlen];
    coap_rw_buffer_t scratch_buf = {scratch_raw, scrlen};

    if (0 != (rc = coap_parse(&pkt, inbuf, inbuflen))) {
        return rc;
    } else {
        coap_packet_t rsppkt;
        coap_handle_req(&scratch_buf, &pkt, &rsppkt);
        return coap_build(outbuf, outbuflen, &rsppkt);
    }
}
