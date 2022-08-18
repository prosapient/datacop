defmodule Datacop.UnauthorizedError do
  @type t :: Exception.t()
  defexception [:action, message: "Unauthorized"]
end
