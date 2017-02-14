defmodule SqlSpCache.Cache.Cleaner do
  @moduledoc false
  @mod __MODULE__

  use GenServer

  alias SqlSpCache.PubSub

  def start_link()
  do
    cleaning_interval = Application.get_env(:sql_sp_cache, @mod)[:cleaning_interval]
    GenServer.start_link(@mod, %{cleaning_interval: cleaning_interval}, name: @mod)
  end

  def init(%{cleaning_interval: cleaning_interval} = state)
  do
    Process.send_after(self(), :clean, cleaning_interval)
    {:ok, state}
  end

  def handle_info(:clean, %{cleaning_interval: cleaning_interval} = state)
  do
    PubSub.publish(PubSub.Topics.cache_clean(), :clean)
    Process.send_after(self(), :clean, cleaning_interval)
    {:noreply, state}
  end
end
