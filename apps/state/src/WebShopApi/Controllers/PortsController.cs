using System;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;

namespace WebShopApi.Controllers
{
    [ApiController]
    [Route("[controller]")]
    public class PortsController : ControllerBase
    {
        private readonly ILogger<PortsController> _logger;
        public PortsController(ILogger<PortsController> logger)
        {
            _logger = logger;
        }

        [HttpGet]
        public async Task<IActionResult> Get()
        {
            var daprHttpPortEnv = Environment.GetEnvironmentVariable("DAPR_HTTP_PORT");
            var daprGrpcPortEnv = Environment.GetEnvironmentVariable("DAPR_GRPC_PORT");
            _logger.LogInformation($"DAPR_HTTP_PORT: {daprHttpPortEnv}");
            _logger.LogInformation($"DAPR_GRPC_PORT: {daprGrpcPortEnv}");
            return Ok();
        }
    }
}
