defmodule SqlSpCache.Mixfile do
  use Mix.Project

  def project do
    [app: :sql_sp_cache,
     version: "0.1.0",
     elixir: "~> 1.4-rc",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  def application do
    [
      extra_applications: [:timex, :logger],
      mod: {SqlSpCache.Application, []},
    ]
  end

  defp deps do
    [
      {:poison, "~> 3.1"},
      {:timex, "~> 3.1"},
    ]
  end
end
