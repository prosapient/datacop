# Datacop

An authorization library with Dataloader and Absinthe support.

This library is heavily inspired by [bodyguard](https://hex.pm/packages/bodyguard).
Our authorization rules not always simple, so `datacop` allows you to deal with n+1 queries using `dataloader`.

## Installation

The package can be installed by adding `datacop` and optionally `absinthe` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:datacop, "~> 0.1"},
    {:absinthe, "~> 1.6"}
  ]
end
```

## Usage
### Define a Policy module with authorization rules
This module should contain authorization rules or redirect resolution to `dataloader` for batch resolutions.
Try to keep authorize callback pure and redirect side effects to `dataloader`.

```elixir
defmodule MyApp.Blog.Policy do
  @behaviour Datacop.Policy

  @imp true
  def authorize(:delete_post, actor, _post), do: actor.id == post.author_id or actor.admin?

  def authorize(:view_stats, actor, post) do
    if actor.admin? do
      {:dataloader,
       %{
         source_name: MyApp.Blog,
         batch_key: {:one, MyApp.Blog.Post},
         inputs: [{{:can_admin_view_stats?, actor.id}, post.id}]
       }}
    else
      false
    end
  end
end
```

### Define a Data module for integration with `dataloader`
A typical module for working with `dataloader`. In this example we use [`Dataloader.Ecto`](https://hexdocs.pm/dataloader/Dataloader.Ecto.html).
See documentation for this module for detailed explanation how it works.
Batch query should return a list of boolean values in the same order which `post_ids` has.
```elixir
defmodule MyApp.Blog.Data do
  def data do
    Dataloader.Ecto.new(MyApp.Repo, run_batch: &run_batch/5)
  end

  def run_batch(queryable, _query, {:can_admin_view_stats?, admin_id}, post_ids, repo_opts, _params) do
    result =
      queryable
      |> very_complex_query_returns_posts_which_are_managed_by_admin(admin_id, post_ids)
      |> select([posts], {posts.id, true})
      |> MyApp.Repo.all(repo_opts)
      |> Map.new()

    Enum.map(post_ids, &Map.get(result, &1, false))
  end
end
```

### Use context module as a proxy
It is not necessary to do this, but otherwise you'll have to refer to Data and Policy modules directly in places
where corresponding functions are invoked.

```elixir
defmodule MyApp.Blog do
  defdelegate authorize(action, actor, params), to: __MODULE__.Policy
  defdelegate data, to: __MODULE__.Data
end
```

### Setup dataloader in Absinthe schema
See [this guide](https://hexdocs.pm/absinthe/dataloader.html#usage) for reference.
In general implementation of `c:Absinthe.Schema.context/1` should look like this:
```elixir
def context(ctx) do
  loader =
    Dataloader.new() |> Dataloader.add_source(MyApp.Blog, MyApp.Blog.data())

  Map.put(ctx, :loader, loader)
end
```

### Use as a single action
Because absinthe defines `:loader` in `c:Absinthe.Schema.context/1` callback, we can reuse it in resolver functions by passing `:loader` option explicitly:
```elixir
def delete_post(params, %{context: %{actor: actor, loader: loader}}) do
  with {:ok, post} <- MyApp.Blog.fetch_post(params.post_id),
       :ok <- Datacop.permit(MyApp.Blog, :delete_post, actor, subject: post, loader: loader) do
    MyApp.Blog.delete_post(post, params)
  end
end
```
If you don't pass `:loader`, then `datacop` checks if passed module (in example above it is `MyApp.Blog`) has `data/0` function. If yes, then loader can be lazily initiated by `datacop` for single source with passed module as a `:source_name`.

For our example this call will work:
```elixir
Datacop.permit(MyApp.Blog, :view_stats, actor, subject: post)
```
which is a short version of:
```elixir
Datacop.permit(MyApp.Blog, :view_stats, actor,
  subject: post,
  loader: Dataloader.new() |> Dataloader.add_source(MyApp.Blog, MyApp.Blog.data())
)
```
but this won't (`MyApp.Blog.Policy` doesn't implement `data/0`):
```elixir
Datacop.permit(MyApp.Blog.Policy, :view_stats, actor, subject: post)
```
The next example works fine, as `:delete_post` action doesn't use dataloader:
```elixir
Datacop.permit(MyApp.Blog.Policy, :delete_post, actor, subject: post)
```
With `Datacop.permit?/4` it's also possible to work with booleans:
```elixir
Datacop.permit?(MyApp.Blog, :search, actor, loader: loader)}
```

### Use as Absinthe middleware
In order to leverage full potential of `datacop` it is recommended to use it with `absinthe`.
```elixir
alias Datacop.AbsintheMiddleware.Authorize

object :post do
  field :id, :id
  field :stats, :stats do
    middleware(Authorize, {MyApp.Blog, :view_stats, loader: &(&1.loader), actor: &(&1.actor)})
    resolve(...)
  end
end
```
In order to DRY you may want to provide a custom middleware on top of existing one:
```elixir
defmodule MyApp.Schema.Middleware.Authorize do
  @behaviour Absinthe.Middleware

  @impl Absinthe.Middleware
  def call(resolution, {action, context_module}) do
    call(resolution, {action, context_module, []})
  end

  @impl Absinthe.Middleware
  def call(resolution, {action, context_module, opts}) do
    opts =
      opts
      |> Keyword.put_new(:actor, &(&1.actor))
      |> Keyword.put_new(:loader, &(&1.loader))

    params = {action, context_module, opts}

    %{resolution | middleware: [{Authorization.AbsintheMiddleware.Authorize, params} | resolution.middleware]}
  end
end
```

and a helper on top of it
```elixir
def authorize(action, module, opts \\ []) do
  {:middleware, PtWeb.Schema.Middleware.Authorize, {action, module, opts}}
end
```
so block with `:stats` contains less noise:
```elixir
field :stats, :stats do
  authorize(MyApp.Blog, :view_stats)
  resolve(...)
end
```

That's it. Now if you request list of posts, then authorization will be performed in batches.
