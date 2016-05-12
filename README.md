# Greenhouse

Elixir library for access [Greenhouse.io Harvest
API](https://developers.greenhouse.io).

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add greenhouse to your list of dependencies in `mix.exs`:

        def deps do
          [{:greenhouse, "~> 0.0.1"}]
        end

  2. Ensure greenhouse is started before your application:

        def application do
          [applications: [:greenhouse]]
        end

