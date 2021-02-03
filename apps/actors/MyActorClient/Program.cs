using System;
using System.Threading.Tasks;
using Dapr.Actors;
using Dapr.Actors.Client;
using MyActor.Interfaces;

namespace MyActorClient
{
    class Program
    {
        const string MyActorType = "MyActor";

        static async Task Main(string[] args)
        {
            while(true)
            {
                await InvokeActorMethodWithRemotingAsync();
                //await InvokeActorMethodWithoutRemotingAsync();
                await Task.Delay(5000);
            }       
        }

        static async Task InvokeActorMethodWithRemotingAsync()
        {
            var actorID = new ActorId("1");

            // Create the local proxy by using the same interface that the service implements
            // By using this proxy, you can call strongly typed methods on the interface using Remoting.
            var proxy = ActorProxy.Create<IMyActor>(actorID, MyActorType);
            var response = await proxy.SetDataAsync(new MyData()
            {
                PropertyA = "ValueA",
                PropertyB = "ValueB",
            });
            Console.WriteLine(response);

            var savedData = await proxy.GetDataAsync();
            Console.WriteLine(savedData);
        }
        static async Task InvokeActorMethodWithoutRemotingAsync()
        {
            var actorID = new ActorId("2");

            // Create Actor Proxy instance to invoke the methods defined in the interface
            var proxy = ActorProxy.Create(actorID, MyActorType);
            // Need to specify the method name and response type explicitly
            var response = await proxy.InvokeMethodAsync<MyData, string>("SetDataAsync", new MyData()
            {
                PropertyA = "ValueA",
                PropertyB = "ValueB",
            });
            Console.WriteLine(response);

            var savedData = await proxy.InvokeMethodAsync<MyData>("GetDataAsync");
            Console.WriteLine(savedData);
        }
    }
}
