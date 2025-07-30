#!/bin/bash
# Set up a relayer

echo "> Running relayer in a tmux session"
if [ $RELAYER == "hermes" ]; then
    tmux new-session -d -s relayer "$HOME/.hermes/hermes start | tee relayer.log"
elif [ $RELAYER == "rly" ]; then
    tmux new-session -d -s relayer "$HOME/.relayer/rly start | tee relayer.log"
fi

sleep 10
cat relayer.log
