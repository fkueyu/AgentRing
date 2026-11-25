// portal_ui.h — HTML for the Wi-Fi captive portal.

#pragma once

#include <Arduino.h>
#include <IPAddress.h>

String portalPage(int scanCount, const String *ssids, const int *rssis,
                  const String &apSsid, const IPAddress &apIp);
String resultPage(bool ok, const String &message);
