defmodule SqlSpCache.Cache.Router do
  @moduledoc false

  alias SqlSpCache.Registry.Cache, as: CacheRegistry
  alias SqlSpCache.Server.Request

  def send_to_cache(%Request{} = request, client) do
    cache_name = get_cache_name(request)
    IO.puts("will send msg to #{inspect(cache_name)} from #{inspect(client)}")
  end

  defp get_cache_name(%Request{} = request) do
    {:via, Registry, {CacheRegistry, request.sp}}
  end

  defp get_cache_key(%Request{} = request) do
    "" # TODO: extract key from request
  end
end
