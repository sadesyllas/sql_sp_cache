defmodule SqlSpCache.PubSub do
  @moduledoc false
  @mod __MODULE__

  def start_link()
  do
    Registry.start_link(:duplicate, @mod, partitions: System.schedulers_online())
  end

  def subscribe(topic)
  do
    Registry.unregister(@mod, topic)
    Registry.register(@mod, topic, true)
  end

  def unsubscribe(topic)
  do
    Registry.unregister(@mod, topic)
  end

  def publish(topic, message \\ nil)
  do
    spawn_link(fn ->
      Registry.dispatch(@mod, topic, fn subscriptions ->
        for {subscriber, _} <- subscriptions, do: send(subscriber, message)
      end)
    end)
  end

  defmodule Topics do
    @moduledoc false

    def cache_clean_up()
    do
      :pub_sub_topic_cache_clean_up
    end

    def client_disconnected()
    do
      :pub_sub_topic_client_disconnected
    end
  end
end
