defmodule DatacopTest do
  use ExUnit.Case
  doctest Datacop

  defmodule User do
    @enforce_keys [:id, :name]
    defstruct [:id, :name]
  end

  defmodule Policy do
    def authorize(action, actor), do: authorize(action, actor, nil)
    def authorize(:view_true, _actor, _subject), do: true
    def authorize(:view_false, _actor, _subject), do: {:error, :Unauthorized}
    def authorize(:view_ok, _actor, _subject), do: :ok
    def authorize(:view_error, _actor, _subject), do: {:error, :Unauthorized}

    def authorize(:view_dataloader, actor, subject) do
      data = %{source_name: DatacopTest.Accounts, batch_key: :id, inputs: {actor.id, subject}}
      {:dataloader, data}
    end
  end

  defmodule Accounts do
    defdelegate authorize(action, user), to: DatacopTest.Policy
    defdelegate authorize(action, user, params), to: DatacopTest.Policy

    def data do
      storage = [
        %{id: 1, name: "Apple", user_id: 1},
        %{id: 2, name: "Amazon", user_id: 2},
        %{id: 3, name: "Dell", user_id: 1}
      ]

      authorize = fn
        %{user_id: user_id}, actor_id -> user_id == actor_id
        _, _ -> false
      end

      load_function = fn batch_key, inputs ->
        Enum.into(inputs, %{}, fn {actor_id, subject} = input ->
          data =
            storage
            |> Enum.find(&(Map.get(&1, batch_key, :id) == subject))
            |> authorize.(actor_id)

          {input, data}
        end)
      end

      Dataloader.KV.new(load_function)
    end
  end

  setup do
    user1 = %User{id: 1, name: "Ben"}
    user2 = %User{id: 2, name: "John"}

    loader = Dataloader.new() |> Dataloader.add_source(Accounts, Accounts.data())
    %{loader: loader, user1: user1, user2: user2}
  end

  test "permit/5", %{loader: loader, user1: user1, user2: user2} do
    reason = %Datacop.UnauthorizedError{message: "Unauthorized"}

    assert :ok = Datacop.permit(Accounts, :view_true, user1)
    assert {:error, ^reason} = Datacop.permit(Accounts, :view_false, user1)
    assert :ok = Datacop.permit(Accounts, :view_ok, user1)
    assert {:error, ^reason} = Datacop.permit(Accounts, :view_error, user1)

    assert :ok = Datacop.permit(Accounts, :view_dataloader, user1, subject: 1)
    assert {:error, ^reason} = Datacop.permit(Accounts, :view_dataloader, user1, subject: 2)
    assert :ok = Datacop.permit(Accounts, :view_dataloader, user1, subject: 3)

    assert :ok = Datacop.permit(Accounts, :view_dataloader, user1, subject: 1, loader: loader)
    assert {:error, ^reason} = Datacop.permit(Accounts, :view_dataloader, user1, subject: 2, loader: loader)
    assert :ok = Datacop.permit(Accounts, :view_dataloader, user1, subject: 3, loader: loader)

    assert {:error, ^reason} = Datacop.permit(Accounts, :view_dataloader, user2, subject: 1)
    assert :ok = Datacop.permit(Accounts, :view_dataloader, user2, subject: 2)
    assert {:error, ^reason} = Datacop.permit(Accounts, :view_dataloader, user2, subject: 3)
  end

  test "permit?/5", %{loader: loader, user1: user1, user2: user2} do
    assert Datacop.permit?(Accounts, :view_true, user1)
    refute Datacop.permit?(Accounts, :view_false, user1)
    assert Datacop.permit?(Accounts, :view_ok, user1)
    refute Datacop.permit?(Accounts, :view_error, user1)

    assert Datacop.permit?(Accounts, :view_dataloader, user1, subject: 1)
    refute Datacop.permit?(Accounts, :view_dataloader, user1, subject: 2)
    assert Datacop.permit?(Accounts, :view_dataloader, user1, subject: 3)

    assert Datacop.permit?(Accounts, :view_dataloader, user1, subject: 1, loader: loader)
    refute Datacop.permit?(Accounts, :view_dataloader, user1, subject: 2, loader: loader)
    assert Datacop.permit?(Accounts, :view_dataloader, user1, subject: 3, loader: loader)

    refute Datacop.permit?(Accounts, :view_dataloader, user2, subject: 1)
    assert Datacop.permit?(Accounts, :view_dataloader, user2, subject: 2)
    refute Datacop.permit?(Accounts, :view_dataloader, user2, subject: 3)
  end

  test "default_loader/1" do
    %{sources: sources} = Datacop.default_loader(Accounts)
    assert Map.has_key?(sources, Accounts)
    assert %Dataloader.KV{} = sources[Accounts]
  end
end
