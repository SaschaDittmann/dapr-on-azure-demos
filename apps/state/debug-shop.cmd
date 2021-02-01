cd src\WebShopApi
dapr run --app-id shop --app-port 5000 --dapr-http-port 3500 dotnet run 
cd ..\..
