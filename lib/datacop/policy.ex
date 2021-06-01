defmodule Datacop.Policy do
  @moduledoc """
  Where authorization rules live.

  Typically the callbacks are designed to be used by `Datacop.permit/4` and
  are not called directly.

  The only requirement is to implement the `authorize/3` callback:

      defmodule MyApp.MyContext do
        @behaviour Datacop.Policy

        def authorize(action, user, params) do
          # Return :ok or true to permit
          # Return {:error, reason}, or false to deny
          # Return {:dataloader, data} to process data in the Dataloader
        end
      end

  To perform authorization checks, use `Datacop.permit/4`:

      with :ok <- Datacop.permit(MyApp.MyContext, :action_name, user, subject: :value) do
        # ...
      end

      if Datacop.permit?(MyApp.MyContext, :action_name, user, subject: :value) do
        # ...
      end

  If you want to define the callbacks in another module, you can use
  `defdelegate`:

      defmodule MyApp.MyContext do
        defdelegate authorize(action, user, params), to: MyApp.MyContext.Policy
      end

  """

  @type dataloader_result ::
          {:dataloader,
           %{
             required(:source_name) => module(),
             required(:batch_key) => any(),
             required(:inputs) => any()
           }}

  @callback authorize(Datacop.action(), Datacop.actor(), subject :: any()) ::
              :ok | {:error, String.Chars.t()} | boolean() | dataloader_result()

  @doc false
  def normalize_output(:ok), do: :ok
  def normalize_output(true), do: :ok
  def normalize_output(false), do: {:error, %Datacop.UnauthorizedError{}}
  def normalize_output({:error, reason}), do: {:error, %Datacop.UnauthorizedError{message: to_string(reason)}}
  def normalize_output({:dataloader, opts}), do: {:dataloader, opts}
end
