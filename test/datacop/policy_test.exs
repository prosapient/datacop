defmodule Datacop.PolicyTest do
  use ExUnit.Case

  test "normalize_output/1" do
    reason = %Datacop.UnauthorizedError{message: "Unauthorized", action: :update_user}

    assert :ok = Datacop.Policy.normalize_output(:ok, :update_user)
    assert :ok = Datacop.Policy.normalize_output(true, :update_user)
    assert {:error, ^reason} = Datacop.Policy.normalize_output(false, :update_user)
    assert {:error, ^reason} = Datacop.Policy.normalize_output({:error, :Unauthorized}, :update_user)
    assert_raise FunctionClauseError, fn -> Datacop.Policy.normalize_output(%{}, :update_user) end
  end
end
