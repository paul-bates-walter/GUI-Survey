# AGENTS.md

## Commands
1) The agent should read this file.
2) The agent should read the following:
    * file://./spec.md.
    * file://./tasks/**/*
3) The agent should inspect the runtime environment and verify that it is
    running in Github Codespaces (e.g. env vars CODESPACES=true and
    CODESPACE_NAME are set, and the workspace lives under /workspaces).
    If not running in Github Codespaces, the agent should LOUDLY warn the
    human and advise the human to close the session. This matters because
    the rules and the security model (sandbox removed, GITHUB_TOKEN allowed
    in env) assume the Codespaces container is the isolation boundary.

## Environment
The agent runs inside a Github Codespace on Microsoft Azure hardware.
https://docs.github.com/en/codespaces/about-codespaces/understanding-the-codespace-lifecycle
Persistence (verified against Github Codespaces docs, 2026-07):
    * Stop/restart: everything persists, inside and outside /workspaces.
    * Container rebuild: /workspaces persists, including gitignored and
      untracked files (e.g. target/, build/). /tmp also persists.
      Everything else outside /workspaces (e.g. ~/.claude, ~/.rustup,
      ~/.cargo) is reset to the container image.
    * New codespace (deletion, or auto-delete after 30 days inactive):
      fresh git clone; gitignored/untracked files are gone.
Durable config belongs in git-tracked workspace files
(e.g. ./.claude/settings.json, .devcontainer/devcontainer.json).

Important filesystem paths include:
- ./:
    the main workspace
- ./package.json:
    root helper scripts for local Codex usage.
    Not associated with any of the gui app implementations.
- ./scripts/
    folder for project-scope scripts and other tools
- ./projects/:
    Folder containing GUI app implementations.
- ./projects/<Project>/.gitignore:
    Ignore file to ignore any project-specific files such as the build folder.
- ./projects/<Project>/:
    Root folder for one GUI app implementation.
- ./projects/<Project>/build/:
    flat build folder for build outputs. 
    Give files unique full names 
    (windows-project_name-x64.exe, linux-project_name-arm.deb)
- ./projects/<Project>/scripts/:
    Project helper scripts for project-specific automation.
- ./projects/<Project>/scripts/config_<os>.sh (e.g. config_linux.sh, config_macos.sh;
    Idempotent project setup script for implementation-specific system
    packages, SDKs, and package-manager installs.
- ./projects/<Project>/design/:
    Source code folder for the implementation.

## Rules
Agents are fallible and non-deterministic; however, at the same time, 
closely monitoring agents is counterproductive. Rules exist to allow 
agents to run more autonomously and more safely.
Where possible, these rules should be enforced by the container, the host operating 
system, and or the client (harness). At startup, the agent should try to break each of the below 
rules. Furthermore, every 10th prompt or every hour (whichever happens first), 
the agent should check its previous actions for rule breakages. 
In the event of a rule breakage, the agent must notify a human which rule was broken and how. 
The human must respond with one of:
    1) modifying the rule to be more clear
    2) creating a mechanism to enforce the rule 
    3) making the agent responsible for remembering and following the rule
1 and 2 are preferred. 3 is acceptable if enforcing the rule is not possible or overly 
complicated. If an agent cannot proceed due to the rules, the agent should ask a human 
for help.

Rule 1: {
    Filesystem Rules:
        path: ./.claude/**
        permissions: read
        description:
            ./.claude/settings.json has configuration and permissions that are hot-reloaded 
            when changed. Allow agent reads but not writes (agent should not be able to change own permissions).
}
Rule 2: {
    Minimize the amount of secrets in the container filesystem or environment variables.
    The allowed secrets include:
    id: env.GITHUB_TOKEN
    description:
        injected by github codespaces, short-lived and tightly scoped.
        Cannot make arbitrary requests to github.com
    id: env.GITHUB_CODESPACE_TOKEN
    description:
        injected by github codespaces for codespace-internal auth
        (port forwarding / codespace API). Cannot be removed from
        inside the container.
}

## LLM Hardware
Hardware-agnostic. Let the client choose 
the LLM hardware as it sees fit.

## Models
model: Fable 5 {
    allowed, more expensive and slower than Opus 4.8.
    May or may not be smarter than Opus 4.8.
    May or may not be overall better than Opus 4.8.
}
model: Opus 4.8 {
    allowed, cheaper and faster than Fable 5.
    May or may not be smarter than Fable 5.
    May or may not be overall better than Fable 5.
}

## Clients
client: Claude Code {
    allowed, has nice configurability.
    Its sandbox is not used here; the Github Codespaces container is the
    isolation boundary.
    Github Codespaces will timeout after period of inactivity, killing the process / session.
    Can resume with:
    $ claude --resume
}
client: Codex {}



## Communication
The agent should be concise.
Fluffy language and compliments do not 
add to the meaningfulness of a conversation.

## Documentation
The agent should not write comments, notes, or other documentation.
Humans are more concise and thoughtful than agents and will add comments / notes 
as needed.

## git
The agent should use the existing git branch. A human will handle git commits.
The agent can read git data, but should generally not need to write, create, or 
delete git data.

## Coding Style
Shell scripts are bash-only: bash-isms (e.g. BASH_SOURCE) are allowed.
Invoke scripts with bash, never with sh/dash.
Do not use UNIX shebangs in scripts.
Do not add code comments.
The agent should use a functional style of coding; avoid classes when possible.
Instead of a class that describes an Object, use a function 
that returns an instance of Object. The type / interface provided by 
the Object can be expressed as a type in most cases.
Prefer being explicit over implicit. Avoid implicit default behavior.

### Coding Style (Typescript)
Place import statements at the top of the file.
Place function definitions at the bottom of the file (functions will hoist).

### Coding Style (Rust)
Avoid traits where possible. 
Avoid impls where possible.
Avoid macros where possible.
Prefer explicit impls over macros.
Use explict return statements (even at the end of function blocks).
Do not use the ? operator (try expressions); use explicit match 
or let-else statements.

## Tasks
When working on a task, the agent should move it from 'todo' to 'doing'.
Periodically update the task file with important information 
from the session. Be concise in task file updates.
When human confirms that a task is done, delete the task file.
