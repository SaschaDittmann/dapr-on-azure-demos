using Newtonsoft.Json;

namespace WebShopApi
{
    public class Order
    {
        [JsonProperty("orderId")]
        public int OrderId { get; set; }
    }
}
