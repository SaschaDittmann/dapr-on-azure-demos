using System.Net;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using WebShopApi.Services;

namespace WebShopApi.Controllers
{
    [ApiController]
    [Route("[controller]")]
    public class NewOrderController : ControllerBase
    {
        private readonly ILogger<NewOrderController> _logger;
        private readonly IDaprStateService _stateService;

        public NewOrderController(ILogger<NewOrderController> logger, IDaprStateService stateService)
        {
            _logger = logger;
            _stateService = stateService;
        }

        [HttpPost]
        public async Task<IActionResult> Post(Order order)
        {
            _logger.LogInformation($"Got a new order! Order ID: {order.OrderId}");

            var stateResult = await _stateService.SetAsync("order", order);
            if (stateResult.StatusCode != HttpStatusCode.OK && stateResult.StatusCode != HttpStatusCode.Created)
            {
                _logger.LogError($"Failed to persist state ({stateResult.ReasonPhrase}).\nReason: {stateResult.ErrorMessage}");
                return StatusCode((int)stateResult.StatusCode);
            }
            _logger.LogInformation("Successfully persisted state.");
            return Ok();
        }
    }
}
