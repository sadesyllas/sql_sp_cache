defmodule SqlSpCache.Push do
  @moduledoc false
  @mod __MODULE__

  require Logger

  use GenServer

  import SqlSpCache.Utilities

  alias SqlSpCache.Server.Response, as: ServerResponse
  alias SqlSpCache.Cache.Listeners, as: CacheListeners

  def start_link()
  do
    GenServer.start_link(@mod, :ok, name: @mod)
  end

  def push(cache_key, client, %ServerResponse{} = server_response)
  do
    Logger.debug("pushing key #{inspect(cache_key)} to clients (current client: #{inspect(client)})"
      <> " with data #{server_response |> inspect() |> String.slice(0, 2048)}")
    GenServer.cast(@mod, {:push, {cache_key, client, server_response}})
  end

  def push_single_client(client, %ServerResponse{} = server_response)
  do
    Logger.debug("pushing to single client #{inspect(client)}"
      <> " with data #{server_response |> inspect() |> String.slice(0, 2048)}")
    GenServer.cast(@mod, {:push_single_client, {client, server_response}})
  end

  def get_push_queue_length()
  do
    GenServer.call(@mod, :get_push_queue_length)
  end

  def handle_call(:get_push_queue_length, _from, state)
  do
    push_queue_length = self() |> :erlang.process_info() |> Keyword.get(:messages) |> length()
    {:reply, push_queue_length, state}
  end

  def handle_cast({:push, {cache_key, client, server_response}}, state)
  do
    clients =
      CacheListeners.get_remove_once(cache_key)
      ++ (cache_key |> CacheListeners.get_clients() |> List.delete(client))
    clients =
      case client do
        nil -> clients
        _ -> [client | clients]
      end
    payload = get_payload(server_response)
    Logger.debug("pushing #{inspect(payload)} (#{byte_size(payload)} bytes) to clients #{inspect(clients)}")
    do_push(clients, payload)
    {:noreply, state}
  end

  def handle_cast({:push_single_client, {client, server_response}}, state)
  do
    payload = get_payload(server_response)
    Logger.debug("pushing #{inspect(payload)} (#{byte_size(payload)} bytes) to client #{inspect(client)}")
    do_push([client], payload)
    {:noreply, state}
  end

  defp do_push([], _)
  do
    nil
  end

  defp do_push(_, nil)
  do
    nil
  end

  defp do_push([client | rest_clients], payload)
  do
    case :gen_tcp.send(client, payload) do
      {:error, error} ->
        CacheListeners.remove_client(client)
        Logger.debug("error while pushing to client #{inspect(client)}: #{inspect(error)}")
      _ ->
        nil
    end
    do_push(rest_clients, payload)
  end

  defp get_payload(%{data: nil, error: nil})
  do
    nil
  end

  defp get_payload(server_response)
  do
    {:ok, payload} = server_response |> ServerResponse.to_serializable() |> Poison.encode()
    payload_header = get_data_header(payload)
    payload_header <> payload
  end
end
