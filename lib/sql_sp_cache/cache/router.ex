defmodule SqlSpCache.Cache.Router do
  @moduledoc false

  require Logger

  alias SqlSpCache.Cache.Registry, as: CacheRegistry
  alias SqlSpCache.Server.Request
  alias SqlSpCache.Cache.Supervisor, as: CacheSupervisor
  alias SqlSpCache.Cache.Item, as: CacheItem
  alias SqlSpCache.Cache

  def send_to_cache(%Request{} = request, client)
  do
    cache_name = get_cache_name(request)
    cache_key = get_cache_key(request)
    log_cache_route(request, cache_name, cache_key)
    Cache.set_keep_alive(cache_name)
    {:ok, _cache} = CacheSupervisor.start_child(cache_name)
    cache_item = %CacheItem{request: request, key: cache_key, timestamp: Timex.now()}
    Cache.add_or_update(cache_name, cache_item, client)
  end

  defp get_cache_name(%Request{sp: sp})
  do
    CacheRegistry.get_via!(sp)
  end

  defp get_cache_key(%Request{token: token, sp: sp, params: params})
  do
    Base.encode64((token || "") <> sp <> inspect(params))
  end

  defp log_cache_route(request, cache_name, cache_key)
  do
    Logger.debug("routing request to cache #{inspect(cache_name)} with key #{inspect(cache_key)}: #{inspect(request)}")
  end
end
