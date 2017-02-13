defmodule SqlSpCache.Cache.Item do
  @moduledoc false

  alias SqlSpCache.Server.Request

  defstruct request: %Request{}, key: "", data: nil, timestamp: 0, listeners: []
end
