using System.Collections.Generic;
using System.Net;
using System.Threading.Tasks;

namespace WebShopApi.Services
{
    public interface IDaprStateService
    {
        Task<DaprStateGetResult<T>> GetAsync<T>(string key);
        Task<DaprStateSetResult> SetAsync(string key, object value);
        Task<DaprStateSetResult> SetAsync(IEnumerable<KeyValuePair<string, object>> states);
    }
}