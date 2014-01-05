#define XTCP_SEPARATE_MAC 1
#define XTCP_VERBOSE_DEBUG 1

#define UIP_CONF_LOGGING 1
#define UIP_CONF_STATISTICS 1

// Enable IP broadcast support
#define UIP_CONF_BROADCAST 1

// Support 3 UDP connections
#define UIP_CONF_UDP_CONNS 3

// Disable outgoing TCP connections
// #define UIP_ACTIVE_OPEN 0

// To save memory, limit TCP to 1 connection
#define UIP_CONF_MAX_CONNECTIONS 1
#define UIP_CONF_MAX_LISTENPORTS 1

/*
#define UIP_USE_AUTOIP 0
#define UIP_USE_DHCP 1
*/
