defmodule SqlSpCache.Command do
  @moduledoc false

  require Logger

  import SqlSpCache.Utilities, only: [get_data_header: 1]

  alias SqlSpCache.Cache.NameRegistry, as: CacheNameRegistry
  alias SqlSpCache.Cache.Listeners, as: CacheListeners
  alias SqlSpCache.Push

  def execute(command, params \\ nil)
  do
    command = command |> String.trim() |> String.downcase()
    case Map.has_key?(commands(), command) do
      true ->
        Logger.debug("received command #{command}")
        commands()[command].(params)
      false ->
        Logger.error("received invalid command #{command}")
        nil
    end
  end

  defp commands()
  do
    %{
      "heartbeat" => &heartbeat/1,
      "stats" => &stats/1,
    }
  end

  defp heartbeat(_params)
  do
    {:ok, version} = :application.get_key(:sql_sp_cache, :vsn)
    version = to_string(version)
    {:ok, response} =
      Poison.encode(%{
        health: "ok",
        version: version,
      })
    get_data_header(response) <> response
  end

  defp stats(_params)
  do
    caches =
      CacheNameRegistry.lookup()
      |> Enum.map(fn {cache_pid, _} ->
        info = GenServer.call(cache_pid, :info)
        pid = info.pid |> inspect() |> String.trim_leading("#PID<") |> String.trim_trailing(">")
        value =
          info
          |> Map.take([:stats, :keys])
          |> Map.put(:pid, pid)
        clients_per_key = Enum.reduce(value[:keys], %{}, fn cache_key, acc ->
          Map.put(acc, cache_key, length(CacheListeners.get_all_clients(cache_key)))
        end)
        value = Map.put(value, :keys, clients_per_key)
        {info.name,  value}
      end)
      |> Map.new()
    {:ok, response} =
      Poison.encode(%{
        caches: caches,
        push_queue_length: Push.get_push_queue_length(),
      })
    get_data_header(response) <> response
  end
end
