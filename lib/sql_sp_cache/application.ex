defmodule SqlSpCache.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      worker(Registry, [:unique, SqlSpCache.Registry.Cache]),
      worker(SqlSpCache.Server, []),      
    ]

    opts = [strategy: :one_for_one, name: SqlSpCache.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
