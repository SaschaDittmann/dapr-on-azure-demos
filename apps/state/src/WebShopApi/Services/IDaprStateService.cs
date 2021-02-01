using System.Collections.Generic;
using System.Net;
using System.Threading.Tasks;

namespace WebShopApi.Services
{
    public interface IDaprStateService
    {
        Task<DaprStateResult<T>> GetAsync<T>(string key);
        Task<HttpStatusCode> SetAsync(string key, object value);
        Task<HttpStatusCode> SetAsync(IEnumerable<KeyValuePair<string, object>> states);
    }
}