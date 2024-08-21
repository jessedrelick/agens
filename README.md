![Build](https://github.com/jessedrelick/agens/actions/workflows/main.yml/badge.svg)
[![Hexdocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/agens)
[![Hex.pm](https://img.shields.io/hexpm/v/yourrepo.svg)](https://hex.pm/packages/agens)
[![codecov](https://codecov.io/gh/jessedrelick/agens/graph/badge.svg?token=KTJXB4SGCJ)](https://codecov.io/gh/jessedrelick/agens)

# Agens
__Agens__ is an Elixir application designed to build multi-agent workflows with language models.

Drawing inspiration from popular tools in the Python ecosystem, such as [LangChain](https://www.langchain.com/)/[LangGraph](https://www.langchain.com/langgraph) and [CrewAI](https://www.crewai.com/), __Agens__ showcases Elixir’s unique strengths in multi-agent workflows. While the ML/AI landscape is dominated by Python, Elixir’s use of the BEAM virtual machine and OTP (Open Telecom Platform), specifically GenServers and Supervisors, makes it particularly well-suited for these tasks. Agens aims to demonstrate how these inherent design features can be leveraged effectively.

By combining Agens with powerful Elixir libraries like [Bumblebee](https://github.com/elixir-nx/bumblebee) and [Nx.Serving](https://hexdocs.pm/nx/Nx.Serving.html), along with [structured outputs in the OpenAI API](https://openai.com/index/introducing-structured-outputs-in-the-api/) and the continuous improvement of open-source language models, the reliance on Python for multi-agent workflows is significantly reduced. This shift allows Elixir’s concurrency model to truly shine.

## Installation
Add `agens` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:agens, "~> 0.1.0"}
  ]
end
```

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

## Example
See `/examples/simple-job.exs` to see how Servings, Agents and Jobs come together to create a cohesive multi-agent workflow.

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
