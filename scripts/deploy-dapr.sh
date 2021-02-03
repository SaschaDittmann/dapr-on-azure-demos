#!/bin/bash
if ! command -v COMMAND &> /dev/null
then
    echo "Unable to locate the Dapr CLI. Aborting..."
    exit
fi

dapr init -k --enable-ha=true
