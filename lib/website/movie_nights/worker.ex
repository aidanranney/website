defmodule Portfolio.MovieNights.Worker do
  @moduledoc """
  Worker to perform background jobs related to `MovieNight`
  state changes, such as automated reminder and update emails.
  """

  use Oban.Worker

  # TODO - Function to schedule reminder emails to all users with a nomination
  # on a given movie night

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    :ok
  end
end
