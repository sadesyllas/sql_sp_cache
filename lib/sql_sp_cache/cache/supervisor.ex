defmodule SqlSpCache.Cache.Supervisor do
  @moduledoc false
  @mod __MODULE__

  use Supervisor

  def start_link() do
    Supervisor.start_link(@mod, :ok, name: @mod)
  end

  def start_child(cache_name) do
    cache =
      case Supervisor.start_child(@mod, [%{name: cache_name}]) do
        {:ok, cache} -> cache
        {:error, {:already_started, cache}} -> cache
      end
    {:ok, cache}
  end

  def init(:ok) do
    children = [
      worker(SqlSpCache.Cache, [], restart: :transient)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
