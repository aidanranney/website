defmodule Portfolio.MovieNights.MovieNightNotifier do
  @moduledoc "Basic templates and functions for sending movie night related emails."

  import Swoosh.Email

  alias Portfolio.Mailer
  alias Portfolio.Accounts.User
  alias Portfolio.MovieNights.MovieNight

  @doc """
  Deliver instructions to remind a user of an upcoming movie night  .
  """
  @spec deliver_movie_night_reminder(User.t(), MovieNight.t()) ::
          {:ok, String.t()} | {:error, term()}
  def deliver_movie_night_reminder(%User{} = user, %MovieNight{} = movie_night) do
    deliver(user.email, "You have an upcoming movie night", """

    ==============================

    Hi #{user.email},

    There's an upcoming movie night happening!

    Starts at: #{Calendar.strftime(movie_night.starts_at, "%A, %B %-d at %-I:%M %p")}
    Notes: #{movie_night.note}

    ==============================
    """)
  end

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Aidan Ranney", "noreply@aidanranney.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
end
