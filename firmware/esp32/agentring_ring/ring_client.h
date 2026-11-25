// ring_client.h — frame transport for the LED ring.

#pragma once

#include <stdint.h>

void ringReset();
void ringStopMdns();
void ringEnsureMdns();
void ringPoll(uint32_t now);
