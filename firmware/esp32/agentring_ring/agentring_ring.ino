// AgentRing 固件：ESP32-C3 + 24 颗 WS2812B
//
// 只做一件事：拉取电脑上 daemon 的 /frame（72 字节 RGB），转成 GRB 推给灯环。
// 布局、配色、亮度、gamma 都在电脑侧计算（见 daemon/src/frame.mjs），
// 所以换配色或动效不用重新烧录。
//
// Wi-Fi 不写死在代码里：
//   - 没有配置或连不上时，开一个临时热点 AgentRing-XXXX（开放），
//     手机连上后会自动弹出配网页（或手动打开 http://192.168.4.1/）。
//   - 配置保存在 NVS，重新烧录固件也不会丢。
//   - 串口 115200 也保留 wifi / wifi status / wifi clear / wifi portal / reboot / info。

#include <WiFi.h>
#include <Preferences.h>
#include <WebServer.h>
#include <DNSServer.h>

#include "config.h"
#include "leds.h"
#include "portal_ui.h"
#include "ring_client.h"


static int s_reconnectFailures = 0;

static Preferences s_prefs;
static String s_ssid;
static String s_pass;

static const int SCAN_MAX = 16;
static String s_scanSsid[SCAN_MAX];
static int s_scanRssi[SCAN_MAX];
static int s_scanCount = 0;

static WebServer s_web(80);
static DNSServer s_dns;
static String s_apSsid;
static bool s_portal = false;
static bool s_webConfigured = false;
static uint32_t s_lastPortalFrame = 0;
static uint32_t s_lastStaRetry = 0;

// MARK: - Wi-Fi 配置（NVS）

static void loadWifiConfig() {
  s_prefs.begin("agentring", false);
  s_ssid = s_prefs.getString("ssid", "");
  s_pass = s_prefs.getString("pass", "");
  if (s_ssid.isEmpty()) {
    String fallback = WIFI_SSID;
    // 忽略模板里的占位符，避免把 "YOUR_WIFI" 当成真 SSID 去连。
    if (fallback.length() && fallback != "YOUR_WIFI") {
      s_ssid = fallback;
      s_pass = WIFI_PASS;
    }
  }
}

static void saveWifiConfig(const String &ssid, const String &pass) {
  s_ssid = ssid;
  s_pass = pass;
  s_prefs.putString("ssid", ssid);
  s_prefs.putString("pass", pass);
}

static void clearWifiConfig() {
  s_ssid = "";
  s_pass = "";
  s_prefs.remove("ssid");
  s_prefs.remove("pass");
}

static void printWifiStatus() {
  Serial.printf("ssid: %s\n", s_ssid.length() ? s_ssid.c_str() : "(not configured)");
  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("ip: %s\n", WiFi.localIP().toString().c_str());
    Serial.printf("rssi: %d dBm\n", WiFi.RSSI());
    Serial.printf("mac: %s\n", WiFi.macAddress().c_str());
  } else {
    Serial.println("state: not connected");
  }
  if (s_portal) {
    Serial.printf("portal: %s  http://%s/\n", s_apSsid.c_str(), WiFi.softAPIP().toString().c_str());
  }
}

static bool connectWifi(bool keepAp = false) {
  if (!s_ssid.length()) {
    Serial.println("wifi: no credentials. Portal or serial 'wifi' can configure it.");
    return false;
  }
  WiFi.mode(keepAp ? WIFI_AP_STA : WIFI_STA);
  WiFi.setSleep(false);  // 关省电，帧率才稳
  WiFi.begin(s_ssid.c_str(), s_pass.c_str());
  Serial.printf("connecting to \"%s\"", s_ssid.c_str());
  uint32_t start = millis();
  uint32_t lastDot = 0;
  while (WiFi.status() != WL_CONNECTED && millis() - start < WIFI_CONNECT_TIMEOUT_MS) {
    // Keep the ring breathing while the 15s connect attempt blocks loop().
    showStatus(millis(), s_portal);
    if (millis() - lastDot >= 200) {
      Serial.print('.');
      lastDot = millis();
    }
    delay(20);
  }
  bool ok = WiFi.status() == WL_CONNECTED;
  Serial.printf("\nWi-Fi %s ip=%s\n", ok ? "ok" : "failed", WiFi.localIP().toString().c_str());
  if (ok) {
    s_reconnectFailures = 0;
    ringEnsureMdns();
  }
  return ok;
}

// MARK: - 扫描与串口配置

