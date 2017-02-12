defmodule SqlSpCache.Cache.Item do
  alias SqlSpCache.Server.Request

  defstruct request: %Request{}, key: "", data: nil, timestamp: 0
end
