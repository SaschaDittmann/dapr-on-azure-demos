#!/bin/bash
cd MyActorService
dapr run --app-id 'my-actor-service' --app-port 5000 --dapr-http-port 3500 dotnet run 
cd ../..
