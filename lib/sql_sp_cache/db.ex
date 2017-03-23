defmodule SqlSpCache.DB do
  @moduledoc false
  @mod __MODULE__

  require Logger

  use GenServer

  alias SqlSpCache.DB.SQL
  alias SqlSpCache.Cache.Item, as: CacheItem
  alias SqlSpCache.Server.Request, as: ServerRequest

  def start_link()
  do
    GenServer.start_link(@mod, :ok, name: @mod)
  end

  def execute_sp({%CacheItem{} = _item, _client} = item_client)
  do
    GenServer.cast(@mod, {:execute_sp, {item_client, self()}})
  end

  def handle_cast({:execute_sp, {item_client, reply_to}}, state)
  do
    spawn(fn -> do_execute_sp(item_client, reply_to) end)
    {:noreply, state}
  end

  defp do_execute_sp({%{request: %ServerRequest{params: params} = server_request}, _client} = item_client, reply_to)
  do
    query = server_request |> get_query_from_server_request()
    case SQL.query(query) do
      {:ok, data} ->
        data = parse_db_results(data, params)
        send(reply_to, {:db_fetch, {item_client, {:ok, data}}})
      {:error, _} = error ->
        send(reply_to, {:db_fetch, {item_client, error}})
      {:error_retry, _} ->
        GenServer.cast(@mod, {:execute_sp, {item_client, reply_to}})
    end
  end

  defp get_query_from_server_request(server_request)
  do
    {declarations, input_params, output_params} = get_sql_params(server_request.params)
    IO.iodata_to_binary([
      Enum.join(declarations, "; "),
      (if length(declarations) === 0, do: "", else: "; "),
      "EXEC #{server_request.sp}",
      (if length(input_params) === 0 and length(output_params) === 0, do: "", else: " "),
      Enum.join(input_params, ", "),
      (if length(input_params) === 0 or length(output_params) === 0, do: "", else: ", "),
      output_params |> Enum.map(fn param -> param <> " OUTPUT" end) |> Enum.join(", "),
      (if length(output_params) === 0, do: "", else: "; SELECT " <> Enum.join(output_params, ", "))
    ])
  end

  #
  # get_sql_params
  #

  defp get_sql_params(params, declarations \\ [], input_params \\ [], output_params \\ [])

  defp get_sql_params([], declarations, input_params, output_params)
  do
    {declarations, input_params, output_params}
  end

  defp get_sql_params(
    [%{name: name, type: type, direction: "OUTPUT"} | rest_params], declarations, input_params, output_params)
  do
    get_sql_params(rest_params, ["DECLARE @#{name} #{type}" | declarations], input_params, ["@#{name}" | output_params])
  end

  defp get_sql_params(
    [%{name: name, value: value} | rest_params], declarations, input_params, output_params)
  when is_binary(value)
  do
    get_sql_params(rest_params, declarations, ["@#{name}='#{value}'" | input_params], output_params)
  end

  defp get_sql_params([%{name: name, value: value} | rest_params], declarations, input_params, output_params)
  do
    get_sql_params(rest_params, declarations, ["@#{name}=#{value}" | input_params], output_params)
  end

  #
  # parse_db_results
  #

  defp parse_db_results(db_result, params, columns \\ [], rows \\ [], output_values \\ %{})

  defp parse_db_results([], _, columns, rows, output_values)
  do
    %{columns: columns, rows: rows, output_values: output_values}
  end

  defp parse_db_results([%{columns: ["" | _], rows: [output_values]} | rest_db_results], params, columns, rows, _)
  do
    parse_db_results(rest_db_results, params, columns, rows, output_values_to_map(output_values, params))
  end

  defp parse_db_results([%{columns: cols, rows: rs} | rest_db_results], params, columns, rows, output_values)
  do
    parse_db_results(rest_db_results, params, columns ++ [cols], rows ++ [normalize_row_data(rs)], output_values)
  end

  #
  # normalize_row_data
  #

  defp normalize_row_data(rows, acc \\ [])

  defp normalize_row_data([], acc)
  do
    Enum.reverse(acc)
  end

  defp normalize_row_data([row | rest_rows], acc)
  do
    row = Enum.map(row, fn row_datum ->
      case row_datum do
        row_datum when is_binary(row_datum) ->
          try do
            with {:ok, _} <- Poison.encode(row_datum) do
              row_datum
            else
              _ -> Base.encode64(row_datum)
            end
          rescue
            _ -> Base.encode64(row_datum)
          end
        {{year, month, day}, {hour, minute, second, millisecond}} ->
          "#{year}-#{month}-#{day}T#{hour}:#{minute}:#{second}.#{millisecond}Z"
        _ ->
          row_datum
      end
    end)
    normalize_row_data(rest_rows, [row | acc])
  end

  defp output_values_to_map(output_values, params)
  do
    output_values
    |> Enum.zip(params)
    |> Enum.map(fn {[value], param} -> {param.name, value} end)
    |> Map.new()
  end
end
