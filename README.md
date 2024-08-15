![Build](https://github.com/jessedrelick/agens/actions/workflows/main.yml/badge.svg)
[![Hexdocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/agens)
[![Hex.pm](https://img.shields.io/hexpm/v/yourrepo.svg)](https://hex.pm/packages/agens)

# Agens
Agens is used to build multi-agent workflows with language models in Elixir.

It is inspired by many of the popular tools in the Python ecosystem, including [LangChain](https://www.langchain.com/)/[LangGraph](https://www.langchain.com/langgraph), [CrewAI](https://www.crewai.com/) and others. Despite the significant ML/AI Python ecosystem, Elixir is well-suited for multi-agent workflows due to the inherent design of OTP, particularly GenServers and Supervisors, and one of the goals of this library is to demonstrate that. 

Combined with the excellent [`Bumblebee`](https://github.com/elixir-nx/bumblebee) Elixir library, [`Nx.Serving`](https://hexdocs.pm/nx/Nx.Serving.html), [structured outputs in the OpenAI API](https://openai.com/index/introducing-structured-outputs-in-the-api/), and continuous improvement of open-source language models, the need to use Python for multi-agent workflows is reduced, enabling the benefits of Elixir, particularly its concurrency model, to shine through.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `agens` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:agens, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/agens>.

## Usage
Building a multi-agent workflow with Agens involves a few different steps and core entities:

### 1. Add Agens to your Supervision tree

This will start Agens as a supervised process inside your application

### 2. Start one or more Servings (`Agens.Serving`)

A 'Serving' is basically a wrapper for language model inference, and can be a `Nx.Serving` struct, returned by `Bumblebee` or manually created, or a `GenServer` that uses the OpenAI API or other LM APIs. Technically, due to GenServer support, a Serving doesn't even have to be related to language models or machine learning, and can be a regular API call.

### 3. Create and start one or more Agents (`Agens.Agent`)

An Agent in the context of Agens is responsible for communicating with Servings, and can provide additional context when communicating with Servings. In practice, this means Agents will typically have some their own specialized task or capabilities while communicating with the same Serving. Many projects may only have a single Serving, whether that be a LM or LM API, but use multiple Agents for performing different tasks using that single Serving. Agents can also use Tools to provide additional function-calling capabilities beyond standard LM inference.

### 4. Create and start one or more Jobs (`Agens.Job`)

While Agens is designed to be flexible enough where you can communicate directly with a Serving or Agent, the real goal is to create a multi-agent workflow that uses a variety of steps to achieve a final result. Each step (`Agens.Job.Step`) uses an Agent to achieve its objective, and the results of that step are passed to the next step of the Job. Conditions can also be used to route to different Steps of the Job or complete the Job.

See the [Documentation]() for more information.

### Example
See `/examples/simple-job.exs` to see how Servings, Agents and Jobs come together to create a cohesive multi-agent workflow.

### Events
Agens emits a handful events that can be used by the caller via `handle_info/3` for ui, pubsub, logging, persistence and other side-effects.

#### Job
```elixir
{:job_started, job.name}
```

Emitted when a Job has been started

```elixir
{:job_ended, job.name, :completed | {:error, error}}
```

Emitted when a Job has ended, whether it has ended due to completion or error

#### Step
```elixir
{:step_started, {job.name, step_index}, message.input}
```
Emitted when a Step has started. Includes the input data provided to the Step, whether from the user or the previous Step.

```elixir
{:step_result, {job.name, step_index}, message.result}
```
Emitted when a result has been returned from the Serving. Includes the Serving result, which will either be provided to the Tool (if applicable), conditions (if applicable) or the next Step of the Job.

#### Tool
The following events are only emitted if the Agent has a Tool specified in `Agens.Agent.Config`:

```elixir
{:tool_started, {job.name, step_index}, message.result}
```
Emitted when a Tool is about to be called. `message.result` here is the Serving result, and will be overriden by the value returned from the Tool prior to final output.

```elixir
{:tool_raw, {job.name, step_index}, message.raw}
```
Emitted after completing the Tool function call. It provides the raw result of the tool, prior to any post-processing.

```elixir
{:tool_result, {job.name, step_index}, message.result}
```
Emitted after completing post-processing of the raw Tool result. This is the final result of the Tool and this value will be provided to either conditions or the next step of the Job.

### Prompting
Agens provides a variety of different ways to customize the final prompt sent to the LM/Serving. Each entity has a configurable field for customizing the final prompt, whereas `nil` values will omit it from the final prompt entirely. This approach provides significant flexibility for crafting detailed prompts.

Aside from the user input, all configurable fields that have values will be sent as part of the final prompt, using the [in-context learning]() method, so be mindful of token usage when using these fields. The more fields used, and the longer the values, the more expensive the query will be. The goal is to strike a balance between detailed prompts and token usage.

Depending on your use case, some fields may be more useful than others, and it is best to be more descriptive at the granular levels i.e. `Agens.Job.Step.objective` or `Agens.Tool.instructions` and use a more minimal approach with higher-level fields i.e. `Agens.Job.Config.description` or `Agens.Agent.Config.prompt`.

#### User/Agent
The `input` value is the only required field for building prompts. This value can be the initial value provided to `Agens.Job.run/2`, or the final result of a previous step (`Agens.Job.Step`). Both the `input` and `result` are stored on `Agens.Message`, which can also be used to send messages directly to `Agens.Agent` or `Agens.Serving` without being part of an `Agens.Job`. 

#### Job
`Agens.Job.Config` uses the `description` field to configure the prompt for all messages within the Job. This field should be used carefully as it will be sent to the Serving with every prompt 

#### Agent
`Agens.Agent` provides the most advanced prompt capabilities. The `prompt` field of `Agens.Agent.Config` accepts either a simple string value, or an `Agens.Agent.Prompt` struct. The following optional fields can be used with the struct approach:

- `:identity` - a string representing the purpose and capabilities of the agent
- `:context` - a string representing the goal or purpose of the agent's actions
- `:constraints` - a string listing any constraints or limitations on the agent's actions
- `:examples` - a list of maps representing example inputs and outputs for the agent
- `:reflection` - a string representing any additional considerations or reflection the agent should make before returning results

Keep in mind that a single agent can be used across multiple jobs, so it is best to restrict the agent prompt to specific capabilities and use `Agens.Job.Step.objective` or `Agens.Job.Config.description` for Job or Step-specific prompting.

#### Step
`Agens.Job.Step` uses the `objective` field to customize the final prompt sent to the serving. This can provide more specific information in the current prompt than the Job description or Agent prompt.

#### Tool
When using creating Tools with the `Agens.Tool` behaviour, the `instructions/0` callback can be used to add specific instructions in the final prompt for using the Tool. This could also include examples, especially for structured output, which can be crucial for designing a Tool that will provide predictable results.

It is important to note that these instructions will be provided to the serving **before** using the Tool in order to ensure the LM provides the proper inputs to the Tool. These inputs will then be provided to the Tool itself, which should be able to handle the LM response and provide the expected output for the next Step of the Job.

See `Agens.Tool` for more information on using Tools.

#### Future
- future
    - knowledge
    - memory

#### Summary
- User/Agent: input/result
- Job: description
- Agent: prompt
  - identity
  - constraints
  - examples
  - reflection
- Step: objective
- Tool: instructions

## Roadmap

## Name
The name 'Agens' is Latin for 'Agents' or 'Actors'. The term 'intellectus agens' is also popular in medieval philosophy, used to describe the 'active intellect' which is a 


## License