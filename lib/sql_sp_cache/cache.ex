defmodule SqlSpCache.Cache do
  @moduledoc false
  @mod __MODULE__
  @private_cache_keys [:_cache_name_, :_stats_, :_keep_alive_, :_ignore_]

  require Logger

  use GenServer

  import SqlSpCache.Utilities

  alias SqlSpCache.PubSub
  alias SqlSpCache.Cache.Cleaner, as: CacheCleaner
  alias SqlSpCache.Cache.Registry, as: CacheRegistry
  alias SqlSpCache.Cache.NameRegistry, as: CacheNameRegistry
  alias SqlSpCache.Cache.Item, as: CacheItem
  alias SqlSpCache.Cache.Listeners, as: CacheListeners
  alias SqlSpCache.DB
  alias SqlSpCache.Push
  alias SqlSpCache.Server.Response, as: ServerResponse

  def start_link(%{name: name})
  do
    GenServer.start_link(@mod, %{_cache_name_: name, _stats_: get_init_stats()}, name: name)
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
    CacheNameRegistry.register()
    PubSub.subscribe(PubSub.Topics.cache_clean_up())
    {:ok, initial_state}
  end

  def handle_call(:info, _from, state)
  do
    info = %{
      name: state[:_cache_name_] |> elem(2) |> elem(1), # extract name from via tuple
      pid: self(),
      stats: Map.delete(state[:_stats_], :db_fetch_timestamp_queue),
      keys: state |> Map.keys() |> Enum.reject(&(Enum.member?(@private_cache_keys, &1))),
    }
    {:reply, info, state}
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

  def handle_info({:db_fetch, {{item, _client} = item_client, result}}, state)
  do
    new_state =
      case state[item.key] do
        nil -> put_stats_db_fetch_end(state, success: false)
        _ -> do_add_item(state, item_client, result)
      end
    {:noreply, new_state}
  end

  def handle_info({:poll, {item, _client} = item_client}, state)
  do
    new_state =
      case state[item.key] do
        nil ->
          Logger.debug("canceling polling for inexistent item with key #{item.key}")
          state
        _ ->
          Logger.debug("polling item with key #{item.key}")
          DB.execute_sp(item_client)
          put_stats_db_fetch_start(state)
      end
    {:noreply, new_state}
  end

  def handle_info(:clean_up, state)
  do
    new_state = clean_up(state)
    private_cache_keys_count = Enum.count(@private_cache_keys, fn key -> Map.has_key?(new_state, key) end)
    if !new_state[:_keep_alive_]
    and (Map.size(new_state) - private_cache_keys_count) <= 0
    and (self() |> :erlang.process_info() |> Keyword.get(:messages) |> length()) === 0 do
      # if _keep_alive_ is not true
      # and the cache is empty
      # and there are no pending messages to be processed
      # then extract name from via tuple
      Logger.debug("shutting down cache #{state[:_cache_name_] |> elem(2) |> elem(1)}")
      {:stop, :shutdown, new_state}
    else
      {:noreply, new_state}
    end
  end

  defp try_add_get_cache_item(state, {item, _client} = item_client)
  do
    db_fetch_update_ignore = fn state ->
      DB.execute_sp(item_client)
      new_state = put_stats_db_fetch_start(state)
      new_cache_item = %{
        item | request: %{item.request | expire: abs(item.request.expire)},
        data: nil
      }
      new_state
      |> Map.put(item.key, new_cache_item)
      |> Map.put(:_ignore_, true)
    end
    case state[item.key] do
      nil ->
        db_fetch_update_ignore.(state)
      cache_item ->
        if item.request.expire <= 0
        or (
          cache_item.request.poll <= 0
          and cache_item.timestamp
          |> Timex.shift(milliseconds: cache_item.request.expire)
          |> Timex.before?(Timex.now())
        ) do
          # if a negative expiration time was requested
          # or the already cached item is not being polled and has expired
          CacheListeners.remove_cache_key(item.key)
          state
          |> Map.delete(item.key)
          |> db_fetch_update_ignore.()
        else
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
          new_state = put_stats_db_fetch_end(state, success: true)
          if data != nil && old_cache_item.data != data do
            new_cache_item = %{old_cache_item | data: data, last_updated: Timex.now()}
            push(new_cache_item, client)
            new_state = Map.put(new_state, old_cache_item.key, new_cache_item)
            old_data_byte_size = gen_byte_size(old_cache_item.data || "")
            new_data_byte_size = gen_byte_size(data)
            old_stats = new_state[:_stats_]
            %{new_state | _stats_:
              %{old_stats | byte_size: old_stats.byte_size - old_data_byte_size + new_data_byte_size}
            }
          else
            new_state
          end
        {:error, error} ->
          new_state = put_stats_db_fetch_end(state, success: false)
          # stop polling for this item if the db fetch operation resulted in an error
          new_cache_item = %{
            old_cache_item | request: %{old_cache_item.request | poll: 0},
            poll_scheduled: false,
            last_updated: Timex.now()
          }
          push(new_cache_item, client, error)
          Map.put(new_state, old_cache_item.key, new_cache_item)
      end
    new_cache_item = new_state[old_cache_item.key]
    case old_cache_item.data do
      # this is the first time this item enters the cache or a previous fetch has failed to fetch data from the db
      nil ->
        if old_cache_item.request.expire <= 0 do
          # this item will enter the cache as expired and it will be removed either by the next request
          # or by the cache cleaner
          new_state
        else
          # this item will expire in the future so we must schedule it for polling if applicable
          schedule_item_polling(new_state, item_client)
        end
      # we reach this point after polling
      _ ->
        new_state = Map.put(new_state, old_cache_item.key, %{new_cache_item | poll_scheduled: false})
        # is polling still in effect for this key?
        if old_cache_item.request.poll <= 0 do
          new_state
        else
          schedule_item_polling(new_state, item_client)
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
    # if polling has been or is about to be scheduled
    if cache_item.poll_scheduled or item.request.poll > 0 do
      {existing_client?, _} = CacheListeners.add_once(client, cache_item.key)
      # if the data is already available and the client has not been already added just send the data to the client
      if cache_item.data != nil && !existing_client? do
        push_single_client(cache_item, client)
      end
    else
      # else schedule a one time immediate poll
      case cache_item.data do
        nil ->
          CacheListeners.add_once(client, cache_item.key)
          cache_pid = CacheRegistry.get_pid!(state[:_cache_name_])
          Logger.debug("scheduling one time instant poll for item #{cache_item.key} and client #{inspect(client)}"
            <> " in cache #{inspect(cache_pid)}")
          Process.send(cache_pid, {:poll, {item, client}}, [])
        _ ->
          push_single_client(cache_item, client)
      end
    end
    # adjust expiration time and polling interval
    %{state | cache_item.key => %{
      cache_item | request: %{
        cache_item.request | expire: item.request.expire, poll: item.request.poll
      }
    }}
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
      if cache_item.request.poll > 0 do
        CacheListeners.add(client, cache_item.key)
        case CacheListeners.get_clients(cache_item.key) do
          [] ->
            Logger.debug("setting poll to 0 for item #{cache_item.key} because no listeners are listening")
            Map.put(state, cache_item.key, %{cache_item | request: %{cache_item.request | poll: 0}})
          _ ->
            if cache_item.poll_scheduled do
              Logger.debug("poll has already been scheduled for item #{cache_item.key}")
              state
            else
              cache_pid = CacheRegistry.get_pid!(state[:_cache_name_])
              Logger.debug("scheduling poll at #{cache_item.request.poll}ms for item #{cache_item.key}"
                <> " in cache #{inspect(cache_pid)}")
              Process.send_after(cache_pid, {:poll, {item, nil}}, cache_item.request.poll)
              Map.put(state, cache_item.key, %{cache_item | poll_scheduled: true})
            end
        end
      else
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

  defp clean_up(state)
  do
    now = Timex.now()
    init_stats = Map.merge(state[:_stats_], %{byte_size: 0})
    Enum.reduce(state, %{_stats_: init_stats}, fn {cache_key, cache_item}, new_state ->
      is_private_cache_key = Enum.member?(@private_cache_keys, cache_key)
      expire =
        cond do
          is_private_cache_key -> 0
          cache_item.request.expire != 0 -> cache_item.request.expire
          # allow at least an expiration time of :clean_up_interval before removing a key from the cache
          cache_item.request.expire == 0 -> Application.get_env(:sql_sp_cache, CacheCleaner)[:clean_up_interval]
        end
      keep? =
        is_private_cache_key
        or cache_item.poll_scheduled
        or cache_item.request.poll > 0
        or cache_item.timestamp
        |> Timex.shift(milliseconds: expire)
        |> Timex.after?(now)
      if keep? && cache_key != :_stats_ do
        new_state = Map.put(new_state, cache_key, cache_item)
        if is_private_cache_key do
          new_state
        else
          new_data_byte_size = gen_byte_size(cache_item.data || "")
          old_stats = new_state[:_stats_]
          %{new_state | _stats_:
            %{old_stats | byte_size: old_stats.byte_size + new_data_byte_size}
          }
        end
      else
        new_state
      end
    end)
  end

  defp get_init_stats()
  do
    %{byte_size: 0, db_fetch_count: 0, db_fetch_duration: 0, db_fetch_mean_duration: 0, db_fetch_timestamp_queue: []}
  end

  defp put_stats_db_fetch_start(state)
  do
    old_stats = state[:_stats_]
    %{state | _stats_: %{old_stats | db_fetch_timestamp_queue: [Timex.now | old_stats[:db_fetch_timestamp_queue]]}}
  end

  defp put_stats_db_fetch_end(state, success: success)
  do
    old_stats = state[:_stats_]
    [timestamp | rest_db_fetch_timestamp_queue] = Enum.reverse(old_stats[:db_fetch_timestamp_queue])
    new_db_fetch_timestamp_queue = Enum.reverse(rest_db_fetch_timestamp_queue)
    if success do
      now = Timex.now()
      new_db_fetch_count = old_stats[:db_fetch_count] + 1
      new_db_fetch_duration = old_stats[:db_fetch_duration] + Timex.diff(now, timestamp, :milliseconds)
      new_db_fetch_mean_duration = new_db_fetch_duration / new_db_fetch_count
      %{state | _stats_: %{old_stats |
        db_fetch_count: new_db_fetch_count,
        db_fetch_duration: new_db_fetch_duration,
        db_fetch_mean_duration: new_db_fetch_mean_duration,
        db_fetch_timestamp_queue: new_db_fetch_timestamp_queue,
      }}
    else
      %{state | stats: %{old_stats | db_fetch_timestamp_queue: new_db_fetch_timestamp_queue}}
    end
  end
end
