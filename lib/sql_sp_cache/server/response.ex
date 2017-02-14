defmodule SqlSpCache.Server.Response do
  @moduledoc false
  @mod __MODULE__

  @doc """
    token:
      a request specific token, provided by the client, so that the reponse can be matched against the initial request
    data:
      the data returned as the response to the request made
    error:
      a string identifying the error that occurred while processing a request
    error_params:
      a key/value map of parameters regarding the error in the response
    last_updated:
      the date when the data were last updated
  """
  defstruct token: nil, data: nil, error: nil, error_params: %{}, last_updated: nil

  def to_serializable(%@mod{
    token: token,
    data: data,
    error: error,
    error_params: error_params,
    last_updated: last_updated})
  do
    %{
      "token" => token,
      "data" => data,
      "error" => error,
      "error_params" => error_params,
      "last_updated" =>
        case last_updated do
          nil -> nil
          _ -> Timex.format!(last_updated, "{ISO:Extended}")
        end
    }
  end
end
