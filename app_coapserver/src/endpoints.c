#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <math.h>
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

static const coap_endpoint_path_t path_humid_temp = {2, {"humidity", "temperature"}};
static int handle_get_humid_temp(coap_rw_buffer_t *scratch, const coap_packet_t *inpkt, coap_packet_t *outpkt, uint8_t id_hi, uint8_t id_lo)
{
    signed long temp;
    char str[12];
    size_t len = 0;

    temp = htu21d_temp();
    len = snprintf(str, 12, "%ld.%2.2ld  C", temp / 100, temp - 100 * (temp / 100));
    str[len-3] = 0xc2;
    str[len-2] = 0xb0;
    return coap_make_response(scratch, outpkt, (const uint8_t *)str, len, id_hi, id_lo, &(inpkt->tok), COAP_RSPCODE_CONTENT, COAP_CONTENTTYPE_TEXT_PLAIN);
}

static const coap_endpoint_path_t path_humid = {1, {"humidity"}};
static int handle_get_humid(coap_rw_buffer_t *scratch, const coap_packet_t *inpkt, coap_packet_t *outpkt, uint8_t id_hi, uint8_t id_lo)
{
    signed long humid;
    char str[4];
    size_t len = 0;

    humid = htu21d_humid();
    len = snprintf(str, 4, "%ld%%", humid);
    return coap_make_response(scratch, outpkt, (const uint8_t *)str, len, id_hi, id_lo, &(inpkt->tok), COAP_RSPCODE_CONTENT, COAP_CONTENTTYPE_TEXT_PLAIN);
}

static const coap_endpoint_path_t path_comphumid = {2, {"humidity", "compensated"}};
static int handle_get_comphumid(coap_rw_buffer_t *scratch, const coap_packet_t *inpkt, coap_packet_t *outpkt, uint8_t id_hi, uint8_t id_lo)
{
    const signed short coeff = -15;
    signed long temp,humid;
    char str[4];
    size_t len = 0;

    temp = htu21d_temp();  // Fixed point, *100
    humid = htu21d_humid() + (25 - temp/100) * coeff / 100;
    len = snprintf(str, 4, "%ld%%", humid);
    return coap_make_response(scratch, outpkt, (const uint8_t *)str, len, id_hi, id_lo, &(inpkt->tok), COAP_RSPCODE_CONTENT, COAP_CONTENTTYPE_TEXT_PLAIN);
}

static const coap_endpoint_path_t path_dewpoint = {2, {"humidity", "dewpoint"}};
static int handle_get_dewpoint(coap_rw_buffer_t *scratch, const coap_packet_t *inpkt, coap_packet_t *outpkt, uint8_t id_hi, uint8_t id_lo)
{
    signed long temp,humid,ldp;
    float pp, dewpoint;
    char str[12];
    size_t len = 0;

    temp = htu21d_temp();  // Fixed point, *100
    humid = htu21d_humid();

    pp = pow(10, 8.1332 - 176239.0 / (temp + 23566));
    dewpoint = -( 1762.39 / (log10(humid * pp / 100) - 8.1332) + 235.66);

    ldp = floor(dewpoint);
    len = snprintf(str, 12, "%ld.%2.2ld  C", ldp, (signed long)(100 * (dewpoint - ldp)));
    str[len-3] = 0xc2;
    str[len-2] = 0xb0;
    return coap_make_response(scratch, outpkt, (const uint8_t *)str, len, id_hi, id_lo, &(inpkt->tok), COAP_RSPCODE_CONTENT, COAP_CONTENTTYPE_TEXT_PLAIN);
}

static const coap_endpoint_path_t path_pres = {1, {"pressure"}};
static int handle_get_pres(coap_rw_buffer_t *scratch, const coap_packet_t *inpkt, coap_packet_t *outpkt, uint8_t id_hi, uint8_t id_lo)
{
    unsigned long pres;
    char str[14];
    size_t len = 0;

    pres = mpl3115a2_pres();
    len = snprintf(str, 14, "%lu.%2.2lu Pa", pres >> 2, 25 * (pres & 0x03));
    return coap_make_response(scratch, outpkt, (const uint8_t *)str, len, id_hi, id_lo, &(inpkt->tok), COAP_RSPCODE_CONTENT, COAP_CONTENTTYPE_TEXT_PLAIN);
}

static const coap_endpoint_path_t path_pres_temp = {2, {"pressure", "temperature"}};
static int handle_get_pres_temp(coap_rw_buffer_t *scratch, const coap_packet_t *inpkt, coap_packet_t *outpkt, uint8_t id_hi, uint8_t id_lo)
{
    signed short temp;
    char str[12];
    size_t len = 0;

    temp = mpl3115a2_temp();
    len = snprintf(str, 12, "%hd.%4.4hd  C", temp >> 4, 625 * (temp & 0x0F));
    str[len-3] = 0xc2;
    str[len-2] = 0xb0;
    return coap_make_response(scratch, outpkt, (const uint8_t *)str, len, id_hi, id_lo, &(inpkt->tok), COAP_RSPCODE_CONTENT, COAP_CONTENTTYPE_TEXT_PLAIN);
}

const coap_endpoint_t endpoints[] =
{
    {COAP_METHOD_GET, handle_get_well_known_core, &path_well_known_core, NULL},
    {COAP_METHOD_GET, handle_get_light, &path_light, "ct=0"},
    {COAP_METHOD_PUT, handle_put_light, &path_light, NULL},
    {COAP_METHOD_GET, handle_get_humid, &path_humid, "ct=0;if=HTU21D;rt=relative"},
    {COAP_METHOD_GET, handle_get_humid_temp, &path_humid_temp, "ct=0;if=HTU21D"},
    {COAP_METHOD_GET, handle_get_comphumid, &path_comphumid, "ct=0;if=HTU21D;rt=temperature-compensated"},
    {COAP_METHOD_GET, handle_get_dewpoint, &path_dewpoint, "ct=0;if=HTU21D"},
    {COAP_METHOD_GET, handle_get_pres, &path_pres, "ct=0;if=MPL3115A2"},
    {COAP_METHOD_GET, handle_get_pres_temp, &path_pres_temp, "ct=0;if=MPL3115A2"},
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

