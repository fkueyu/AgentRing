// portal_ui.cpp — captive-portal HTML, kept separate from Wi-Fi state.

#include <Arduino.h>
#include <IPAddress.h>

#include "portal_ui.h"

static String htmlEscape(const String &input) {
  String out;
  out.reserve(input.length() + 8);
  for (size_t i = 0; i < input.length(); i++) {
    char c = input[i];
    switch (c) {
      case '<': out += "&lt;"; break;
      case '>': out += "&gt;"; break;
      case '&': out += "&amp;"; break;
      case '"': out += "&quot;"; break;
      case '\'': out += "&#39;"; break;
      default: out += c; break;
    }
  }
  return out;
}

String portalPage(int scanCount, const String *ssids, const int *rssis,
                      const String &apSsid, const IPAddress &apIp) {
  String page;
  page.reserve(4096);
  page += "<!doctype html><html lang=\"zh\"><head><meta charset=\"utf-8\">";
  page += "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">";
  page += "<title>AgentRing 配网</title><style>";
  page += "body{margin:0;padding:28px 18px;background:#0f1420;color:#e8edf7;font:15px/1.6 -apple-system,BlinkMacSystemFont,'PingFang SC',sans-serif}";
  page += "main{max-width:420px;margin:0 auto}h1{font-size:22px;margin:0 0 6px}p.hint{color:#8b97ad;font-size:13px}";
  page += "label{display:block;margin:18px 0 6px;color:#a9b5c8;font-size:13px}";
  page += "select,input{width:100%;box-sizing:border-box;padding:12px;border-radius:10px;border:1px solid #2a3446;background:#171e2c;color:#e8edf7;font-size:16px}";
  page += "button{width:100%;margin-top:22px;padding:13px;border:0;border-radius:10px;background:#4d6bfe;color:#fff;font-size:16px;font-weight:600}";
  page += "button:active{opacity:.8}a{color:#8aa4ff}.ok{color:#5ee0a0}.bad{color:#ff8080}";
  page += "</style></head><body><main>";
  page += "<h1>AgentRing 配网</h1>";
  page += "<p class=\"hint\">选择 2.4GHz Wi-Fi（ESP32-C3 不支持 5GHz）。保存后热点会自动关闭。</p>";
  page += "<form method=\"post\" action=\"/save\">";
  page += "<label>附近的网络</label><select name=\"ssid\">";
  if (scanCount == 0) {
    page += "<option value=\"\">（没扫描到，请在下面手动输入）</option>";
  }
  for (int i = 0; i < scanCount; i++) {
    page += "<option value=\"" + htmlEscape(ssids[i]) + "\">";
    page += htmlEscape(ssids[i]) + " (" + String(rssis[i]) + " dBm)";
    page += "</option>";
  }
  page += "</select>";
  page += "<label>或手动输入 SSID（隐藏网络）</label>";
  page += "<input name=\"manual\" placeholder=\"留空则使用上面选择\" autocomplete=\"off\" autocapitalize=\"off\">";
  page += "<label>密码</label>";
  page += "<input name=\"password\" type=\"password\" placeholder=\"开放网络留空\" autocomplete=\"off\">";
  page += "<button type=\"submit\">保存并连接</button>";
  page += "</form>";
  page += "<p class=\"hint\">热点：" + htmlEscape(apSsid) + " · 地址：http://" + apIp.toString() + "/</p>";
  page += "</main></body></html>";
  return page;
}

String resultPage(bool ok, const String &message) {
  String page;
  page.reserve(1024);
  page += "<!doctype html><html lang=\"zh\"><head><meta charset=\"utf-8\">";
  page += "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">";
  page += "<title>AgentRing 配网</title><style>";
  page += "body{margin:0;padding:36px 20px;background:#0f1420;color:#e8edf7;font:16px/1.6 -apple-system,BlinkMacSystemFont,'PingFang SC',sans-serif;text-align:center}";
  page += "main{max-width:420px;margin:0 auto}a{color:#8aa4ff}";
  page += "</style></head><body><main>";
  page += ok ? "<h1 class=\"ok\">已连接</h1>" : "<h1 class=\"bad\">连接失败</h1>";
  page += "<p>" + htmlEscape(message) + "</p>";
  if (ok) {
    page += "<p>热点即将关闭，设备开始拉取灯环数据。</p>";
  } else {
    page += "<p><a href=\"/\">返回重试</a></p>";
  }
  page += "</main></body></html>";
  return page;
}
