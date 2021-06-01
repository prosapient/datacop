defmodule Datacop.UnauthorizedError do
  @type t :: Exception.t()
  defexception message: "Unauthorized"
end
