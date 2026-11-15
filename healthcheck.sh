#!/bin/sh
# 200 -> healthy. 401 -> healthy, basic auth is enabled.
code=$(curl -s -o /dev/null --max-time 4 -w '%{http_code}' http://127.0.0.1:8080/ || true)
[ "$code" = "200" ] || [ "$code" = "401" ]
