Application.ensure_all_started(:mimic)
Application.ensure_all_started(:http_server)
Mimic.copy(:hackney)
ExUnit.start
