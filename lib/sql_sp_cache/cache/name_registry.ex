defmodule SqlSpCache.Cache.NameRegistry do
  @moduledoc false
  @mod __MODULE__

  def start_link()
  do
    Registry.start_link(:duplicate, @mod, partitions: System.schedulers_online())
  end

  def register()
  do
    Registry.register(@mod, @mod, nil)
  end

  def lookup()
  do
    Registry.lookup(@mod, @mod)
  end
end
