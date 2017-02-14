defmodule SqlSpCache.Cache.Listeners.Test do
  use ExUnit.Case, async: true

  alias SqlSpCache.Cache.Listeners, as: CacheListeners

  test "adding to cache listeners works"
  do
    {:ok, client1} = :gen_tcp.connect('127.0.0.1', 4416, [])
    CacheListeners.add(client1, "cache_key1")
    %{client_cache_key: client_cache_key, cache_key_client: cache_key_client, cache_key_client_once: %{}} =
      CacheListeners.get_state()
    assert client_cache_key === %{client1 => MapSet.new() |> MapSet.put("cache_key1")}
    assert cache_key_client === %{"cache_key1" => MapSet.new() |> MapSet.put(client1)}
    CacheListeners.remove_client(client1)
    :gen_tcp.close(client1)
  end

  test "removing clients from cache listeners works"
  do
    {:ok, client1} = :gen_tcp.connect('127.0.0.1', 4416, [])
    {:ok, client2} = :gen_tcp.connect('127.0.0.1', 4416, [])
    CacheListeners.add(client1, "cache_key1")
    CacheListeners.add(client1, "cache_key2")
    CacheListeners.add(client2, "cache_key1")
    CacheListeners.add(client2, "cache_key2")
    CacheListeners.remove_client(client1)
    %{client_cache_key: client_cache_key} = CacheListeners.get_state()
    assert client_cache_key === %{client2 => MapSet.new() |> MapSet.put("cache_key1") |> MapSet.put("cache_key2")}
    CacheListeners.remove_client(client2)
    :gen_tcp.close(client1)
    :gen_tcp.close(client2)
  end

  test "removing cache keys from cache listeners works"
  do
    {:ok, client1} = :gen_tcp.connect('127.0.0.1', 4416, [])
    {:ok, client2} = :gen_tcp.connect('127.0.0.1', 4416, [])
    CacheListeners.add(client1, "cache_key1")
    CacheListeners.add(client1, "cache_key2")
    CacheListeners.add(client2, "cache_key1")
    CacheListeners.add(client2, "cache_key2")
    CacheListeners.remove_cache_key("cache_key1")
    %{cache_key_client: cache_key_client} = CacheListeners.get_state()
    assert cache_key_client === %{"cache_key2" => MapSet.new() |> MapSet.put(client1) |> MapSet.put(client2)}
    CacheListeners.remove_cache_key("cache_key2")
    :gen_tcp.close(client1)
    :gen_tcp.close(client2)
  end

  test "removing clients and cache keys from cache listeners works"
  do
    {:ok, client1} = :gen_tcp.connect('127.0.0.1', 4416, [])
    {:ok, client2} = :gen_tcp.connect('127.0.0.1', 4416, [])
    CacheListeners.add(client1, "cache_key1")
    CacheListeners.add(client1, "cache_key2")
    CacheListeners.add(client2, "cache_key1")
    CacheListeners.add(client2, "cache_key2")
    CacheListeners.remove_client(client1)
    %{client_cache_key: client_cache_key} = CacheListeners.get_state()
    assert client_cache_key === %{client2 => MapSet.new() |> MapSet.put("cache_key1") |> MapSet.put("cache_key2")}
    CacheListeners.remove_cache_key("cache_key1")
    %{cache_key_client: cache_key_client} = CacheListeners.get_state()
    assert cache_key_client === %{"cache_key2" => MapSet.new() |> MapSet.put(client2)}
    CacheListeners.remove_cache_key(client2)
    :gen_tcp.close(client1)
    :gen_tcp.close(client2)
  end

  test "adding multiple clients to one time cache listeners works"
  do
    {:ok, client1} = :gen_tcp.connect('127.0.0.1', 4416, [])
    {:ok, client2} = :gen_tcp.connect('127.0.0.1', 4416, [])
    CacheListeners.add_once(client1, "cache_key1")
    CacheListeners.add_once(client2, "cache_key1")
    %{client_cache_key: %{}, cache_key_client: %{}, cache_key_client_once: cache_key_client_once} =
      CacheListeners.get_state()
    assert cache_key_client_once === %{"cache_key1" => MapSet.new() |> MapSet.put(client1) |> MapSet.put(client2)}
    :gen_tcp.close(client1)
    :gen_tcp.close(client2)
  end

  test "adding to and removing from one time cache listeners work"
  do
    {:ok, client1} = :gen_tcp.connect('127.0.0.1', 4416, [])
    {:ok, client2} = :gen_tcp.connect('127.0.0.1', 4416, [])
    CacheListeners.add_once(client1, "cache_key1")
    CacheListeners.add(client1, "cache_key1")
    CacheListeners.add_once(client2, "cache_key1")
    %{client_cache_key: client_cache_key, cache_key_client: cache_key_client, cache_key_client_once: cache_key_client_once} =
      CacheListeners.get_state()
    assert client_cache_key === %{client1 => MapSet.new() |> MapSet.put("cache_key1")}
    assert cache_key_client === %{"cache_key1" => MapSet.new() |> MapSet.put(client1)}
    assert cache_key_client_once === %{"cache_key1" => MapSet.new() |> MapSet.put(client2)}
    CacheListeners.remove_client(client1)
    assert CacheListeners.get_remove_once("cache_key1") === [client2]
    %{cache_key_client_once: cache_key_client_once} = CacheListeners.get_state()
    assert cache_key_client_once === %{}
    :gen_tcp.close(client1)
    :gen_tcp.close(client2)
  end

end
