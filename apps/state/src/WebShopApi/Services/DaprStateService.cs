using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Net.Http.Json;
using System.Threading.Tasks;
using Newtonsoft.Json;

namespace WebShopApi.Services
{
    public class DaprStateService : IDaprStateService
    {
        private readonly int _daprHttpPort;
        private string _stateStoreName;
        private readonly string _stateStoreUri;
        private static readonly HttpClient _httpClient = new HttpClient();
        
        public DaprStateService(int daprHttpPort, string stateStoreName)
        {
            _daprHttpPort = daprHttpPort;
            _stateStoreName = stateStoreName;
            _stateStoreUri = $"http://localhost:{_daprHttpPort}/v1.0/state/{_stateStoreName}";
        }
        
        public async Task<DaprStateResult<T>> GetAsync<T>(string key)
        {
            var response = await _httpClient.GetAsync($"{_stateStoreUri}/{key}");
            if (response.StatusCode != HttpStatusCode.OK)
                return new DaprStateResult<T> {StatusCode = response.StatusCode};
            var content = await response.Content.ReadAsStringAsync();
            return new DaprStateResult<T>
            {
                StatusCode = response.StatusCode,
                Value = JsonConvert.DeserializeObject<T>(content)
            };
        }

        public async Task<HttpStatusCode> SetAsync(string key, object value)
        {
            return await SetAsync(new List<KeyValuePair<string, object>>
            {
                new KeyValuePair<string, object>(key, value)
            });
        }

        public async Task<HttpStatusCode> SetAsync(IEnumerable<KeyValuePair<string, object>> states)
        {
            var response = await _httpClient.PostAsync(
                _stateStoreUri, 
                JsonContent.Create(states)
                );
            return response.StatusCode;
        }
    }
}