// ring_client.cpp — mDNS discovery and the persistent /frame stream client.
//
// The daemon pushes 72-byte RGB frames over one raw TCP connection. There is
// no HTTP request per frame, so Wi-Fi round-trip latency no longer caps the
// animation at ~22 fps.

#include <Arduino.h>
#include <WiFi.h>
#include <ESPmDNS.h>

#include "config.h"
#include "leds.h"
#include "ring_client.h"

static String s_host;
static WiFiClient s_stream;
static bool s_resolved = false;
static bool s_mdns = false;
static int s_failures = 0;
static int s_resolveErrors = 0;
static int s_fetchErrors = 0;
static uint32_t s_lastShownAt = 0;

static void ensureMdns() {
  if (!s_mdns && WiFi.status() == WL_CONNECTED) {
    s_mdns = MDNS.begin("agentring-ring");
    if (s_mdns) Serial.println("mDNS: agentring-ring.local");
  }
}

// MARK: - 网络

// 有静态地址就用静态地址；否则问 mDNS 要 _agentring._tcp，并选同一子网的 IPv4。
static bool resolve() {
  if (strlen(AGENTRING_HOST) > 0) {
    s_host = AGENTRING_HOST;
    Serial.printf("static: %s:%u\n", s_host.c_str(), (unsigned)AGENTRING_STREAM_PORT);
    return true;
  }

  int found = MDNS.queryService("agentring", "tcp");
  if (found <= 0) return false;

  // A Mac has many interfaces (Wi-Fi, bridges, Tailscale...). MDNS.address(0)
  // can be 0.0.0.0 or a CGNAT address, which makes every connection fail.
  // Pick the IPv4 address on the same subnet as our STA interface instead.
  IPAddress local = WiFi.localIP();
  IPAddress chosen;
  for (int i = 0; i < found; i++) {
    IPAddress a = MDNS.address(i);
    uint16_t port = MDNS.port(i);
    if (port == 0 || a[0] == 0 || a[0] == 255) continue;
    if (a[0] == 169 && a[1] == 254) continue;  // link-local
    if (a[0] == local[0] && a[1] == local[1] && a[2] == local[2]) {
      chosen = a;
      break;
    }
  }

  if (chosen[0] == 0) {
    if (s_resolveErrors++ < 5) {
      Serial.printf("mDNS: no same-subnet IPv4 for local %s (%d result(s))\n",
                    local.toString().c_str(), found);
      for (int i = 0; i < found; i++) {
        Serial.printf("  candidate %s:%u\n", MDNS.address(i).toString().c_str(), MDNS.port(i));
      }
    }
    return false;
  }

  s_resolveErrors = 0;
  s_host = chosen.toString();
  Serial.printf("mDNS %s -> %s:%u\n", MDNS.hostname(0).c_str(), s_host.c_str(),
                (unsigned)AGENTRING_STREAM_PORT);
  return true;
}

static bool connectStream() {
  if (s_stream.connected()) return true;
  s_stream.stop();
  if (!s_stream.connect(s_host.c_str(), AGENTRING_STREAM_PORT)) {
    if (s_fetchErrors++ < 5) {
      Serial.printf("stream: connect %s:%u failed\n", s_host.c_str(),
                    (unsigned)AGENTRING_STREAM_PORT);
    }
    return false;
  }
  s_stream.setNoDelay(true);
  s_stream.setTimeout(STREAM_READ_TIMEOUT_MS);
  Serial.printf("stream: %s:%u\n", s_host.c_str(), (unsigned)AGENTRING_STREAM_PORT);
  return true;
}

static bool fetchFrame(uint8_t *out, size_t expected) {
  if (!connectStream()) return false;

  uint32_t start = millis();
  size_t got = 0;
  while (got < expected && millis() - start < STREAM_READ_TIMEOUT_MS) {
    int n = s_stream.read(out + got, expected - got);
    if (n > 0) {
      got += n;
    } else if (!s_stream.connected()) {
      break;
    } else {
      delay(1);
    }
  }

  if (got == expected) {
    s_fetchErrors = 0;
    // If the network delivered a small burst while we were rendering, keep
    // only the newest complete frame. This avoids replaying stale frames when
    // we pace the display below.
    while (s_stream.available() >= (int)expected) {
      uint8_t newer[LED_COUNT * 3];
      if (s_stream.read(newer, expected) != (int)expected) break;
      memcpy(out, newer, expected);
    }
    return true;
  }

  if (s_fetchErrors++ < 5) {
    Serial.printf("frame: stream short read %u/%u\n", (unsigned)got, (unsigned)expected);
  }
  // A dropped connection must be re-estimated; do not leave a half-read frame.
  s_stream.stop();
  return false;
}

void ringReset() {
  s_resolved = false;
  s_failures = 0;
  s_lastShownAt = 0;
  s_stream.stop();
}

void ringStopMdns() {
  if (s_mdns) {
    MDNS.end();
    s_mdns = false;
  }
}

void ringEnsureMdns() {
  ensureMdns();
}

void ringPoll(uint32_t now) {
  ensureMdns();

  if (!s_resolved) {
    if (!resolve()) {
      showOffline(now);
      delay(1000);
      return;
    }
    s_resolved = true;
  }

  static uint8_t frame[LED_COUNT * 3];
  if (fetchFrame(frame, sizeof(frame))) {
    // Keep the LED refresh on the documented ~30 fps cadence even if TCP
    // delivers a burst faster than the strip can be updated.
    if (s_lastShownAt != 0) {
      uint32_t elapsed = millis() - s_lastShownAt;
      if (elapsed < FRAME_INTERVAL_MS) delay(FRAME_INTERVAL_MS - elapsed);
    }
    s_failures = 0;
    ledsShow(frame);
    s_lastShownAt = millis();
  } else if (++s_failures >= OFFLINE_AFTER_FAILURES) {
    s_failures = 0;
    s_resolved = false;  // 重新发现
    showOffline(now);
  }
}
