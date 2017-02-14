defmodule SqlSpCache.Cache.Listeners do
  @moduledoc false
  @mod __MODULE__

  require Logger
  use GenServer

  def start_link()
  do
    GenServer.start_link(@mod, %{client_cache_key: %{}, cache_key_client: %{}, cache_key_client_once: %{}}, name: @mod)
  end

  def add(nil, _)
  do
    :ok
  end

  def add(client, cache_key)
  do
    Logger.debug("adding client #{inspect(client)} to listeners")
    GenServer.call(@mod, {:add, {client, cache_key}})
  end

  def add_once(client, cache_key)
  do
    GenServer.call(@mod, {:add_once, {client, cache_key}})
  end

  def remove_client(client)
  do
    GenServer.call(@mod, {:remove_client, client})
  end

  def remove_cache_key(cache_key)
  do
    GenServer.call(@mod, {:remove_cache_key, cache_key})
  end

  def get_clients(cache_key)
  do
    GenServer.call(@mod, {:get_clients, cache_key})
  end

  def get_remove_once(cache_key)
  do
    GenServer.call(@mod, {:get_remove_once, cache_key})
  end

  # used only for testing
  def get_state()
  do
    GenServer.call(@mod, :get_state)
  end

  def handle_call({:get_clients, cache_key}, _from, state)
  do
    clients = MapSet.to_list(state.cache_key_client[cache_key] || MapSet.new())
    {:reply, clients, state}
  end

  def handle_call({:get_remove_once, cache_key}, _from, state)
  do
    clients = MapSet.to_list(state.cache_key_client_once[cache_key] || MapSet.new())
    cache_key_client_once_new = Map.delete(state.cache_key_client_once, cache_key)
    new_state = %{state | cache_key_client_once: cache_key_client_once_new}
    {:reply, clients, new_state}
  end

  # used only for testing
  def handle_call(:get_state, _from, state)
  do
    {:reply, state, state}
  end

  def handle_call({:add, {client, cache_key}}, _from,
    %{client_cache_key: client_cache_key, cache_key_client: cache_key_client,
      cache_key_client_once: cache_key_client_once} = state)
  do
    cache_key_clients_once = cache_key_client_once[cache_key]
    new_state =
      case cache_key_clients_once do
        nil ->
          state
        _ ->
          cache_key_clients_once_new = MapSet.delete(cache_key_clients_once, client)
          cache_key_client_once_new =
            case MapSet.size(cache_key_clients_once_new) do
              0 -> Map.delete(cache_key_client_once, cache_key)
              _ -> Map.put(cache_key_client_once, cache_key, cache_key_clients_once_new)
            end
          %{state | cache_key_client_once: cache_key_client_once_new}
      end
    new_state =
      case state.client_cache_key[client] do
        nil ->
          client_cache_key_new = Map.put(client_cache_key, client, MapSet.put(MapSet.new(), cache_key))
          cache_key_client_new = Map.put(cache_key_client, cache_key,
            MapSet.put(cache_key_client[cache_key] || MapSet.new(), client))
          new_state
          |> Map.put(:client_cache_key, client_cache_key_new)
          |> Map.put(:cache_key_client, cache_key_client_new)
        _ ->
          client_cache_key_new = Map.put(client_cache_key, client, MapSet.put(client_cache_key[client], cache_key))
          cache_key_client_new = Map.put(cache_key_client, cache_key,
            MapSet.put(cache_key_client[cache_key] || MapSet.new(), client))
          new_state
          |> Map.put(:client_cache_key, client_cache_key_new)
          |> Map.put(:cache_key_client, cache_key_client_new)
      end
    {:reply, new_state, new_state}
  end

  def handle_call({:add_once, {client, cache_key}}, _from, %{cache_key_client_once: cache_key_client_once} = state)
  do
    cache_key_clients_once = cache_key_client_once[cache_key]
    cache_key_client_once_new =
      case cache_key_clients_once do
        nil -> Map.put(cache_key_client_once, cache_key, MapSet.put(MapSet.new(), client))
        _ -> Map.put(cache_key_client_once, cache_key, MapSet.put(cache_key_clients_once, client))
      end
    new_state = %{state | cache_key_client_once: cache_key_client_once_new}
    {:reply, new_state, new_state}
  end

  def handle_call({:remove_client, client}, _from,
    %{client_cache_key: client_cache_key, cache_key_client: cache_key_client} = state)
  do
    client_cache_key_new = Map.delete(client_cache_key, client)
    cache_key_client_new = Enum.reduce(cache_key_client, %{}, fn {cache_key, client_set}, acc ->
      new_client_set = MapSet.delete(client_set, client)
      case MapSet.size(new_client_set) do
        0 -> Map.delete(acc, cache_key)
        _ -> Map.put(acc, cache_key, new_client_set)
      end
    end)
    new_state =
      state
      |> Map.put(:client_cache_key, client_cache_key_new)
      |> Map.put(:cache_key_client, cache_key_client_new)
    {:reply, new_state, new_state}
  end

  def handle_call({:remove_cache_key, cache_key}, _from,
    %{client_cache_key: client_cache_key, cache_key_client: cache_key_client} = state)
  do
    client_cache_key_new = Enum.reduce(client_cache_key, %{}, fn {client, cache_key_set}, acc ->
      new_cache_key_set = MapSet.delete(cache_key_set, cache_key)
      case MapSet.size(new_cache_key_set) do
        0 -> Map.delete(acc, client)
        _ -> Map.put(acc, client, new_cache_key_set)
      end
    end)
     cache_key_client_new = Map.delete(cache_key_client, cache_key)
    new_state =
      state
      |> Map.put(:client_cache_key, client_cache_key_new)
      |> Map.put(:cache_key_client, cache_key_client_new)
    {:reply, new_state, new_state}
  end
end
