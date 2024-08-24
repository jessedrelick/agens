![Build](https://github.com/jessedrelick/agens/actions/workflows/main.yml/badge.svg)
[![Hexdocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/agens)
[![Hex.pm](https://img.shields.io/hexpm/v/yourrepo.svg)](https://hex.pm/packages/agens)
[![codecov](https://codecov.io/gh/jessedrelick/agens/graph/badge.svg?token=KTJXB4SGCJ)](https://codecov.io/gh/jessedrelick/agens)

# Agens
__Agens__ is an Elixir application designed to build multi-agent workflows with language models.

Drawing inspiration from popular tools in the Python ecosystem, such as [LangChain](https://www.langchain.com/)/[LangGraph](https://www.langchain.com/langgraph) and [CrewAI](https://www.crewai.com/), __Agens__ showcases Elixir’s unique strengths in multi-agent workflows. While the ML/AI landscape is dominated by Python, Elixir’s use of the BEAM virtual machine and OTP (Open Telecom Platform), specifically GenServers and Supervisors, makes it particularly well-suited for these tasks. Agens aims to demonstrate how these inherent design features can be leveraged effectively.

By combining Agens with powerful Elixir libraries like [Bumblebee](https://github.com/elixir-nx/bumblebee) and [Nx.Serving](https://hexdocs.pm/nx/Nx.Serving.html), along with [structured outputs in the OpenAI API](https://openai.com/index/introducing-structured-outputs-in-the-api/) and the continuous improvement of open-source language models, the reliance on Python for multi-agent workflows is significantly reduced. This shift allows Elixir’s concurrency model to truly shine.

> **⚠️ Experimental:** v0.1  
>  
> Agens is currently an experimental project. As of version 0.1, it is primarily a proof-of-concept and learning tool. 
>  
> The next phase of the project focuses on developing real-world examples to uncover potential issues or gaps that the current test suite may not address.  
>  
> These examples are designed to not only help you get started but also to advance Agens towards becoming a production-ready tool, suitable for integration into new or existing Elixir applications.

## Installation
Add `agens` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:agens, "~> 0.1.0"}
  ]
end
```

## Configuration
Future versions of Agens will be configurable by providing options to `Agens.Supervisor` in order to [avoid using application configuration](https://hexdocs.pm/elixir/1.17.2/design-anti-patterns.html#using-application-configuration-for-libraries). For now, however, you can change the Agens `Registry` if needed via config:

```elixir
config :agens, registry: Agens.Registry
```

In addition, you can also override the prompt prefixes:

```elixir
config :agens, prompts: %{
  prompt:
    {"Agent",
      "You are a specialized agent with the following capabilities and expertise"},
  identity:
    {"Identity",
      "You are a specialized agent with the following capabilities and expertise"},
  context: {"Context", "The purpose or goal behind your tasks are to"},
  constraints:
    {"Constraints", "You must operate with the following constraints or limitations"},
  examples:
    {"Examples",
      "You should consider the following examples before returning results"},
  reflection:
    {"Reflection",
      "You should reflect on the following factors before returning results"},
  instructions:
    {"Tool Instructions",
      "You should provide structured output for function calling based on the following instructions"},
  objective: {"Step Objective", "The objective of this step is to"},
  description:
    {"Job Description", "This is part of multi-step job to achieve the following"},
  input:
    {"Input",
      "The following is the actual input from the user, system or another agent"}
}
```

See the [Prompting](#prompting) section below or `Agens.Message` for more information on prompt prefixes.

## Usage
Building a multi-agent workflow with Agens involves a few different steps and core entities:

---
**1. Add the Agens Supervisor to your Supervision tree**

This will start Agens as a supervised process inside your application:

```elixir
Supervisor.start_link(
  [
    {Agens.Supervisor, name: Agens.Supervisor}
  ],
  strategy: :one_for_one
)
```

See `Agens.Supervisor` for more information

---
**2. Start one or more Servings**

A **Serving** is essentially a wrapper for language model inference. It can be an `Nx.Serving` struct, either returned by `Bumblebee` or manually created, or a `GenServer` that interfaces with the OpenAI API or other language model APIs. Technically, due to `GenServer` support, a Serving doesn't need to be limited to language models or machine learning—it can also handle regular API calls.

```elixir
Application.put_env(:nx, :default_backend, EXLA.Backend)
auth_token = System.get_env("HF_AUTH_TOKEN")

my_serving = fn ->
  repo = {:hf, "mistralai/Mistral-7B-Instruct-v0.2", auth_token: auth_token}

  {:ok, model} = Bumblebee.load_model(repo, type: :bf16)
  {:ok, tokenizer} = Bumblebee.load_tokenizer(repo)
  {:ok, generation_config} = Bumblebee.load_generation_config(repo)

  Bumblebee.Text.generation(model, tokenizer, generation_config)
end

serving_config = %Agens.Serving.Config{
  name: :my_serving,
  serving: my_serving()
}

{:ok, pid} = Agens.Serving.start(serving_config)
```

See `Agens.Serving` for more information

---
**3. Create and start one or more Agents**

An **Agent** in the context of Agens is responsible for communicating with Servings and can provide additional context during these interactions.

In practice, Agents typically have their own specialized tasks or capabilities while communicating with the same Serving. Many projects may use a single Serving, such as a language model (LM) or an LM API, but employ multiple Agents to perform different tasks using that Serving. 

Additionally, Agents can use modules implementing the `Agens.Tool` behaviour to extend their capabilities beyond standard LM inference, enabling function-calling and other advanced operations.

```elixir
agent_config = %Agens.Agent.Config{
  name: :my_agent,
  serving: :my_serving
}
{:ok, pid} = Agens.Agent.start(agent_config)
```

See `Agens.Agent` for more information

---
**4. Create and start one or more Jobs**

While Agens is designed to be flexible enough to allow direct communication with an `Agens.Serving` or `Agens.Agent`, its primary goal is to facilitate a multi-agent workflow that uses various steps to achieve a final result. Each step (`Agens.Job.Step`) employs an Agent to accomplish its objective, and the results are then passed to the next step in the **Job**. Conditions can also be used to determine the routing between steps or to conclude the job.

```elixir
job_config = %Agens.Job.Config{
  name: :my_job,
  description: "an example job",
  steps: [
    %Agens.Job.Step{
      agent: :my_agent,
      objective: "first step objective"
    },
    %Agens.Job.Step{
      agent: :my_agent,
      conditions: %{
        "__DEFAULT__" => :end
      }
    }
  ]
}
{:ok, pid} = Agens.Job.start(job_config)
Agens.Job.run(:my_job, "user input")
```

See `Agens.Job` for more information

---

## Prompting
Agens provides a variety of different ways to customize the final prompt sent to the language model (LM) or Serving. A natural language string can be assigned to the entity's specialized field (see below), while `nil` values will omit that field from the final prompt. This approach allows for precise control over the prompt’s content.

All fields with values, in addition to user input, will be included in the final prompt !!!!using the [in-context learning]() method!!!!. The goal should be to balance detailed prompts with efficient token usage by focusing on relevant fields and using concise language. This approach will yield the best results with minimal token usage, keeping costs low and performance high.

### User/Agent
The `input` value is the only required field for building prompts. This value can be the initial value provided to `Agens.Job.run/2`, or the final result of a previous step (`Agens.Job.Step`). Both the `input` and `result` are stored in `Agens.Message`, which can also be used to send messages directly to `Agens.Agent` or `Agens.Serving` without being part of an `Agens.Job`. 

### Job
`Agens.Job.Config` uses the `description` field to configure the prompt for all messages within the Job. This field should be used carefully as it will be sent to the Serving with every prompt.

### Step
`Agens.Job.Step` uses the `objective` field to customize the final prompt sent to the Serving. This can provide more specific information in the final prompt than the Job `description` or Agent `prompt`.

### Agent
`Agens.Agent` provides the most advanced prompt capabilities. The `prompt` field of `Agens.Agent.Config` accepts either a simple string value, or an `Agens.Agent.Prompt` struct. The following fields, which are all optional, can be used with the struct approach:

- `:identity` - a string representing the purpose and capabilities of the agent
- `:context` - a string representing the goal or purpose of the agent's actions
- `:constraints` - a string listing any constraints or limitations on the agent's actions
- `:examples` - a list of maps representing example inputs and outputs for the agent
- `:reflection` - a string representing any additional considerations or reflection the agent should make before returning results

Keep in mind that a single agent can be used across multiple jobs, so it is best to restrict the agent prompt to specific capabilities and use `objective` on `Agens.Job.Step` or `description` on `Agens.Job.Config` for Job or Step-specific prompting.

### Tool
When creating Tools with the `Agens.Tool` behaviour, the `c:Agens.Tool.instructions/0` callback can be used to include specific instructions in the final prompt. These instructions may also include examples, especially for structured output, which can be crucial for designing a Tool that delivers predictable results.

It is important to note that these instructions are provided to the Serving **before** the Tool is used, ensuring that the language model (LM) supplies the correct inputs to the Tool. After receiving these inputs, the Tool should be able to generate the relevant arguments to make the function call, and finally provide the expected output for the next step of the job.

See `Agens.Tool` for more information on using Tools.

### Summary
- **User/Agent**: `input`/`result`
- **Job**: `description`
- **Agent**: `prompt` (`string` or `Agens.Agent.Prompt`)
- **Step**: `objective`
- **Tool**: `instructions`

> **Note:** 
>
> Depending on your use case, some fields may be more relevant than others.
>
> It’s often beneficial to be more descriptive at granular levels, such as the `objective` of `Agens.Job.Step` or the `instructions` for `Agens.Tool`, while taking a more minimal approach with higher-level fields, such as the `description` of `Agens.Job.Config` or the `prompt` of `Agens.Agent.Config`.

## Name
The name Agens comes from the Latin word for 'Agents' or 'Actors.' It also draws from **intellectus agens**, a term in medieval philosophy meaning ['active intellect'](https://en.wikipedia.org/wiki/Active_intellect), which describes the mind’s ability to actively process and abstract information. This reflects the goal of the Agens project: to create intelligent, autonomous agents that manage workflows within the Elixir ecosystem.

## License
This project is licensed under the Apache License, Version 2.0. See the [LICENSE](./LICENSE) file for more details.
