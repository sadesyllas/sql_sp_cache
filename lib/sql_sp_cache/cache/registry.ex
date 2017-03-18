defmodule SqlSpCache.Cache.Registry do
  @moduledoc false
  @mod __MODULE__

  require Logger

  def start_link()
  do
    Registry.start_link(:unique, @mod, partitions: System.schedulers_online())
  end

  def get_via!(name)
  do
    {:via, Registry, {@mod, String.trim(name)}}
  end

  def get_pid!({:via, Registry, {@mod, name}})
  do
    name = String.trim(name)
    case Registry.lookup(@mod, name) do
      [{pid, _}] ->
        pid
      _ ->
        Logger.error("did not find cache name #{name} in cache registry")
        nil
    end
  end
end
