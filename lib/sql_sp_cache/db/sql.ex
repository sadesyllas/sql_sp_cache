defmodule SqlSpCache.DB.SQL do
  @mod __MODULE__

  use Ecto.Repo, otp_app: :sql_sp_cache

  def query(query)
  do
    timeout = Application.get_env(:sql_sp_cache, @mod)[:db_query_timeout]
    try do
      result = Ecto.Adapters.SQL.query(@mod, query, [], [timeout: timeout || 5_000, pool_timeout: :infinity])
      with {:ok, data} <- result do
        {:ok, data}
      else
        {:error, error} ->
          error = inspect(error)
          Logger.error("error while executing sp: #{error}")
          {:error, error}
        error ->
          error = inspect(error)
          Logger.error("error while executing sp: #{error}")
          {:error, error}
      end
    catch
      :exit, error ->
        error = inspect(error)
        Logger.error("caught error while executing sp: #{error}")
        {:error_retry, error}
    rescue
      error ->
        error = inspect(error)
        Logger.error("rescued error while executing sp: #{error}")
        {:error_retry, error}
    end
  end
end
