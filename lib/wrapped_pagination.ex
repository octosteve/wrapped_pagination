defmodule Repo do
  defstruct [:current_page, :next_page, :commits]

  def new(%__MODULE__{current_page: current_page}) do
    {:ok, response} = HTTPoison.get(current_page)

    next_page =
      response.headers
      |> Enum.into(%{})
      |> Map.get("Link")
      |> then(fn link ->
        Regex.scan(~r/<(.*)>; rel="next"/, to_string(link), capture: :all_but_first)
      end)
      |> List.flatten()
      |> List.last()

    commits = response.body |> Jason.decode!(keys: :atoms)

    struct!(__MODULE__,
      current_page: current_page,
      next_page: next_page,
      commits: commits
    )
  end

  def new(nwo) do
    current_page = "https://api.github.com/repos/#{nwo}/commits"
    struct!(__MODULE__, current_page: current_page) |> new
  end
end

defimpl Enumerable, for: Repo do
  # Run through reduce/3 to figure it out
  def slice(%Repo{}), do: {:error, __MODULE__}
  # Run through reduce/3 to figure it out
  def count(_repo), do: {:error, __MODULE__}
  # Don't bother
  def member?(_repo, _element), do: {:ok, false}

  def reduce(_repo, {:halt, acc}, _fun), do: {:halted, acc}
  def reduce(repo, {:suspend, acc}, fun), do: {:suspended, acc, &reduce(repo, &1, fun)}

  def reduce(%Repo{commits: [head | tail]} = repo, {:cont, acc}, fun) do
    reduce(%{repo | commits: tail}, fun.(head, acc), fun)
  end

  def reduce(%Repo{commits: [], next_page: nil}, {:cont, acc}, _fun) do
    {:done, acc}
  end

  def reduce(%Repo{commits: [], next_page: next_page} = repo, {:cont, acc}, fun) do
    repo
    |> Map.put(:current_page, next_page)
    |> Repo.new()
    |> reduce({:cont, acc}, fun)
  end
end
