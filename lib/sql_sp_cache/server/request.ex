defmodule SqlSpCache.Server.Request do
  @mod __MODULE__

  @doc """
    token:
      a request specific token, provided by the client, so that the reponse can be matched against the initial request
    sp:
      name of stored procedure
    params:
      array of maps containing names and values of the stored procedure's parameters
      %{name: "x", type: "INT", direction: "INPUT", value: "y"}
    expire:
      duration of cached object in milliseconds
    poll:
      when positive, it is interpreted as an interval, in milliseconds, after which,
      the stored procedure is executed again and if the result is different,
      the new value is pushed to the client
  """
  defstruct token: "", sp: "", params: [], expire: 0, poll: 0

  def from_map(%{"sp" => ":" <> _command = sp} = request)
  do
    %@mod{
      sp: sp,
      params: map_params(request["params"] || [])
    }
  end

  def from_map(%{"sp" => sp, "expire" => expire} = request)
    when sp != nil and expire != nil
  do
    %@mod{
      token: request["token"] || nil,
      sp: sp,
      params: map_params(request["params"] || []),
      expire: expire || 0,
      poll: request["poll"] || 0
    }
  end

  def from_map(request)
  do
    %@mod{sp: "_INVALID_: #{inspect(request)}"}
  end

  defp map_params(params)
  do
    Enum.map(params, fn param -> %{
      name: param["name"],
      type: param["type"],
      direction: param["direction"],
      value: param["value"],
    } end)
  end
end
