using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using WebShopApi.Services;

namespace WebShopApi.Controllers
{
    [ApiController]
    [Route("[controller]")]
    public class OrderController : ControllerBase
    {
        private readonly ILogger<OrderController> _logger;
        private readonly IDaprStateService _stateService;

        public OrderController(ILogger<OrderController> logger, IDaprStateService stateService)
        {
            _logger = logger;
            _stateService = stateService;
        }

        [HttpGet]
        public async Task<IEnumerable<Order>> Get()
        {
            var stateResult = await _stateService.GetAsync<Order>("order");
            if (stateResult.StatusCode != HttpStatusCode.OK)
            {
                _logger.LogError("Could not get state.");
                return Enumerable.Empty<Order>();
            }
            return new[] {stateResult.Value};
        }
    }
}
