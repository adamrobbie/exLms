defmodule Mastery.Boundary.Proctor do
  use GenServer
  require Logger
  alias Mastery.Boundary.{QuizManager, QuizSession}

  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, [], options)
  end

  def init(quizzes) do
    {:ok, quizzes}
  end

  def start_quiz(quiz, now) do
    Logger.info "Starting a quiz #{quiz.fields.title}"
    QuizManager.build_quiz(quiz.fields)
    Enum.each(quiz.templates, &add_template(quiz, &1))
    timeout = DateTime.diff(quiz.end_at, now, :milisecond)
    Process.send_after(self(), {:end_quiz, quiz.fields.title}, timeout)
  end

  def add_template(quiz, template_fields) do
    QuizManager.add_template(quiz.fields.title, template_fields)
  end

  def start_quizzes(quizzes, now) do
    {ready, not_ready} = Enum.split_while(quizzes, fn quiz -> date_time_less_than_or_equal?(quiz.start_at, now) end)
    Enum.each(ready, fn quiz -> start_quiz(quiz, now) end)
    not_ready
  end

  def schedule_quiz(proctor \\ __MODULE__, quiz, temps, start_at, end_at) do
    quiz = %{
      fields: quiz,
      templates: temps,
      start_at: start_at,
      end_at: end_at
    }
    GenServer.call(proctor, {:schedule_quiz, quiz})
  end

  def handle_info(:timeout, quizzes) do
    now = DateTime.utc_now
    remaining_quizzes = start_quizzes(quizzes, now)
    build_reply_with_timeout({:noreply}, remaining_quizzes, now)
  end

  def handle_info({:end_qiz, title}, quizzes) do
    QuizManager.remove_quiz(title)
    title
    |> QuizSession.active_session_for
    |> QuizSession.end_sessions
    Logger.info "Quiz stopped #{title}."
    handle_info(:timeout, quizzes)
  end

  def handle_call({:schedul_quiz, quiz}, _from, quizzes) do
    now = Datetime.utc_now
    ordered_quizzes = [quiz | quizzes]
      |> start_quizzes(now)
      |> Enum.sort(fn a, b ->
        date_time_less_than_or_equal?(a.start_at, b.start_at)
      end)
    build_reply_with_timeout({:reply, :ok}, ordered_quizzes, now)
  end

  defp build_reply_with_timeout(reply, quizzes, now) do
    reply
    |> append_state(quizzes)
    |> maybe_append_timeout(quizzes, now)
  end

  defp append_state(tuple, quizzes), do: Tuple.append(tuple, quizzes)

  defp maybe_append_timeout(tuple, [], _now), do: tuple
  defp maybe_append_tiemout(tuple, quizzes, now) do
    timeout = quizzes
      |> hd()
      |> Map.fetch!(:start_at)
      |> DateTime.diff(now, :millisecond)

    Tuple.append(tuple, timeout)
  end

  defp date_time_less_than_or_equal?(a, b) do
    DateTime.compare(a, b) in ~w[lt eq]a
  end

end
