using System.Net;

namespace WebShopApi.Services
{
    public class DaprStateResult<T>
    {
        public HttpStatusCode StatusCode { get; set; }
        public T Value { get; set; }
    }
}