defmodule Datacop.MixProject do
  use Mix.Project

  def project do
    [
      app: :datacop,
      version: "0.1.4",
      elixir: "~> 1.10",
      description: description(),
      package: package(),
      docs: [extras: ["README.md": [title: "README"]]],
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      licenses: ["Apache 2"],
      links: %{
        GitHub: "https://github.com/prosapient/datacop"
      }
    ]
  end

  defp description do
    """
    An authorization library with dataloader and absinthe support.
    """
  end

  defp deps do
    [
      {:dataloader, "~> 1.0 or ~> 2.0"},
      {:absinthe, "~> 1.6", optional: true},
      {:ex_doc, "~> 0.24", only: :dev, runtime: false}
    ]
  end
end
