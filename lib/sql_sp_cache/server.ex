defmodule SqlSpCache.Server do
  @moduledoc false
  @mod __MODULE__

  alias SqlSpCache.Server.Request
  alias SqlSpCache.Cache.Router

  def start_link() do
    [port: port] = Application.get_env(:sql_sp_cache, @mod, :port)
    {:ok, listen(port)}
  end

  defp listen(port) do
    spawn_link(fn ->
      {:ok, socket} = :gen_tcp.listen(port, [
            :binary,
            {:reuseaddr, true},
            {:active, false},
          ])
      accept(socket)
    end)
  end

  defp accept(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    spawn(fn -> receive_loop(client) end)
    accept(socket)
  end

  defp receive_loop(client) do
    with {:ok, <<x, y>>} <- :gen_tcp.recv(client, 2), length = Integer.undigits([x, y], 16) do
      case :gen_tcp.recv(client, length) do
        {:ok, data} ->
          data |> Msgpax.unpack() |> elem(1) |> IO.inspect(label: "req") |> Request.from_map() |> IO.inspect(label: "to_req") |> handle_request(client)
          receive_loop(client)
        _ -> nil
      end
    end
  end

  defp handle_request(%Request{} = request, client), do: Router.send_to_cache(request, client)
  defp handle_request(_error, _client), do: nil
end
