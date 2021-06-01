defmodule Datacop.PolicyTest do
  use ExUnit.Case

  test "normalize_output/1" do
    reason = %Datacop.UnauthorizedError{message: "Unauthorized"}
    assert :ok = Datacop.Policy.normalize_output(:ok)
    assert :ok = Datacop.Policy.normalize_output(true)
    assert {:error, ^reason} = Datacop.Policy.normalize_output(false)
    assert {:error, ^reason} = Datacop.Policy.normalize_output({:error, :Unauthorized})
    assert_raise FunctionClauseError, fn -> Datacop.Policy.normalize_output(%{}) end
  end
end
