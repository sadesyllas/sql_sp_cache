defmodule SqlSpCache.Cache do
  @moduledoc false
  @mod __MODULE__
  @private_cache_keys [:_cache_name_, :_keep_alive_, :_ignore_]

  require Logger
  use GenServer

  alias SqlSpCache.PubSub
  alias SqlSpCache.Cache.Registry, as: CacheRegistry
  alias SqlSpCache.Cache.Item, as: CacheItem
  alias SqlSpCache.Cache.Listeners, as: CacheListeners
  alias SqlSpCache.DB
  alias SqlSpCache.Push
  alias SqlSpCache.Server.Response, as: ServerResponse

  def start_link(%{name: name})
  do
    GenServer.start_link(@mod, %{_cache_name_: name}, name: name)
  end

  def set_keep_alive(cache_name)
  do
    GenServer.cast(cache_name, :_keep_alive_)
  end

  def add_or_update(cache_name, %CacheItem{} = item, client)
  do
    GenServer.cast(cache_name, {:add_or_update, {item, client}})
  end

  def init(initial_state)
  do
    PubSub.subscribe(PubSub.Topics.cache_clean())
    {:ok, initial_state}
  end

  def handle_cast(:_keep_alive_, state)
  do
    {:noreply, Map.put(state, :_keep_alive_, true)}
  end

  def handle_cast({:add_or_update, item_client}, state)
  do
    new_state =
      state
      |> try_add_get_cache_item(item_client)
      |> try_update_get_cache_item(item_client)
      |> Map.delete(:_keep_alive_)
      |> Map.delete(:_ignore_)
    {:noreply, new_state}
  end

  def handle_info({:db_fetch, {item_client, result}}, state)
  do
    {:noreply, do_add_item(state, item_client, result)}
  end

  def handle_info({:poll, {item, _client} = item_client}, state)
  do
    Logger.debug("polling item with key #{item.key}")
    DB.execute_sp(item_client)
    {:noreply, state}
  end

  def handle_info(:clean, state)
  do
    new_state = clean(state)
    private_cache_keys_count = Enum.count(new_state, fn {key, _value} -> Enum.member?(@private_cache_keys, key) end)
    cond do
      # _keep_alive_ is not true
      !new_state[:_keep_alive_]
      # and the cache is empty
      and (Map.size(new_state) - private_cache_keys_count) <= 0
      # and there are no pending messages to be processed
      and (:erlang.process_info(self()) |> Keyword.get(:messages) |> length()) === 0 ->
        Logger.debug("shutting down cache #{inspect(state[:_cache_name_])}")
        {:stop, :shutdown, new_state}
      true ->
        {:noreply, new_state}
    end
  end

  defp try_add_get_cache_item(state, {item, _client} = item_client)
  do
    db_fetch_update_ignore = fn state ->
      DB.execute_sp(item_client)
      new_cache_item = %{
        item | request: %{item.request | expire: abs(item.request.expire)},
        data: nil
      }
      state
      |> Map.put(item.key, new_cache_item)
      |> Map.put(:_ignore_, true)
    end
    case state[item.key] do
      nil ->
        db_fetch_update_ignore.(state)
      cache_item ->
        cond do
          # if a negative expiration time was requested
          item.request.expire <= 0
          # or the already cached item is not being polled and has expired
          or (
            cache_item.request.poll <= 0
            and cache_item.timestamp
            |> Timex.shift(milliseconds: cache_item.request.expire)
            |> Timex.before?(Timex.now())
          ) ->
            CacheListeners.remove_cache_key(item.key)
            state
            |> Map.delete(item.key)
            |> db_fetch_update_ignore.()
          true ->
            # update cache item
            state
        end
    end
  end

  defp do_add_item(state, {item, client} = item_client, db_fetch_result)
  do
    old_cache_item = state[item.key]
    new_state =
      case db_fetch_result do
        {:ok, data} ->
          cond do
            old_cache_item.data != data ->
              new_cache_item = %{old_cache_item | data: data, last_updated: Timex.now()}
              push(new_cache_item, client)
              Map.put(state, old_cache_item.key, new_cache_item)
            true ->
              state
          end
        {:error, error} ->
          # stop polling for this item if the db fetch operation resulted in an error
          new_cache_item = %{
            old_cache_item | request: %{old_cache_item.request | poll: 0},
            poll_scheduled: false,
            last_updated: Timex.now()
          }
          push(new_cache_item, client, error)
          Map.put(state, old_cache_item.key, new_cache_item)
      end
    new_cache_item = new_state[old_cache_item.key]
    case old_cache_item.data do
      # this is the first time this item enters the cache or a previous fetch has failed to fetch data from the db
      nil ->
        case old_cache_item.request.expire <= 0 do
          # this item will enter the cache as expired and it will be removed either by the next request
          # or by the cache cleaner
          true -> new_state
          # this item will expire in the future so we must schedule it for polling if applicable
          false -> schedule_item_polling(new_state, item_client)
        end
      # we reach this point after polling
      _ ->
        new_state = Map.put(new_state, old_cache_item.key, %{new_cache_item | poll_scheduled: false})
        # is polling still in effect for this key?
        case old_cache_item.request.poll <= 0 do
          true -> new_state
          false -> schedule_item_polling(new_state, item_client)
        end
    end
  end

  defp try_update_get_cache_item(%{_ignore_: true} = state, _)
  do
    state
  end

  defp try_update_get_cache_item(state, {item, client} = item_client)
  do
    cache_item = state[item.key]
    case cache_item.data do
      nil ->
        CacheListeners.add_once(client, cache_item.key)
        # if polling has been or is about to be scheduled
        case cache_item.poll_scheduled or item.request.poll > 0 do
          # then do nothing
          true ->
            nil
          # else schedule a one time instant poll
          false ->
            cache_pid = CacheRegistry.get_pid!(state[:_cache_name_])
            Logger.debug("scheduling one time instant poll for item #{cache_item.key} and client #{inspect(client)}"
              <> " in cache #{inspect(cache_pid)}")
            Process.send(cache_pid, {:poll, {item, client}}, [])
        end
      _ ->
        push_single_client(cache_item, client)
    end
    # adjust polling interval
    %{state | cache_item.key => %{cache_item | request: %{cache_item.request | poll: item.request.poll}}}
    |> schedule_item_polling(item_client)
  end

  defp schedule_item_polling(%{_ignore_: true} = state, _)
  do
    state
  end

  defp schedule_item_polling(state, {item, client})
  do
    cache_item = state[item.key]
    new_state =
      case cache_item.request.poll > 0 do
        true ->
          CacheListeners.add(client, cache_item.key)
          case CacheListeners.get_clients(cache_item.key) do
            [] ->
              Logger.debug("setting poll to 0 for item #{cache_item.key} because no listeners are listening")
              Map.put(state, cache_item.key, %{cache_item | request: %{cache_item.request | poll: 0}})
            _ ->
              case cache_item.poll_scheduled do
                true ->
                  Logger.debug("poll has already been scheduled for item #{cache_item.key}")
                  state
                false ->
                  cache_pid = CacheRegistry.get_pid!(state[:_cache_name_])
                  Logger.debug("scheduling poll at #{cache_item.request.poll}ms for item #{cache_item.key}"
                    <> " in cache #{inspect(cache_pid)}")
                  Process.send_after(cache_pid, {:poll, {item, nil}}, cache_item.request.poll)
                  Map.put(state, cache_item.key, %{cache_item | poll_scheduled: true})
              end
          end
        false ->
          state
      end
    new_state
  end

  defp push(cache_item, client, error \\ nil)

  defp push(%CacheItem{} = cache_item, client, error)
  do
    Push.push(cache_item.key, client, %ServerResponse{
        token: cache_item.request.token,
        data: cache_item.data,
        last_updated: cache_item.last_updated,
        error: error
      })
  end

  defp push_single_client(cache_item, client, error \\ nil)

  defp push_single_client(%CacheItem{} = cache_item, client, error)
  do
    Push.push_single_client(client, %ServerResponse{
        token: cache_item.request.token,
        data: cache_item.data,
        last_updated: cache_item.last_updated,
        error: error
      })
  end

  defp clean(state)
  do
    now = Timex.now()
    state
    |> Enum.filter(fn {cache_key, cache_item} ->
      cache_key === :_cache_name_
      or cache_item.request.poll > 0
      or cache_item.timestamp
      |> Timex.shift(milliseconds: cache_item.request.expire)
      |> Timex.after?(now)
    end)
    |> Map.new()
  end
end
