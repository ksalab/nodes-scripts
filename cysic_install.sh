#!/bin/bash

# Define colors

if ! source <(curl -s https://ksalab.xyz/dl/ksalab_utils.sh); then
    echo "Failed to load utility script!"
    exit 1
fi

# Check if a second parameter is provided

if [ -n "$2" ]; then
    command_to_execute="curl -L https://github.com/cysic-labs/phase2_libs/releases/download/v1.0.0/setup_linux.sh > ~/setup_linux.sh && bash ~/setup_linux.sh $2 && cd ~/cysic-verifier/ && bash start.sh"
else
    command_to_execute="echo \"No EVM address specified\""
fi

# Create a tmux session with two windows split horizontally

title "Creating tmux session with two windows split horizontally..."
tmux new-session -d -s cysic || { error "Failed to create tmux session"; exit 1; }
tmux split-window -v || { error "Failed to split tmux window"; exit 1; }
tmux select-pane -t 0 || { error "Failed to select tmux pane"; exit 1; }
tmux send-keys "$command_to_execute" C-m || { error "Failed to send command to tmux"; exit 1; }
info "Command sent to tmux session 'cysic'."
tmux -2 attach-session -t cysic || { error "Failed to attach to tmux session"; exit 1; }

#
