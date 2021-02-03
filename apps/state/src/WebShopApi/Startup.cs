using System;
using System.Diagnostics;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.OpenApi.Models;
using WebShopApi.Services;

namespace WebShopApi
{
    public class Startup
    {
        public Startup(IConfiguration configuration)
        {
            Configuration = configuration;
        }

        public IConfiguration Configuration { get; }

        // This method gets called by the runtime. Use this method to add services to the container.
        public void ConfigureServices(IServiceCollection services)
        {
            var daprHttpPortEnv = Environment.GetEnvironmentVariable("DAPR_HTTP_PORT");
            var daprGrpcPortEnv = Environment.GetEnvironmentVariable("DAPR_GRPC_PORT");
            Debug.WriteLine($"DAPR_HTTP_PORT: {daprHttpPortEnv}");
            Debug.WriteLine($"DAPR_GRPC_PORT: {daprGrpcPortEnv}");
            
            var daprStateService = new DaprStateService(
                string.IsNullOrEmpty(daprHttpPortEnv) ? 3500 : Convert.ToInt32(daprHttpPortEnv),
                "statestore");
            services.AddSingleton<IDaprStateService>(daprStateService);
            
            services.AddControllers();
            services.AddSwaggerGen(c =>
            {
                c.SwaggerDoc("v1", new OpenApiInfo { Title = "WebShopApi", Version = "v1" });
            });
            
        }

        // This method gets called by the runtime. Use this method to configure the HTTP request pipeline.
        public void Configure(IApplicationBuilder app, IWebHostEnvironment env)
        {
            if (env.IsDevelopment())
            {
                app.UseDeveloperExceptionPage();
                app.UseSwagger();
                app.UseSwaggerUI(c => c.SwaggerEndpoint("/swagger/v1/swagger.json", "WebShopApi v1"));
            }

            app.UseHttpsRedirection();

            app.UseRouting();

            app.UseAuthorization();

            app.UseEndpoints(endpoints =>
            {
                endpoints.MapControllers();
            });
        }
    }
}
