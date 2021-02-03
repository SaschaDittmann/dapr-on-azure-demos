using System.Net;

namespace WebShopApi.Services
{
    public class DaprStateGetResult<T>
    {
        public T Value { get; set; }
        public HttpStatusCode StatusCode { get; set; }
        public string ReasonPhrase { get; set; }
        public string ErrorMessage { get; set; }
    }
}