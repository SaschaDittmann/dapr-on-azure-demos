using System.Net;

namespace WebShopApi.Services
{
    public class DaprStateSetResult
    {
        public HttpStatusCode StatusCode { get; set; }
        public string ReasonPhrase { get; set; }
        public string ErrorMessage { get; set;}
    }
}