static void scanWifi() {
  Serial.println("scanning 2.4GHz networks...");
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  int found = WiFi.scanNetworks();
  s_scanCount = 0;
  for (int i = 0; i < found && i < SCAN_MAX; i++) {
    s_scanSsid[i] = WiFi.SSID(i);
    s_scanRssi[i] = WiFi.RSSI(i);
    s_scanCount = i + 1;
    Serial.printf("  %2d) %s  %d dBm%s\n", i + 1, s_scanSsid[i].c_str(), s_scanRssi[i],
                  WiFi.encryptionType(i) == WIFI_AUTH_OPEN ? "  (open)" : "");
  }
  if (found <= 0) Serial.println("  (none; check 2.4GHz and antenna)");
  WiFi.scanDelete();
}

static String readLine(uint32_t timeoutMs) {
  String line;
  uint32_t start = millis();
  while (millis() - start < timeoutMs) {
    while (Serial.available()) {
      char c = (char)Serial.read();
      if (c == '\r') continue;
      if (c == '\n') return line;
      if (c == '\b' || c == 0x7f) {
        if (line.length()) line.remove(line.length() - 1);
        continue;
      }
      if (line.length() < 128) line += c;
    }
    delay(10);
  }
  return line;
}

static bool serialConfig() {
  Serial.println();
  Serial.println("== Wi-Fi configuration ==");
  scanWifi();
  Serial.println("SSID (number or name, empty to cancel):");
  String ssid = readLine(120000);
  if (!ssid.length()) {
    Serial.println("cancelled");
    return false;
  }
  bool numeric = true;
  for (size_t i = 0; i < ssid.length(); i++) {
    if (!isDigit(ssid[i])) { numeric = false; break; }
  }
  if (numeric) {
    int index = ssid.toInt();
    if (index >= 1 && index <= s_scanCount) ssid = s_scanSsid[index - 1];
  }
  Serial.println("Password (empty for an open network):");
  String pass = readLine(120000);

  saveWifiConfig(ssid, pass);
  Serial.printf("saved \"%s\" to NVS\n", ssid.c_str());

  WiFi.disconnect(true);
  delay(200);
  if (connectWifi()) {
    ringReset();
    return true;
  }
  Serial.println("connect failed. Type 'wifi' to try again, or 'wifi portal'.");
  return false;
}

// MARK: - 配网热点（captive portal）

static void handlePortalRoot() {
  s_web.send(200, "text/html; charset=utf-8",
              portalPage(s_scanCount, s_scanSsid, s_scanRssi, s_apSsid, WiFi.softAPIP()));
}

static void stopPortal();

static void handlePortalSave() {
  String ssid = s_web.arg("manual");
  ssid.trim();
  if (!ssid.length()) ssid = s_web.arg("ssid");
  String pass = s_web.arg("password");

  if (!ssid.length()) {
    s_web.send(400, "text/html; charset=utf-8", resultPage(false, "请选择或输入 Wi-Fi 名称。"));
    return;
  }

  saveWifiConfig(ssid, pass);
  bool ok = connectWifi(true);
  if (ok) {
    ringReset();
    String message = String("已连接 \"") + ssid + "\" · IP " + WiFi.localIP().toString();
    s_web.send(200, "text/html; charset=utf-8", resultPage(true, message));
    delay(300);
    stopPortal();
  } else {
    String message = String("连接 \"") + ssid + "\" 失败，请检查密码、信号，或换一个 2.4GHz 网络。";
    s_web.send(200, "text/html; charset=utf-8", resultPage(false, message));
  }
}

static void handlePortalNotFound() {
  s_web.sendHeader("Location", String("http://") + WiFi.softAPIP().toString() + "/", true);
  s_web.send(302, "text/plain", "");
}

static void startPortal() {
  if (s_portal) return;
  Serial.println("starting config portal...");
  showConfigMode(millis());
  scanWifi();

  uint64_t chip = ESP.getEfuseMac();
  char suffix[5];
  snprintf(suffix, sizeof(suffix), "%04X", (unsigned)(chip & 0xFFFF));
  s_apSsid = String(AP_SSID_PREFIX) + "-" + suffix;

  WiFi.mode(WIFI_AP_STA);
  // Keep the setup AP off channel 1 by default: many 2.4 GHz routers use it,
  // and an AP inches from the ring otherwise jams its own station attempts.
  const uint8_t portalChannel = 6;
  bool ap = strlen(AP_PASSWORD)
                ? WiFi.softAP(s_apSsid.c_str(), AP_PASSWORD, portalChannel)
                : WiFi.softAP(s_apSsid.c_str(), nullptr, portalChannel);
  if (!ap) {
    Serial.println("softAP failed");
    return;
  }

  IPAddress ip = WiFi.softAPIP();
  s_dns.start(53, "*", ip);
  if (!s_webConfigured) {
    s_web.on("/", HTTP_GET, handlePortalRoot);
    s_web.on("/save", HTTP_POST, handlePortalSave);
    s_web.onNotFound(handlePortalNotFound);
    s_webConfigured = true;
  }
  s_web.begin();
  s_portal = true;
  s_lastPortalFrame = 0;
  s_lastStaRetry = millis();
  Serial.printf("AP: %s  ch%d  http://%s/\n", s_apSsid.c_str(), (int)portalChannel,
                ip.toString().c_str());
}

