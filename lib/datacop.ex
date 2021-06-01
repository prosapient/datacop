defmodule Datacop do
  @moduledoc """
  An authorization library with `Dataloader` and `Absinthe` support.
  """

  @typedoc """
  Option

  * `:subject` – any value you want to access in the authorize/3 callback.
  * `:loader` – an initialized Dataloader struct with loaded sources.
  """
  @type option :: {:subject, any()} | {:loader, Dataloader.t()}

  @typedoc "Any term which describes an action you want to perform. Usually atoms are used."
  @type action :: term()

  @typedoc "Usually your user struct"
  @type actor :: term()

  @doc """
  Authorize an action.

  Processes `c:Datacop.Policy.authorize/3` result.

  ## Examples

      > Datacop.permit(MyApp.Accounts, :view_email, current_user, subject: other_user)
      :ok

      > Datacop.permit(MyApp.Accounts, :view_email, current_user, subject: other_user, loader: loader)
      {:error, %Datacop.UnauthorizedError{message: "Unauthorized"}}
  """
  @spec permit(policy :: module(), action(), actor(), opts :: [option()]) ::
          :ok | {:error, Datacop.UnauthorizedError.t()}
  def permit(module, action, actor, opts \\ []) do
    subject = Keyword.get(opts, :subject)

    case module.authorize(action, actor, subject) do
      {:dataloader, %{source_name: source_name, batch_key: batch_key, inputs: inputs}} ->
        loader = Keyword.get_lazy(opts, :loader, fn -> default_loader(module) end)

        loader
        |> Dataloader.load(source_name, batch_key, inputs)
        |> Dataloader.run()
        |> Dataloader.get(source_name, batch_key, inputs)
        |> Datacop.Policy.normalize_output()

      result ->
        Datacop.Policy.normalize_output(result)
    end
  end

  @doc """
  The same as `permit/4`, but returns a `boolean`.
  """
  @spec permit?(policy :: module(), action(), actor(), opts :: [option()]) :: boolean()
  def permit?(module, action, actor, opts \\ []) do
    module
    |> permit(action, actor, Keyword.delete(opts, :callback))
    |> case do
      :ok -> true
      _ -> false
    end
  end

  @doc """
  Returns initialized dataloader struct with the source.

  It requires `data/0` function to be defined for the particular module.
  """
  def default_loader(module) do
    if Kernel.function_exported?(module, :data, 0) do
      Dataloader.new() |> Dataloader.add_source(module, module.data())
    else
      raise ArgumentError, "Cannot automatically determine the source of
        #{inspect(module)} - specify the `data/0` function OR pass loader explicitly"
    end
  end
end
