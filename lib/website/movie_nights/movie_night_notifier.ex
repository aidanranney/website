defmodule Portfolio.MovieNights.MovieNightNotifier do
  import Swoosh.Email

  alias Portfolio.Mailer
  alias Portfolio.Accounts.User
  alias Portfolio.MovieNights.MovieNight

  @doc """
  Deliver instructions to update a user email.
  """
  @spec deliver_movie_night_reminder(User.t(), MovieNight.t()) ::
          {:ok, String.t()} | {:error, term()}
  def deliver_movie_night_reminder(%User{} = user, %MovieNight{} = movie_night) do
    deliver(user.email, "You have an upcoming movie night", """

    ==============================

    Hi #{user.email},

    There's an upcoming movie night happening!

    Starts at: #{DateTime.to_iso8601(movie_night.starts_at)}
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
