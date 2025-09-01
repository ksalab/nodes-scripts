#!/bin/bas

command_to_execute="sudo journalctl -fu dcdnd -o cat --no-hostname"
command_to_execute_2="/opt/dcdn/pipe-tool list-nodes --node-registry-url=\"https://rpc.pipedev.network\""

# Create a tmux session with two windows split horizontally
tmux new-session -d -s pipe
tmux split-window -v
tmux select-pane -t 0
tmux send-keys "$command_to_execute" C-m
tmux select-pane -t 1
tmux send-keys "$command_to_execute_2" C-m
tmux -2 attach-session -d
