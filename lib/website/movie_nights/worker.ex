defmodule Portfolio.MovieNights.Worker do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    :ok
  end
end
