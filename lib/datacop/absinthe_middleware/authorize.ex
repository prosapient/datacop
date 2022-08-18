if Code.ensure_loaded?(Absinthe) do
  defmodule Datacop.AbsintheMiddleware.Authorize do
    @moduledoc """
    Performs authorization for the given resolution.

    This module helps to build authorization logic for batches, based on [`Dataloader`](https://hexdocs.pm/dataloader/Dataloader.html).
    Each time the middleware receives `{:dataloader, _dataloader_config}` tuple, it loads(accumulates) data in the `dataloader`
    struct, in order to run single query in the end. As a result, this middleware returns resolution with either
    a successfully resolved state or Datacop.UnauthorizedError.

    ## Options
    * `:loader` - either `dataloader` struct or 1-arity function, which can fetch `dataloader` struct,
      based on `c:Absinthe.Schema.context/1`. It uses default `Datacop.default_loader/1`, when the option is nil.
    * `:actor` - the actor struct, which is used in the authorize/3 function for the target module.
    * `:subject` - the subject struct, which is used in the authorize/3 function for the target module.
      By default this is resolution.source.
    * `:callback` - custom function callback, which handles Datacop result.


    ## Example
    ```elixir
    opts = [
      loader: &(&1.loader),
      actor: &(&1.actor),
      callback: fn
        :ok -> {:ok, true)
        error -> {:ok, false}
      end}
    ]
    middleware(Authorize, {MyApp.Blog, :view_stats, opts})
    ```
    """
    @behaviour Absinthe.Middleware

    @type opts() :: [
            actor: (context :: map() -> Datacop.actor()) | Datacop.actor(),
            subject: any(),
            loader: (context :: map() -> Dataloader.t()) | Dataloader.t(),
            callback: (:ok | {:error, Datacop.UnauthorizedError.t()} -> {:ok, any()} | {:error, map()})
          ]

    @impl Absinthe.Middleware
    def call(%{state: :unresolved} = resolution, {action, module}), do: call(resolution, {action, module, []})

    @impl Absinthe.Middleware
    def call(%{state: :unresolved} = resolution, {action, module, opts}) do
      actor = get_actor(resolution, opts)
      subject = Keyword.get(opts, :subject, resolution.source)
      custom_resolver = Keyword.get(opts, :callback)

      result =
        action
        |> module.authorize(actor, subject)
        |> Datacop.Policy.normalize_output(action)

      case {result, custom_resolver} do
        {:ok, nil} ->
          resolution

        {:ok, custom_resolver} ->
          Absinthe.Resolution.put_result(resolution, custom_resolver.(:ok))

        {{:error, error}, nil} ->
          Absinthe.Resolution.put_result(resolution, {:error, error})

        {{:error, error}, custom_resolver} ->
          Absinthe.Resolution.put_result(resolution, custom_resolver.({:error, error}))

        {{:dataloader, %{source_name: source_name, batch_key: batch_key, inputs: inputs} = params}, nil} ->
          loader = resolution |> get_loader(module, opts) |> Dataloader.load(source_name, batch_key, inputs)
          on_load = on_load(params, action, opts)
          context = Map.put(resolution.context, :loader, loader)
          middleware = [{__MODULE__, on_load} | resolution.middleware]

          if Dataloader.pending_batches?(loader) do
            %{resolution | state: :suspended, context: context, middleware: middleware}
          else
            resolution
          end

        {{:dataloader, %{source_name: source_name, batch_key: batch_key, inputs: inputs} = params}, _custom_resolver} ->
          loader = resolution |> get_loader(module, opts) |> Dataloader.load(source_name, batch_key, inputs)
          on_load = on_load(params, action, opts)
          context = Map.put(resolution.context, :loader, loader)
          middleware = [{Absinthe.Middleware.Dataloader, {loader, on_load}} | resolution.middleware]

          %{resolution | context: context, middleware: middleware}
      end
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

    defp on_load(%{source_name: source_name, batch_key: batch_key, inputs: inputs}, action, opts) do
      callback = Keyword.get(opts, :callback, &Function.identity/1)

      fn loader ->
        loader
        |> Dataloader.get(source_name, batch_key, inputs)
        |> Datacop.Policy.normalize_output(action)
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
