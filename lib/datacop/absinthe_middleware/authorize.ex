if Code.ensure_loaded?(Absinthe) do
  defmodule Datacop.AbsintheMiddleware.Authorize do
    @moduledoc """
    Performs authorization for the given resolution.

    With Datacop module we are able to get `{:dataloader, _dataloader_config}` while authorizing, when
    we work with batched fields. To process result we should accumulate these params for all fields.
    When the data is ready, we call the appropriated callback and process results
    to return resolution with either resolved state or Absinthe error.

    ## Example
    ```elixir
    middleware(Datacop.AbsintheMiddleware.Authorize, {:view_users, MyApp.MyContext})
    middleware(Datacop.AbsintheMiddleware.Authorize, {:view_users, MyApp.MyContext, opts})
    ```

    We also are able to run this middleware from the resolve function, with custom callback fuction:

    ```elixir
    {:middleware, Datacop.AbsintheMiddleware.Authorize,
      callback: fn
        :ok -> {:ok, true)
        error -> {:ok, false}
      end}
    ```

    In the latter case this middleware uses `Absinthe.Middleware.Dataloader` under the hood for `{:dataloader, _config}`
    authorization result, and resolve the value with custom callback.

    The source field from resolution is the subject in case of empty subject option.

    You can also pass a function, to fetch loader or actor struct from the resolution.context with options like:
    ```elixir
    [actor: &(&1.current_user), loader: &(&1.loader)]
    ```
    """
    @behaviour Absinthe.Middleware

    @type opts() :: [
            actor: (context :: map() -> Datacop.actor()) | Datacop.actor(),
            subject: any(),
            loader: (context :: map() -> Dataloader.t()) | Dataloader.t(),
            callback: (:ok | {:error, Datacop.UnauthorizedError.t()} -> {:ok, any()} | {:error, map})
          ]

    @impl Absinthe.Middleware
    def call(%{state: :unresolved} = resolution, {action, module}), do: call(resolution, {action, module, []})

    @impl Absinthe.Middleware
    def call(%{state: :unresolved} = resolution, {action, module, opts}) do
      actor = get_actor(resolution, opts)
      subject = Keyword.get(opts, :subject, resolution.source)
      custom_resolver = Keyword.get(opts, :callback)

      action
      |> module.authorize(actor, subject)
      |> Datacop.Policy.normalize_output()
      |> process(resolution, module, custom_resolver, opts)
    end

    @impl Absinthe.Middleware
    def call(%{state: :suspended} = resolution, callback) do
      resolution.context.loader
      |> callback.()
      |> case do
        :ok -> %{resolution | state: :unresolved}
        error -> Absinthe.Resolution.put_result(resolution, error)
      end
    end

    @impl Absinthe.Middleware
    def call(resolution, _params), do: resolution

    defp process(result, resolution, module, resolver, opts) when is_nil(resolver) do
      case result do
        {:dataloader, %{source_name: source_name, batch_key: batch_key, inputs: inputs}} ->
          loader = resolution |> get_loader(module, opts) |> Dataloader.load(source_name, batch_key, inputs)
          on_load = on_load(source_name, batch_key, inputs, opts)
          context = Map.put(resolution.context, :loader, loader)
          middleware = [{__MODULE__, on_load} | resolution.middleware]

          %{resolution | state: :suspended, context: context, middleware: middleware}

        :ok ->
          resolution

        error ->
          Absinthe.Resolution.put_result(resolution, error)
      end
    end

    defp process(result, resolution, module, resolver, opts) when not is_nil(resolver) do
      case result do
        {:dataloader, %{source_name: source_name, batch_key: batch_key, inputs: inputs}} ->
          loader = resolution |> get_loader(module, opts) |> Dataloader.load(source_name, batch_key, inputs)
          on_load = on_load(source_name, batch_key, inputs, opts)
          context = Map.put(resolution.context, :loader, loader)
          middleware = [{Absinthe.Middleware.Dataloader, {loader, on_load}} | resolution.middleware]

          %{resolution | context: context, middleware: middleware}

        result ->
          Absinthe.Resolution.put_result(resolution, resolver.(result))
      end
    end

    defp on_load(source_name, batch_key, inputs, opts) do
      callback = Keyword.get(opts, :callback, &Function.identity/1)

      fn loader ->
        loader
        |> Dataloader.get(source_name, batch_key, inputs)
        |> Datacop.Policy.normalize_output()
        |> callback.()
      end
    end

    defp get_actor(resolution, opts) do
      case opts[:actor] do
        get_actor when is_function(get_actor, 1) -> get_actor.(resolution.context)
        actor -> actor
      end
    end

    defp get_loader(resolution, module, opts) do
      case opts[:loader] do
        nil -> Datacop.default_loader(module)
        get_loader when is_function(get_loader, 1) -> get_loader.(resolution.context)
        loader -> loader
      end
    end
  end
end
