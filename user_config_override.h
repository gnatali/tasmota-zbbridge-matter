// Copie dans tasmota/user_config_override.h avant la compilation
// (workflow GitHub et build-zbbridge-matter.ps1).

#ifndef _USER_CONFIG_OVERRIDE_H_
#define _USER_CONFIG_OVERRIDE_H_

// eWeLink ZB-GW03 : le module Zigbee est un EFR32MG21 (Silicon Labs, firmware EmberZNet),
// qui parle EZSP. Le build ZBBridge Pro suppose un CC2652P (Texas Instruments, ZNP).
// Les deux protocoles s'excluent : un seul peut etre compile.
#undef  USE_ZIGBEE_ZNP
#define USE_ZIGBEE_EZSP

#endif  // _USER_CONFIG_OVERRIDE_H_
