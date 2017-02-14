defmodule SqlSpCache.Cache.Item do
  @moduledoc false

  alias SqlSpCache.Server.Request

  defstruct request: %Request{}, key: "", data: nil, timestamp: 0, last_updated: nil, poll_scheduled: false
end
