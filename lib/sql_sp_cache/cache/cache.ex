defmodule SqlSpCache.Cache do
  @moduledoc false
  @mod __MODULE__

  use GenServer

  alias SqlSpCache.Cache.Item, as: CacheItem

  def start_link(%{name: name}) do
    GenServer.start_link(@mod, :ok, name: name)
  end

  def add_or_update(cache_name, %CacheItem{} = item) do
    IO.puts("received request for #{inspect(cache_name)} to cache item #{inspect(item)}")
  end

  def init(:ok) do
    {:ok, %{}}
  end
end
