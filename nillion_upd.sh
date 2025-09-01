#!/bin/bash

APP_TOML="/home/ritual/.nillionapp/config/app.toml"

echo "Updating API settings in $APP_TOML..."

awk '
/^\[api\]/ { in_api_section = 1 }
in_api_section && /^enable = false/ {
    sub(/enable = false/, "enable = true");
    in_api_section = 0
}
{ print }
' "$APP_TOML" > "${APP_TOML}.tmp" && mv "${APP_TOML}.tmp" "$APP_TOML"

echo "API settings updated in $APP_TOML."

# Create a tmux session with two windows split horizontally
tmux new-session -d -s nillion
#tmux send-keys "$command_to_execute" C-m
tmux -2 attach-session -d
