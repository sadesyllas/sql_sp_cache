defmodule SqlSpCache.Cache.Router do
  @moduledoc false

  alias SqlSpCache.Registry.Cache, as: CacheRegistry
  alias SqlSpCache.Server.Request
  alias SqlSpCache.Cache.Supervisor, as: CacheSupervisor
  alias SqlSpCache.Cache.Item, as: CacheItem
  alias SqlSpCache.Cache

  def send_to_cache(%Request{} = request, client) do
    cache_name = get_cache_name(request)
    cache_key = get_cache_key(request)
    {:ok, _cache} = CacheSupervisor.start_child(cache_name)
    cache_item = %CacheItem{request: request, key: cache_key, timestamp: 0}
    Cache.add_or_update(cache_name, cache_item)
  end

  defp get_cache_name(%Request{sp: sp}) do
    {:via, Registry, {CacheRegistry, sp}}
  end

  defp get_cache_key(%Request{sp: sp, params: params}) do
    Base.encode64(sp <> ":" <> inspect(params))
  end
end
