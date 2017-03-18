defmodule SqlSpCache.Cache.Cleaner do
  @moduledoc false
  @mod __MODULE__

  use GenServer

  alias SqlSpCache.PubSub

  def start_link()
  do
    clean_up_interval = Application.get_env(:sql_sp_cache, @mod)[:clean_up_interval]
    GenServer.start_link(@mod, %{clean_up_interval: clean_up_interval}, name: @mod)
  end

  def init(%{clean_up_interval: clean_up_interval} = state)
  do
    Process.send_after(self(), :clean_up, clean_up_interval)
    {:ok, state}
  end

  def handle_info(:clean_up, %{clean_up_interval: clean_up_interval} = state)
  do
    PubSub.publish(PubSub.Topics.cache_clean_up(), :clean_up)
    Process.send_after(self(), :clean_up, clean_up_interval)
    {:noreply, state}
  end
end
