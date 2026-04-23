# neo-http.nvim

A lightweight HTTP client for Neovim. Write requests in `.http` files and run them without leaving the editor.

> **Status:** Active development — Phase 1 + Phase 2 complete.

---

## Features

- Run HTTP requests from `.http` files with `<leader>hr`
- `curl` (default) or `httpie` backend
- Three-tier variable system: request-scope > file-scope > env file
- Built-in dynamic variables: `{{$timestamp}}`, `{{$uuid}}`, `{{$randomInt}}`, etc.
- Auth helpers: `@auth = basic user:pass` / `@auth = bearer TOKEN`
- Multipart file upload with `file://` references
- SSL control: `@ssl_verify = false`
- URL encoding: `@url_encode = true`
- **Request chaining**: `@capture token = $.token` → use `{{token}}` in next request
- **Cookie jar**: `@cookie_jar = true` persists cookies across requests
- **Response history**: browse past responses with `<leader>hH`
- **Assertions**: `@assert status == 200` with pass/fail display in response buffer
- JSON auto-format + interactive jq filtering
- Syntax highlighting for `.http` files (vim syntax + optional Treesitter)
- Vertical split response buffer with `q` to close

---

## Requirements

| Tool | Role |
|------|------|
| `curl` (default) or `httpie` | Executes requests |
| `jq` | Optional — JSON auto-format + filtering |
| nvim-treesitter + `:TSInstall http` | Optional — richer syntax highlighting |

---

## Installation

### lazy.nvim

```lua
{
  "tauantcamargo/neo-http.vim",
  ft = { "http" },
  opts = {
    backend        = "curl",   -- "curl" | "httpie"
    split_width    = 0.5,      -- response pane width (0.1–0.9)
    env_file       = ".http-client.env.json",
    jq_auto_format = true,
    default_env    = "dev",
  },
  config = function(_, opts)
    require("neo-http").setup(opts)
  end,
}
```

---

## Quick Start

```
1. Create any file:  api.http
2. Write a request   (see format below)
3. <leader>hr        run it
```

The response opens in a vertical split. Press `q` to close it.

---

## Keymaps

Active inside `.http` files. `<leader>hj` also works from the response buffer.

| Key | Action |
|-----|--------|
| `<leader>hr` | Run request under cursor |
| `<leader>hl` | Pick any request in the file |
| `<leader>he` | Switch active environment |
| `<leader>hj` | jq filter (empty input = reset) |
| `<leader>hc` | Copy request as `curl` command |
| `<leader>hH` | Browse response history |
| `<leader>hx` | Clear captured variables |
| `<leader>hC` | Clear cookie jar |
| `q` | Close response buffer |

---

## File Format

```http
# File-level variables
@base_url = https://api.example.com
@token    = my-token

###
# Simple GET
GET {{base_url}}/users
Authorization: Bearer {{token}}

###
# POST with JSON body
POST {{base_url}}/users
Content-Type: application/json
@auth = bearer {{token}}

{
  "name": "Jane Doe",
  "role": "admin"
}

###
# Dynamic variables
GET {{base_url}}/events?after={{$timestamp}}&trace={{$uuid}}

###
# URL-encode query values
@url_encode = true
GET {{base_url}}/search?q=hello world&tag=c++ language

###
# Skip SSL verification
@ssl_verify = false
GET https://localhost:8443/health

###
# Multipart upload
POST {{base_url}}/upload
Content-Type: multipart/form-data

name=Jane Doe
avatar=file://~/Pictures/photo.jpg
```

---

## Variable System

| Priority | Scope | Where |
|----------|-------|-------|
| **1** (highest) | Request block | `@var = value` before the `METHOD` line |
| **2** | Whole file | `@var = value` before the first `###` |
| **3** (lowest) | Environment file | `.http-client.env.json` at project root |

Reference variables with `{{var_name}}`. Unresolved variables show a warning and stay as-is.

---

## Environment File

Create `.http-client.env.json` at your project root:

```json
{
  "dev": {
    "base_url": "http://localhost:3000",
    "token": "dev-token"
  },
  "prod": {
    "base_url": "https://api.example.com",
    "token": "{{$env PROD_API_TOKEN}}"
  }
}
```

`{{$env VAR_NAME}}` reads from your shell — keeps secrets out of committed files.

---

## Request Directives

| Directive | Description |
|-----------|-------------|
| `@url_encode = true` | Percent-encode query string values |
| `@ssl_verify = false` | Skip TLS certificate validation |
| `@auth = basic user:pass` | Injects `Authorization: Basic <base64>` |
| `@auth = bearer TOKEN` | Injects `Authorization: Bearer TOKEN` |

---

## Dynamic Variables

| Variable | Example |
|----------|---------|
| `{{$timestamp}}` | `1745366400` |
| `{{$isoTimestamp}}` | `2026-04-23T10:00:00Z` |
| `{{$uuid}}` | `f47ac10b-58cc-4372-a567-0e02b2c3d479` |
| `{{$guid}}` | same as `$uuid` |
| `{{$randomInt}}` | `742` |
| `{{$randomFloat}}` | `583.142700` |

---

## Request Chaining

Capture a value from a response and use it in subsequent requests:

```http
###
# Step 1 — login and capture token
@capture auth_token = $.token
POST https://api.example.com/login
Content-Type: application/json

{"username": "jane", "password": "secret"}

###
# Step 2 — use captured token automatically
GET https://api.example.com/profile
Authorization: Bearer {{auth_token}}
```

Path syntax: `$.field`, `$.nested.field`, `$.items[0].name`

Clear captured variables with `<leader>hx`.

---

## Cookie Jar

Persist cookies across requests in a session:

```http
###
@cookie_jar = true
POST https://api.example.com/login

###
@cookie_jar = true
GET https://api.example.com/dashboard
```

Cookies are stored at `~/.cache/nvim/neo-http-cookies.txt`. Clear with `<leader>hC`.

---

## Response History

Every request is stored in an in-memory ring buffer (20 entries per request by default).

Press `<leader>hH` to open a two-level picker: choose a request, then choose a past response by timestamp and status code. The selected response is loaded into the response buffer.

Configure with `opts.history_max = 50`.

---

## Assertions

Add pass/fail checks that run after each response:

```http
###
@assert status == 200
@assert body.user.id != null
@assert body.items[0].price > 0
GET https://api.example.com/cart
```

Results appear in the response buffer between the headers and body:

```
Assertions
────────────────────────────────────────
✓ status == 200                          → PASS  (got: 200)
✓ body.user.id != null                   → PASS  (got: 42)
✗ body.items[0].price > 0               → FAIL  (got: nil)
────────────────────────────────────────
```

Supported operators: `==` `!=` `>` `>=` `<` `<=`
Supported targets: `status`, `body.<path>`

---

## License

MIT
