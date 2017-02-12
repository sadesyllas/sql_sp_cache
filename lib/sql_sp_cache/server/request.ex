defmodule SqlSpCache.Server.Request do
  @mod __MODULE__

  @doc """
    sp:
      name of stored procedure
    params:
      map containing names and values of the stored procedure's parameters
    exp:
      duration of cached object in milliseconds
    poll:
      when positive, it is interpreted as an interval, in milliseconds, after which,
      the stored procedure is executed again and if the result is different,
      the new value is pushed to the client
  """
  defstruct sp: "", params: %{}, exp: 0, poll: 0

  def from_map(%{"sp" => sp, "params" => params, "exp" => exp, "poll" => poll}) do
    %@mod{
      sp: sp,
      params: params,
      exp: exp,
      poll: poll
    }
  end
end