static void stopPortal() {
  if (!s_portal) return;
  s_web.stop();
  s_dns.stop();
  WiFi.softAPdisconnect(true);
  s_portal = false;
  WiFi.mode(WIFI_STA);
  ringEnsureMdns();
  s_reconnectFailures = 0;
  Serial.println("portal stopped");
}

// MARK: - 串口命令

static void handleSerialCommand(String line) {
  line.trim();
  if (!line.length()) return;
  String cmd = line;
  cmd.toLowerCase();

  if ((cmd == "wifi" || cmd == "wifi set") && s_portal) {
    Serial.printf("portal already active: join %s, open http://%s/\n", s_apSsid.c_str(),
                  WiFi.softAPIP().toString().c_str());
  } else if (cmd == "wifi" || cmd == "wifi set") {
    serialConfig();
  } else if (cmd == "wifi portal") {
    startPortal();
  } else if (cmd == "wifi status") {
    printWifiStatus();
  } else if (cmd == "wifi clear") {
    clearWifiConfig();
    WiFi.disconnect(true);
    ringStopMdns();
    Serial.println("wifi cleared. Type 'wifi' or 'wifi portal' to configure.");
  } else if (cmd == "info") {
    Serial.printf("LED: GPIO%d x%d, frame %dms\n", LED_GPIO, LED_COUNT, FRAME_INTERVAL_MS);
    printWifiStatus();
  } else if (cmd == "reboot") {
    Serial.println("rebooting...");
    delay(100);
    ESP.restart();
  } else if (cmd == "help") {
    Serial.println("commands: wifi | wifi portal | wifi status | wifi clear | info | reboot");
  } else {
    Serial.println("unknown command; type 'help'");
  }
}

static void pollSerial() {
  static String line;
  while (Serial.available()) {
    char c = (char)Serial.read();
    if (c == '\r') continue;
    if (c == '\n') {
      if (line.length()) handleSerialCommand(line);
      line = "";
    } else if (c == '\b' || c == 0x7f) {
      if (line.length()) line.remove(line.length() - 1);
    } else if (line.length() < 128) {
      line += c;
    }
  }
}

// MARK: - Arduino

void setup() {
  Serial.begin(115200);
  delay(200);
  ledsBegin();

  Serial.println("\nAgentRing ring firmware");
  Serial.printf("LED: GPIO%d x%d, frame %dms\n", LED_GPIO, LED_COUNT, FRAME_INTERVAL_MS);
  Serial.println("commands: wifi | wifi portal | wifi status | wifi clear | info | reboot");

  loadWifiConfig();
  if (!connectWifi()) startPortal();
}

void loop() {
  uint32_t now = millis();
  pollSerial();

  if (s_portal) {
    s_dns.processNextRequest();
    s_web.handleClient();
    // 25fps is plenty for a breathing animation; don't burn CPU at ~300fps.
    if (now - s_lastPortalFrame >= FRAME_INTERVAL_MS) {
      s_lastPortalFrame = now;
      showConfigMode(now);
    }
    // A saved network may come back after a router reboot. Retry it in the
    // background so the AP can close itself, but never while a phone is on the
    // portal page (softAPgetStationNum > 0), which would block the page.
    if (s_ssid.length() && WiFi.softAPgetStationNum() == 0 && now - s_lastStaRetry >= 60000) {
      s_lastStaRetry = now;
      if (connectWifi(true)) {
        stopPortal();
        return;
      }
    }
    delay(2);
    return;
  }

  if (WiFi.status() != WL_CONNECTED) {
    ringReset();
    ringStopMdns();
    if (!s_ssid.length()) {
      startPortal();
    } else if (!connectWifi()) {
      if (++s_reconnectFailures >= 3) {
        s_reconnectFailures = 0;
        showConfigMode(millis());
        startPortal();
      }
    }
    return;
  }

  ringPoll(now);
}
