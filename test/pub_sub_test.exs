defmodule SqlSpCache.PubSub.Test do
  use ExUnit.Case, async: true

  alias SqlSpCache.PubSub

  test "subscribing and publishing"
  do
    PubSub.subscribe(PubSub.Topics.cache_clean())
    PubSub.publish(PubSub.Topics.cache_clean())
    assert_receive nil, 500
  end

  test "doubly subscribing and receiving only once"
  do
    PubSub.subscribe(PubSub.Topics.cache_clean())
    PubSub.subscribe(PubSub.Topics.cache_clean())
    PubSub.publish(PubSub.Topics.cache_clean())
    assert_receive nil, 500
    receive do
      _ -> assert false
    after
      500 -> true
    end
  end

  test "subscribing, unsubscribing  and then not receiving"
  do
    PubSub.subscribe(PubSub.Topics.cache_clean())
    PubSub.unsubscribe(PubSub.Topics.cache_clean())
    PubSub.publish(PubSub.Topics.cache_clean())
    receive do
      _ -> assert false
    after
      500 -> true
    end
  end
end
