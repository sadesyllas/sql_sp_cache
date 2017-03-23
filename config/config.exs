# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# This configuration is loaded before any dependency and is restricted
# to this project. If another project depends on this project, this
# file won't be loaded nor affect the parent project. For this reason,
# if you want to provide default values for your application for
# 3rd-party users, it should be done in your "mix.exs" file.

# You can configure for your application as:
#
#     config :sql_sp_cache, key: :value
#
# And access this configuration in your application as:
#
#     Application.get_env(:sql_sp_cache, :key)
#
# Or configure a 3rd-party app:
#
#     config :logger, level: :info
#

# It is also possible to import configuration files, relative to this
# directory. For example, you can emulate configuration per environment
# by uncommenting the line below and defining dev.exs, test.exs and such.
# Configuration from the imported file will override the ones defined
# here (which is why it is important to import them last).
#
#     import_config "#{Mix.env}.exs"

logger_level = if Mix.env === :prod, do: :info, else: :debug

config :logger,
  backends: [:console],
  compile_time_purge_level: logger_level,
  utc_log: true

config :logger, :console,
  level: logger_level

config :sql_sp_cache, SqlSpCache.Server,
  port: 4416,
  receive_timeout: 5_000,
  log_heartbeats: false

config :sql_sp_cache, SqlSpCache.DB.SQL,
  adapter: Tds.Ecto,
  hostname: "",
  username: "",
  password: "",
  database: "",
  db_query_timeout: 5_000

config :sql_sp_cache, SqlSpCache.Cache.Cleaner,
  cleaning_interval: 10_000
