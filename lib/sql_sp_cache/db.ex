defmodule SqlSpCache.DB do
  @moduledoc false
  @mod __MODULE__

  require Logger

  use GenServer

  alias SqlSpCache.Cache.Item, as: CacheItem
  alias SqlSpCache.Server.Request, as: ServerRequest

  def start_link(db_connection_string)
  do
    :odbc.start()
    GenServer.start_link(@mod, db_connection_string, name: @mod)
  end

  def execute_sp({%CacheItem{} = _item, _client} = item_client)
  do
    GenServer.cast(@mod, {:execute_sp, {item_client, self()}})
  end

  def init(db_connection_string)
  do
#    Process.send_after(self(), :connect, 5) # TODO: restore
    {:ok, %{db_connection_string: db_connection_string}}
  end

  def handle_cast(
    {:execute_sp, {{item, _client} = item_client, reply_to}},
    %{db_connection_string: db_connection_string} = state)
  do
    spawn(fn ->
      result =
        with {:ok, db} <- db_connection_string |> to_charlist() |> :odbc.connect([]) do
          result = do_execute_sp(db, item.request)
          :odbc.disconnect(db)
          result
        else
          {:error, error} ->
            error = IO.iodata_to_binary(error)
            Logger.error("error while executing sp: #{error}")
            {:error, error}
          error ->
            error = inspect(error)
            Logger.error("error while executing sp: #{error}")
            {:error, error}
        end
      send(reply_to, {:db_fetch, {item_client, result}})
    end)
    {:noreply, state}
  end

#  def handle_cast({:execute_sp, {{item, _client} = item_client, reply_to}}, %{db: db} = state)
#  do
#    result = do_execute_sp(db, item.request)
#    send(reply_to, {:db_fetch, {item_client, result}})
#    {:noreply, state}
#  end
#
#  def handle_info(:connect, %{db_connection_string: db_connection_string} = state)
#  do
#    new_state =
#      case db_connection_string |> to_charlist() |> :odbc.connect([]) do
#        {:ok, db} ->
#          Map.put(state, :db, db)
#        {:error, :connection_closed} ->
#          Logger.warn("db connection has been closed and will be reopened")
#          Process.send_after(@mod, :connect, Application.get_env(:sql_sp_cache, @mod)[:db_reconnection_delay])
#          state
#        {:error, error} ->
#          Logger.error("db connection error: #{error}")
#          state
#      end
#    {:noreply, new_state}
#  end

  def handle_info(info, state)
  do
    Logger.debug("received unhandled db info message #{inspect(info)}")
    {:noreply, state}
  end

  defp do_execute_sp(db, %ServerRequest{params: params} = server_request)
  do
    query =
      server_request
      |> get_query_from_server_request()
      |> to_charlist()
    timeout = Application.get_env(:sql_sp_cache, @mod)[:db_query_timeout]
#    receive do '_____' -> nil after 10_000 -> nil end # TODO: remove
    case :odbc.sql_query(db, query, timeout) do # TODO: restore
#    case [{:selected, ['x', 'y'], [{1, round(abs(:rand.normal()))}]}, {:selected, [[]], [{0}]}] do # TODO: remove
      {:selected, _, _} = db_result ->
        {:ok, parse_db_results([db_result], params)}
      [{:selected, _, _} | _] = db_results ->
        {:ok, parse_db_results(db_results, params)}
      {:error, error} ->
        error = to_string(error)
        Logger.error("an error occurred during sp execution: #{error} (#{inspect(server_request)})")
        {:error, error}
      error ->
        Logger.error("an error occurred during sp execution: #{inspect(error)} (#{inspect(server_request)})")
        {:error, error}
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

  defp parse_db_results([{:selected, [[]], output_value_data} | rest_db_results], params, columns, rows, _)
  do
    parse_db_results(
      rest_db_results,
      params,
      columns,
      rows,
      output_value_data |> data_to_binary() |> output_values_to_map(params))
  end

  defp parse_db_results([{:selected, column_names, row_data} | rest_db_results], params, columns, rows, output_values)
  do
    column_names = data_to_binary(column_names)
    row_data = data_to_binary(row_data)
    parse_db_results(rest_db_results, params, columns ++ [column_names], rows ++ [row_data], output_values)
  end

  #
  # data_to_binary
  #

  defp data_to_binary(data, acc \\ [])

  defp data_to_binary([], acc)
  do
    Enum.reverse(acc)
  end

  # here datum should be the name of a column
  defp data_to_binary([datum | data], acc) when is_list(datum)
  do
    data_to_binary(data, [to_string(datum) | acc])
  end

  # here datum should be a tuple representing a row of data
  defp data_to_binary([datum | data], acc)
  do
    datum = Enum.map(Tuple.to_list(datum), fn datum_part ->
      case datum_part do
        datum_part when is_list(datum_part) ->
          to_string(datum_part)
        datum_part when is_binary(datum_part) ->
          datum_part |> String.split("", trim: true) |> Enum.filter(&String.printable?/1) |> to_string()
        {{year, month, day}, {hour, minute, second}} ->
          "#{year}-#{month}-#{day}T#{hour}:#{minute}:#{second}Z"
        _ ->
          datum_part
      end
    end)
    data_to_binary(data, [datum | acc])
  end

  defp output_values_to_map(output_values, params)
  do
    output_values
    |> Enum.zip(params)
    |> Enum.map(fn {[value], param} -> {param.name, value} end)
    |> Map.new()
  end
end
