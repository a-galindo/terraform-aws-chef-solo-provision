#!/bin/bash

app="DOWN"

while [ "$app" != "{\"status\":\"UP\"}" ]; do
## Curl the app in our local server to check if it is already up
app=`curl localhost:8484/actuator/health`

done

echo "App is $app"
