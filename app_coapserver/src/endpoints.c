#include <stdbool.h>
#include <string.h>
#include "coap.h"
#include "sensors.h"

static char light = '0';

const uint16_t rsplen = 1500;
static char rsp[1500] = "";
void build_rsp(void);

extern void ledon(void);
extern void ledoff(void);

void endpoints_init(void)
{
    build_rsp();
    sensors_init();
}

static const coap_endpoint_path_t path_well_known_core = {2, {".well-known", "core"}};
static int handle_get_well_known_core(coap_rw_buffer_t *scratch, const coap_packet_t *inpkt, coap_packet_t *outpkt, uint8_t id_hi, uint8_t id_lo)
{
    return coap_make_response(scratch, outpkt, (const uint8_t *)rsp, strlen(rsp), id_hi, id_lo, &(inpkt->tok), COAP_RSPCODE_CONTENT, COAP_CONTENTTYPE_APPLICATION_LINKFORMAT);
}

static const coap_endpoint_path_t path_light = {1, {"light"}};
static int handle_get_light(coap_rw_buffer_t *scratch, const coap_packet_t *inpkt, coap_packet_t *outpkt, uint8_t id_hi, uint8_t id_lo)
{
    return coap_make_response(scratch, outpkt, (const uint8_t *)&light, 1, id_hi, id_lo, &(inpkt->tok), COAP_RSPCODE_CONTENT, COAP_CONTENTTYPE_TEXT_PLAIN);
}

static int handle_put_light(coap_rw_buffer_t *scratch, const coap_packet_t *inpkt, coap_packet_t *outpkt, uint8_t id_hi, uint8_t id_lo)
{
    if (inpkt->payload.len == 0)
        return coap_make_response(scratch, outpkt, NULL, 0, id_hi, id_lo, &(inpkt->tok), COAP_RSPCODE_BAD_REQUEST, COAP_CONTENTTYPE_TEXT_PLAIN);
    if (inpkt->payload.p[0] == '1')
    {
        light = '1';
        ledon();
        return coap_make_response(scratch, outpkt, (const uint8_t *)&light, 1, id_hi, id_lo, &(inpkt->tok), COAP_RSPCODE_CHANGED, COAP_CONTENTTYPE_TEXT_PLAIN);
    }
    else
    {
        light = '0';
        ledoff();
        return coap_make_response(scratch, outpkt, (const uint8_t *)&light, 1, id_hi, id_lo, &(inpkt->tok), COAP_RSPCODE_CHANGED, COAP_CONTENTTYPE_TEXT_PLAIN);
    }
}

static const coap_endpoint_path_t path_temp = {1, {"temperature"}};
static int handle_get_temp(coap_rw_buffer_t *scratch, const coap_packet_t *inpkt, coap_packet_t *outpkt, uint8_t id_hi, uint8_t id_lo)
{
    signed long temp;
    unsigned char str[8];
    size_t len = 0;

    temp = htu21d_temp();
    if (temp > 0) {
        if (temp > 10000)
          str[len++] = temp / 10000 + '0';
        str[len++] = (temp / 1000 - 10 * (temp / 10000)) + '0';
        str[len++] = (temp / 100 - 10 * (temp / 1000)) + '0';
        str[len++] = '.';
        str[len++] = (temp / 10 - 10 * (temp / 100)) + '0';
        str[len++] = (temp - 10 * (temp / 10)) + '0';
        str[len++] = 'C';
    }
    return coap_make_response(scratch, outpkt, (const uint8_t *)str, len, id_hi, id_lo, &(inpkt->tok), COAP_RSPCODE_CONTENT, COAP_CONTENTTYPE_TEXT_PLAIN);
}

static const coap_endpoint_path_t path_humid = {1, {"humidity"}};
static int handle_get_humid(coap_rw_buffer_t *scratch, const coap_packet_t *inpkt, coap_packet_t *outpkt, uint8_t id_hi, uint8_t id_lo)
{
    signed long humid;
    unsigned char str[4];
    size_t len = 0;

    humid = htu21d_humid();
    if (humid > 99) {
        str[len++] = '1';
        str[len++] = '0';
        str[len++] = '0';
        str[len++] = '%';
    } else {
        if (humid > 10)
          str[len++] = humid / 10 + '0';
        str[len++] = (humid - 10 * (humid / 10)) + '0';
        str[len++] = '%';
    }
    return coap_make_response(scratch, outpkt, (const uint8_t *)str, len, id_hi, id_lo, &(inpkt->tok), COAP_RSPCODE_CONTENT, COAP_CONTENTTYPE_TEXT_PLAIN);
}

const coap_endpoint_t endpoints[] =
{
    {COAP_METHOD_GET, handle_get_well_known_core, &path_well_known_core, "ct=40"},
    {COAP_METHOD_GET, handle_get_light, &path_light, "ct=0"},
    {COAP_METHOD_PUT, handle_put_light, &path_light, NULL},
    {COAP_METHOD_GET, handle_get_temp, &path_temp, "ct=0;if=HTU21D;rt=temperature"},
    {COAP_METHOD_GET, handle_get_humid, &path_humid, "ct=0;if=HTU21D;rt=relative-humidity"},
    {(coap_method_t)0, NULL, NULL}
};

void build_rsp(void)
{
    uint16_t len = rsplen;
    const coap_endpoint_t *ep = endpoints;
    int i;

    len--; // Null-terminated string

    while(NULL != ep->handler)
    {
        if (NULL == ep->core_attr) {
            ep++;
            continue;
        }

        if (0 < strlen(rsp)) {
            strncat(rsp, ",", len);
            len--;
        }

        strncat(rsp, "<", len);
        len--;

        for (i = 0; i < ep->path->count; i++) {
            strncat(rsp, "/", len);
            len--;

            strncat(rsp, ep->path->elems[i], len);
            len -= strlen(ep->path->elems[i]);
        }

        strncat(rsp, ">;", len);
        len -= 2;

        strncat(rsp, ep->core_attr, len);
        len -= strlen(ep->core_attr);

        ep++;
    }
}

