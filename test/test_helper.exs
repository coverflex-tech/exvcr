Application.ensure_all_started(:mimic)
Application.ensure_all_started(:http_server)
Application.ensure_all_started(:telemetry)
Mimic.copy(:hackney)
ExUnit.start
