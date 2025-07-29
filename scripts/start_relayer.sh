#!/bin/bash
# Set up a relayer

echo "> Running relayer in a tmux session"
if [ $RELAYER == "hermes" ]; then
    tmux new-session -d -s relayer "$HOME/.hermes/hermes | tee relayer.log"
elif [ $RELAYER == "rly" ]; then
    tmux new-session -d -s relayer "$HOME/.relayer/rly | tee relayer.log"
fi
