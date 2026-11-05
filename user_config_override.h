// Copie dans tasmota/user_config_override.h avant la compilation par le workflow GitHub.
// Sert aux deux firmwares : tasmota32-zbgw03-matter (complet) et
// tasmota32-zbgw03-matter-lite (FIRMWARE_ZBGW03_LITE).

#ifndef _USER_CONFIG_OVERRIDE_H_
#define _USER_CONFIG_OVERRIDE_H_

// eWeLink ZB-GW03 : le module Zigbee est un EFR32MG21 (Silicon Labs, firmware EmberZNet),
// qui parle EZSP. Le build ZBBridge Pro suppose un CC2652P (Texas Instruments, ZNP).
// Les deux protocoles s'excluent : un seul peut etre compile.
#undef  USE_ZIGBEE_ZNP
#define USE_ZIGBEE_EZSP

/*********************************************************************************************\
 * Version lite : Zigbee + Matter + regles, ZbBind et Device Groups, en Wi-Fi seulement
 *
 * Ce fichier est inclus a la fin de my_user_config.h, AVANT tasmota_configurations_ESP32.h :
 * un #undef ici ne peut pas annuler ce que le bloc FIRMWARE_ZBBRDGPRO redefinit ensuite
 * (Ethernet, InfluxDB, TCP bridge...). La version lite ne definit donc pas FIRMWARE_ZBBRDGPRO
 * (voir platformio_override.ini) et reprend ici ce qui reste utile de ce bloc.
\*********************************************************************************************/

#ifdef FIRMWARE_ZBGW03_LITE

// -- Repris du bloc FIRMWARE_ZBBRDGPRO -------------
#undef  MODULE
#define MODULE                 WEMOS
#undef  FALLBACK_MODULE
#define FALLBACK_MODULE        WEMOS

#define USE_ZIGBEE

#undef  USE_DOMOTICZ
#undef  USE_HOME_ASSISTANT
#undef  USE_ENERGY_SENSOR
#undef  USE_SHUTTER
#undef  USE_IR_REMOTE
#undef  USE_ARMTRONIX_DIMMERS
#undef  USE_PS_16_DZ
#undef  USE_SONOFF_IFAN
#undef  USE_ARILUX_RF
#undef  USE_EXS_DIMMER
#undef  USE_KEELOQ
#undef  USE_SONOFF_D1
#undef  USE_SHELLY_DIMMER

// Non repris du bloc FIRMWARE_ZBBRDGPRO, donc absents de la version lite :
//   USE_ETHERNET          Wi-Fi seulement (pilote, tache et tampons DMA de l'Ethernet)
//   USE_INFLUXDB          envoi vers InfluxDB
//   USE_TCP_BRIDGE        pont serie-TCP (Zigbee pilote par ZHA ou Zigbee2MQTT)
//   USE_SPI               aucun peripherique SPI sur le ZB-GW03
//   USE_I2C               l'EEPROM 0x50 ne sert pas (USE_ZIGBEE_EEPROM n'est pas active : les
//                         appareils Zigbee sont enregistres en flash) ; retire aussi les
//                         capteurs I2C actives par defaut
//   USE_TASMOTA_DISCOVERY decouverte MQTT

// -- Web et emulations Alexa -----------------------
#undef  USE_EMULATION_HUE
#undef  USE_EMULATION_WEMO
#undef  USE_GPIO_VIEWER

// -- Minuteries et lever/coucher du soleil ---------
#undef  USE_TIMERS
#undef  USE_TIMERS_WEB
#undef  USE_SUNRISE

// -- MQTT (le client MQTT fait partie du coeur de Tasmota et reste compile) --
#undef  SUPPORT_MQTT_EVENT
#undef  USE_TASMOTA_DISCOVERY

// -- Berry : extensions inutiles a Matter ----------
#undef  USE_AUTOCONF
#undef  USE_EXTENSION_MANAGER
#undef  USE_BERRY_PYTHON_COMPAT
#undef  USE_BERRY_TCPSERVER

// -- Materiel absent du ZB-GW03 --------------------
#undef  USE_SONOFF_RF
#undef  USE_RF_FLASH
#undef  USE_SONOFF_SC
#undef  USE_TUYA_MCU
#undef  USE_TUYA_TIME
#undef  USE_BUZZER
#undef  USE_DEEPSLEEP
#undef  ROTARY_V1
#undef  USE_AC_ZERO_CROSS_DIMMER
#undef  USE_PWM_DIMMER
#undef  USE_PWM_DIMMER_REMOTE
#undef  USE_DGR_LIGHT_SEQUENCE
#undef  USE_COUNTER
#undef  USE_DS18x20
#undef  USE_DHT
#undef  USE_ADC
#undef  USE_ESP32_SENSORS
#undef  USE_SERIAL_BRIDGE
#undef  USE_IMPROV
#undef  USE_CSE7761
#undef  USE_NETWORK_LIGHT_SCHEMES

// -- Pilotes de lumiere -----------------------------
// USE_LIGHT (le coeur) est garde : les plugins Matter des lumieres font "import light"
#undef  USE_WS2812
#undef  USE_MY92X1
#undef  USE_SM16716
#undef  USE_SM2135
#undef  USE_SM2335
#undef  USE_BP1658CJ
#undef  USE_BP5758D
#undef  USE_SONOFF_L1
#undef  USE_ELECTRIQ_MOODL
#undef  USE_LIGHT_PALETTE
#undef  USE_LIGHT_VIRTUAL_CT

// Gardes (valeurs par defaut de my_user_config.h) : USE_RULES et USE_UNISHOX_COMPRESSION
// (regles), USE_DEVICE_GROUPS et USE_DEVICE_GROUPS_SEND, USE_WEBSERVER, USE_BERRY,
// USE_WEBCLIENT_HTTPS, USE_LIGHT. Matter ajoute lui-meme mDNS (USE_DISCOVERY) et ses
// fonctions de chiffrement ; IPv6 (USE_IPV6) vient des options de compilation ESP32.

#endif  // FIRMWARE_ZBGW03_LITE

#endif  // _USER_CONFIG_OVERRIDE_H_
