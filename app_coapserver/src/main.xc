// Copyright (c) 2011, XMOS Ltd, All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

#include <platform.h>
#include <stddef.h>
#include <stdint.h>
#include "print.h"
#include "xtcp.h"
#include "ethernet_board_support.h"

#include "xtcp_conf.h"

#include "coapapi.h"

// These intializers are taken from the ethernet_board_support.h header for
// XMOS dev boards. If you are using a different board you will need to
// supply explicit port structure intializers for these values
#if XTCP_SEPARATE_MAC
on ETHERNET_DEFAULT_TILE: otp_ports_t otp_ports = OTP_PORTS_INITIALIZER;

// Here are the port definitions required by ethernet
// The intializers are taken from the ethernet_board_support.h header for
// XMOS dev boards. If you are using a different board you will need to
// supply explicit port structure intializers for these values
smi_interface_t smi = ETHERNET_DEFAULT_SMI_INIT;
mii_interface_t mii = ETHERNET_DEFAULT_MII_INIT;
ethernet_reset_interface_t eth_rst = ETHERNET_DEFAULT_RESET_INTERFACE_INIT;
#else
ethernet_xtcp_ports_t xtcp_ports =
    {on ETHERNET_DEFAULT_TILE: OTP_PORTS_INITIALIZER,
     ETHERNET_DEFAULT_SMI_INIT,
     ETHERNET_DEFAULT_MII_INIT_lite,
     ETHERNET_DEFAULT_RESET_INTERFACE_INIT};
#endif


// IP Config - change this to suit your network.  Leave with all
// 0 values to use DHCP/AutoIP
xtcp_ipconfig_t ipconfig = {
		{ 192, 168, 0, 2 }, // ip address (eg 192,168,0,2)
		{ 255, 255, 255, 0 }, // netmask (eg 255,255,255,0)
		{ 192, 168, 0, 1 } // gateway (eg 192,168,0,1)
};


#define TX_BUFFER_SIZE 300
#define RX_BUFFER_SIZE 300
#define INCOMING_PORT 15533
#define BROADCAST_INTERVAL 600000000
#define BROADCAST_PORT 15534

/** Simple UDP reflection thread.
 *
 * This thread does two things:
 *
 *   - Reponds to incoming packets on port INCOMING_PORT and
 *     with a packet with the same content back to the sender.
 *   - Periodically sends out a fixed packet to a broadcast IP address.
 *
 */
