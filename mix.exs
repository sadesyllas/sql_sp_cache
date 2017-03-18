defmodule SqlSpCache.Mixfile do
  use Mix.Project

  def project do
    [app: :sql_sp_cache,
     version: "1.0.0",
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
      {:ecto, "~> 1.1", override: true},
      {:logger_file_backend, "~> 0.0.9"},
      {:poison, "~> 2.0"},
      {:tds, git: "https://github.com/StoiximanServices/tds.git", override: true},
      {:tds_ecto, git: "https://github.com/StoiximanServices/tds_ecto.git", override: true},
      {:timex, "~> 3.1"},
    ]
  end
end
