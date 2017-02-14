defmodule SqlSpCache.Application do
  @moduledoc false

  use Application

  def start(_type, _args)
  do
    import Supervisor.Spec, warn: false

    children = [
      supervisor(SqlSpCache.Cache.Supervisor, []),
      worker(SqlSpCache.PubSub, []),
      worker(SqlSpCache.Push, []),
      worker(SqlSpCache.DB, [Application.get_env(:sql_sp_cache, SqlSpCache.DB)[:db_connection_string]]),
      worker(SqlSpCache.Cache.Listeners, []),
      worker(SqlSpCache.Cache.Registry, []),
      worker(SqlSpCache.Cache.Cleaner, []),
      worker(SqlSpCache.Server, []),
    ]

    opts = [strategy: :one_for_one, name: SqlSpCache.Supervisor]

    Supervisor.start_link(children, opts)
  end
end
