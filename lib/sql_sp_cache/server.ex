defmodule SqlSpCache.Server do
  @moduledoc false
  @mod __MODULE__

  require Logger

  alias SqlSpCache.Server.Request, as: CacheRequest
  alias SqlSpCache.Cache.Listeners, as: CacheListeners
  alias SqlSpCache.Cache.Router

  def start_link()
  do
    port = Application.get_env(:sql_sp_cache, @mod)[:port]
    {:ok, listen(port)}
  end

  defp listen(port)
  do
    spawn_link(fn ->
      {:ok, socket} = :gen_tcp.listen(port, [
            :binary,
            {:reuseaddr, true},
            {:active, false},
        ])
      Logger.info("server listening to port #{port}")
      accept(socket)
    end)
  end

  defp accept(socket)
  do
    {:ok, client} = :gen_tcp.accept(socket)
    Logger.debug("client connected from #{get_client_ip_port(client)}")
    receive_timeout = Application.get_env(:sql_sp_cache, @mod)[:receive_timeout]
    spawn(fn -> receive_loop(client, receive_timeout) end)
    accept(socket)
  end

  defp receive_loop(client, receive_timeout)
  do
    try do
      with\
        {:ok, <<x, y>>} <- :gen_tcp.recv(client, 2, receive_timeout),
        length = Integer.undigits([x, y], 256),
        true <- length != 0 || :heartbeat,
        {:ok, data} <- :gen_tcp.recv(client, length, receive_timeout)
      do
        case byte_size(data) != 0 do
          true ->
            data
            |> Poison.decode()
            |> log_request_debug(client)
            |> elem(1)
            |> CacheRequest.from_map()
            |> handle_request(client)
          false ->
            nil
        end
        receive_loop(client, receive_timeout)
      else
        :heartbeat ->
          log_heartbeats = Application.get_env(:sql_sp_cache, @mod)[:log_heartbeats]
          if log_heartbeats do
            Logger.debug("received heartbeat from client #{get_client_ip_port(client)}")
          end
          receive_loop(client, receive_timeout)
        {:error, :timeout} ->
          receive_timeout = Application.get_env(:sql_sp_cache, @mod)[:receive_timeout]
          Logger.debug("timeout of #{receive_timeout}ms elapsed while waiting for data from client"
            <> " #{get_client_ip_port(client)}")
          :gen_tcp.close(client)
          nil
        error ->
          error =
            case error do
              {:error, error} -> error
              error -> error
            end
          CacheListeners.remove_client(client)
          :gen_tcp.close(client)
          Logger.debug("error #{inspect(error)} receiving from client #{get_client_ip_port(client)}")
          nil
      end
    rescue
      error ->
        CacheListeners.remove_client(client)
        Logger.debug("error #{error.message} receiving from client #{get_client_ip_port(client)}")
        nil
    end
  end

  defp handle_request(%CacheRequest{sp: "_INVALID_" <> _request_string} = request, client)
  do
    Logger.error("got invalid request from #{get_client_ip_port(client)}: #{inspect(request)}")
  end

  defp handle_request(%CacheRequest{} = request, client)
  do
    Router.send_to_cache(request, client)
  end

  defp get_client_ip_port(client)
  do
    :inet.peername(client)
    |> (fn client_info ->
      with {:ok, {client_ip, client_port}} <- client_info do
        "#{:inet.ntoa(client_ip)}:#{client_port}"
      else
        _ -> inspect(client)
      end
    end).()
  end

  defp log_request_debug(request, client)
  do
    Logger.debug("got request from #{get_client_ip_port(client)}: #{inspect(request)}")
    request
  end
end