void udp_reflect(chanend c_xtcp)
{
  xtcp_connection_t conn;  // A temporary variable to hold
                           // connections associated with an event
  xtcp_connection_t responding_connection; // The connection to the remote end
                                           // we are responding to
  xtcp_connection_t broadcast_connection; // The connection out to the broadcast
                                          // address
  xtcp_ipaddr_t broadcast_addr = {255,255,255,255};
  int send_flag = 0;  // This flag is set when the thread is in the
                      // middle of sending a response packet
  int broadcast_send_flag = 0; // This flag is set when the thread is in the
                               // middle of sending a broadcast packet
  timer tmr;
  unsigned int time;

  // The buffers for incoming data, outgoing responses and outgoing broadcast
  // messages
  char rx_buffer[RX_BUFFER_SIZE];
  char tx_buffer[TX_BUFFER_SIZE];
  char broadcast_buffer[RX_BUFFER_SIZE];

  int response_len;  // The length of the response the thread is sending
  size_t tx_sz;
  int tx_len;
  int rc;
  int broadcast_len; // The lenght of the broadcast message the thread is
                     // sending


  // Maintain track of two connections. Initially they are not initialized
  // (which can be represented by setting their ID to -1
  responding_connection.id = -1;
  broadcast_connection.id = -1;

  // Instruct server to listen and create new connections on the incoming port
  xtcp_listen(c_xtcp, INCOMING_PORT, XTCP_PROTOCOL_UDP);

  tmr :> time;
  while (1) {
    select {

    // Respond to an event from the tcp server
    case xtcp_event(c_xtcp, conn):
      switch (conn.event)
        {
        case XTCP_IFUP:
          printstrln("Interface UP");
          // When the interface goes up, set up the broadcast connection.
          // This connection will persist while the interface is up
          // and is only used for outgoing broadcast messages
          xtcp_connect(c_xtcp,
                       BROADCAST_PORT,
                       broadcast_addr,
                       XTCP_PROTOCOL_UDP);
          break;
        case XTCP_IFDOWN:
          printstrln("Interface DOWN");
          // Tidy up and close any connections we have open
          if (responding_connection.id != -1) {
            xtcp_close(c_xtcp, responding_connection);
            responding_connection.id = -1;
          }
          if (broadcast_connection.id != -1) {
            xtcp_close(c_xtcp, broadcast_connection);
            broadcast_connection.id = -1;
          }
          break;
        case XTCP_NEW_CONNECTION:

          // The tcp server is giving us a new connection.
          // It is either a remote host connecting on the listening port
          // or the broadcast connection the threads asked for with
          // the xtcp_connect() call
          if (XTCP_IPADDR_CMP(conn.remote_addr, broadcast_addr)) {
            // This is the broadcast connection
            printstr("New broadcast connection established:");
            printintln(conn.id);
            broadcast_connection = conn;
          }
          else {
            // This is a new connection to the listening port
            printstr("New connection to listening port:");
            printintln(conn.local_port);
            if (responding_connection.id == -1) {
              responding_connection = conn;
            }
            else {
              printstr("Cannot handle new connection");
              xtcp_close(c_xtcp, conn);
            }
          }
          break;
        case XTCP_RECV_DATA:
          // When we get a packet in:
          //
          //  - fill the tx buffer
          //  - initiate a send on that connection
          //
          response_len = xtcp_recv_count(c_xtcp, rx_buffer, RX_BUFFER_SIZE);
          printstr("Got data: ");
          printint(response_len);
          printstrln(" bytes");

          for (int i=0;i<response_len;i++)
            tx_buffer[i] = rx_buffer[i];

          tx_sz = TX_BUFFER_SIZE;
          if(0 != (rc = coap_simple(rx_buffer, response_len, tx_buffer, &tx_sz))) {
              printstr("Error parsing CoAP packet, rc = ");
              printintln(rc);
              break;
          }
          tx_len = tx_sz;

          if (!send_flag) {
            xtcp_init_send(c_xtcp, conn);
            send_flag = 1;
            printstrln("Responding");
          }
          else {
            // Cannot respond here since the send buffer is being used
          }
          break;
      case XTCP_REQUEST_DATA:
      case XTCP_RESEND_DATA:
        // The tcp server wants data, this may be for the broadcast connection
        // or the reponding connection

        if (conn.id == broadcast_connection.id) {
          xtcp_send(c_xtcp, broadcast_buffer, broadcast_len);
        }
        else {
          xtcp_send(c_xtcp, tx_buffer, tx_len);
        }
        break;
      case XTCP_SENT_DATA:
        xtcp_complete_send(c_xtcp);
        if (conn.id == broadcast_connection.id) {
          // When a broadcast message send is complete th connection is kept
          // open for the next one
          printstrln("Sent Broadcast");
          broadcast_send_flag = 0;
        }
        else {
          // When a reponse is sent, the connection is closed opening up
          // for another new connection on the listening port
          printstrln("Sent Response");
          xtcp_close(c_xtcp, conn);
          responding_connection.id = -1;
          send_flag = 0;
        }
        break;
      case XTCP_TIMED_OUT:
      case XTCP_ABORTED:
      case XTCP_CLOSED:
        printstr("Closed connection:");
        printintln(conn.id);
        break;
      case XTCP_ALREADY_HANDLED:
          break;
      }
      break;
    // This is the periodic case, it occurs every BROADCAST_INTERVAL
    // timer ticks
    case tmr when timerafter(time + BROADCAST_INTERVAL) :> void:
      printstrln("Timer expiry, will attempt to broadcast");
      // A broadcast message can be sent if the connection is established
      // and one is not already being sent on that connection
      if (broadcast_connection.id != -1 && !broadcast_send_flag)  {
        printstrln("Sending broadcast message");
        broadcast_len = 100;
        xtcp_init_send(c_xtcp, broadcast_connection);
        broadcast_send_flag = 1;
      } else {
        if (broadcast_connection.id == -1) {
          printstrln("No broadcast connection available, attempting to create");
          xtcp_connect(c_xtcp,
                       BROADCAST_PORT,
                       broadcast_addr,
                       XTCP_PROTOCOL_UDP);
        } else
            printstrln("Flags are wrong");
      }
      tmr :> time;
      break;
    }
  }
}

// Program entry point
int main(void) {
	chan xtcp[1];
#if XTCP_SEPARATE_MAC
	chan c_mac_rx[1];
	chan c_mac_tx[1];
#endif

	par
	{
#if XTCP_SEPARATE_MAC
		on ETHERNET_DEFAULT_TILE:
		{
			char mac_address[6];
			otp_board_info_get_mac(otp_ports, 0, mac_address);
			eth_phy_reset(eth_rst);
			smi_init(smi);
			eth_phy_config(1, smi);
			ethernet_server(mii,
			                null,
			                mac_address,
			                c_mac_rx, 1,
			                c_mac_tx, 1);
		}

		// The TCP/IP server thread
		on ETHERNET_DEFAULT_TILE:
		xtcp_server(c_mac_rx[0],
		                c_mac_tx[0],
		                xtcp,
		                1,
		                ipconfig);

		// Insert code to check link state and call uip_linkup, uip_linkdown
/*		This code is no good, violates parallel usage rules
		on ETHERNET_DEFAULT_TILE :
		{
			static int linkstate = 0;
			int status = smi_check_link_state(smi);
			if (!status && linkstate) {
				printstrln("Ethernet link down");
				uip_linkdown();
			}
			if (status && !linkstate) {
				printstrln("Ethernet link up");
				uip_linkup();
			}
			linkstate = status;
		}*/
#else
		// The TCP/IP server thread
               on ETHERNET_DEFAULT_TILE: ethernet_xtcp_server(xtcp_ports,
                                                              ipconfig,
                                                              xtcp,
                                                              1);
#endif

                // The simple udp reflector thread
                on stdcore[0]: udp_reflect(xtcp[0]);

	}
	return 0;
}
