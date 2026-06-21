# Claude CLI for Alfred

Send a prompt to the Claude CLI and render the answer as Markdown — right inside Alfred. No API key needed; requests use your existing Claude CLI login and plan.

## Usage

Type `cla` followed by your prompt, then press Enter:

```
cla explain recursion in one line
```

The prompt is shown on top, followed by Claude's answer.

## Configuration

Open the workflow configuration and set:

- **Claude CLI Path** — path to your `claude` binary (find yours with `which claude`)
- **Model** — the model to use (default `sonnet`)
