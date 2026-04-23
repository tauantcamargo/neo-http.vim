# neo-http.nvim

A fast, editor-native HTTP client for Neovim.

Write requests in `.http` files, execute them with a keymap, inspect formatted responses in a split, and keep environment variables, captures, assertions, cookies, GraphQL, and WebSocket workflows inside your editor.

## Highlights

- Run HTTP requests from `.http` files with a `curl` or `httpie` backend.
- Work with file, request, environment, captured, and dynamic variables.
- Format JSON, XML, and HTML responses when optional tools are available.
- Filter JSON responses interactively with `jq`.
- Chain requests with `@capture` and validate responses with `@assert`.
- Persist cookies per session with `@cookie_jar = true`.
- Import Postman, Insomnia, and Bruno collections.
- Run GraphQL requests from readable query blocks.
- Open persistent WebSocket consoles from `WS` and `WSS` request blocks.
- Browse in-memory response history and copy requests as `curl`.
- Use built-in Vim syntax highlighting or optional Tree-sitter highlighting.

## Requirements

| Tool | Required | Used for |
|------|----------|----------|
| Neovim 0.10+ | Yes | `vim.system`, `vim.uv`, and modern Lua APIs |
| `curl` or `httpie` | Yes | Request execution |
| `jq` | No | JSON formatting and filtering |
| `websocat` | No | WebSocket connections |
| `xmllint` | No | XML formatting |
| `prettier` | No | HTML formatting |
| `nvim-treesitter` + `:TSInstall http` | No | Richer `.http` highlighting |

## Installation

### lazy.nvim

```lua
{
  "tauantcamargo/neo-http.vim",
  ft = { "http" },
  opts = {
    backend        = "curl",                 -- "curl" | "httpie"
    split_width    = 0.5,                    -- response pane width, 0.1-0.9
    env_file       = ".http-client.env.json",
    default_env    = "dev",
    history_max    = 20,
    jq_auto_format = true,
  },
  config = function(_, opts)
    require("neo-http").setup(opts)
  end,
}
```

## Quick Start

Create `api.http`:

```http
@base_url = https://api.example.com
@token = dev-token

###
# List users
GET {{base_url}}/users
Authorization: Bearer {{token}}

###
# Create user
POST {{base_url}}/users
Content-Type: application/json
@auth = bearer {{token}}

{
  "name": "Jane Doe",
  "role": "admin"
}
```

Open the file in Neovim and press `<leader>hr` with the cursor inside a request block. The response opens in a vertical split. Press `q` to close it.

## Keymaps

Keymaps are active inside `.http` buffers. `<leader>hj` also works from the response buffer after a JSON response.

| Key | Action |
|-----|--------|
| `<leader>hr` | Run request under cursor |
| `<leader>hl` | Select and run a request in the file |
| `<leader>he` | Select the active environment |
| `<leader>hj` | Apply a `jq` filter, or reset with an empty input |
| `<leader>hc` | Copy the current request as a `curl` command |
| `<leader>hH` | Browse response history |
| `<leader>hx` | Clear captured variables |
| `<leader>hC` | Clear the cookie jar |
| `<leader>hi` | Import a Postman, Insomnia, or Bruno collection |
| `<leader>hwm` | Send a WebSocket message |
| `<leader>hwd` | Disconnect a WebSocket session |
| `q` | Close the response or WebSocket buffer |

## Request Format

Requests are separated by `###`. A block can include an optional name comment, request-scoped variables and directives, the request line, headers, and an optional body.

```http
# File-level variables
@base_url = https://api.example.com
@token = my-token

###
# Simple GET
GET {{base_url}}/users
Authorization: Bearer {{token}}

###
# URL-encode query values
@url_encode = true
GET {{base_url}}/search?q=hello world&tag=c++ language

###
# Multipart upload
POST {{base_url}}/upload
Content-Type: multipart/form-data

name=Jane Doe
avatar=file://~/Pictures/photo.jpg
```

Multi-line query parameters are supported:

```http
###
GET {{base_url}}/search
?q=neovim http client
&limit=20
```

## Variables

Variables use `{{name}}` syntax.

| Priority | Source | Example |
|----------|--------|---------|
| 1 | Captured response values | `@capture token = $.token` |
| 2 | Request block | `@token = request-token` |
| 3 | File scope, before the first `###` | `@base_url = https://api.example.com` |
| 4 | Environment file | `.http-client.env.json` |

Unresolved variables stay unchanged and produce a warning.

### Environment Files

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

`{{$env VAR_NAME}}` reads from your shell environment, which keeps secrets out of committed files. Switch environments with `<leader>he`.

### Dynamic Variables

| Variable | Example |
|----------|---------|
| `{{$timestamp}}` | `1745366400` |
| `{{$isoTimestamp}}` | `2026-04-23T10:00:00Z` |
| `{{$uuid}}` | `f47ac10b-58cc-4372-a567-0e02b2c3d479` |
| `{{$guid}}` | same as `$uuid` |
| `{{$randomInt}}` | `742` |
| `{{$randomFloat}}` | `583.142700` |

## Directives

Request directives can be placed before the `METHOD URL` line or in the header section before the blank line.

| Directive | Description |
|-----------|-------------|
| `@auth = basic user:pass` | Inject `Authorization: Basic <base64>` |
| `@auth = bearer TOKEN` | Inject `Authorization: Bearer TOKEN` |
| `@url_encode = true` | Percent-encode query string values |
| `@ssl_verify = false` | Skip TLS certificate validation |
| `@cookie_jar = true` | Persist cookies across requests |

Example:

```http
###
# Inline directives in the header section
POST {{base_url}}/users
Content-Type: application/json
@auth = bearer {{token}}
@ssl_verify = false

{ "name": "Jane Doe" }
```

## Request Chaining

Capture a value from one response and use it in later requests:

```http
###
# Step 1: login and capture token
@capture auth_token = $.token
POST https://api.example.com/login
Content-Type: application/json

{"username": "jane", "password": "secret"}

###
# Step 2: use captured token
GET https://api.example.com/profile
Authorization: Bearer {{auth_token}}
```

Supported capture paths include `$.field`, `$.nested.field`, and `$.items[0].name`. Clear captured variables with `<leader>hx`.

## Assertions

Assertions run after the response returns and are displayed above the response body.

```http
###
@assert status == 200
@assert body.user.id != null
@assert body.items[0].price > 0
GET https://api.example.com/cart
```

Supported operators: `==`, `!=`, `>`, `>=`, `<`, `<=`.

Supported targets: `status` and `body.<path>`.

Example output:

```text
Assertions
────────────────────────────────────────
✓ status == 200                         → PASS  (got: 200)
✓ body.user.id != null                  → PASS  (got: 42)
✗ body.items[0].price > 0               → FAIL  (got: nil)
────────────────────────────────────────
```

## Response Buffer

Responses open in a reusable vertical split with:

- The resolved request line.
- HTTP status, elapsed time, and curl timing breakdown when available.
- Response headers.
- Assertion results.
- Formatted body content when optional formatters are installed.

For curl-backed requests, timing appears in the status line:

```text
HTTP/2 200  [145ms]  dns:12ms  tcp:8ms  ttfb:120ms  total:145ms
```

## JSON, XML, and HTML Formatting

| Content | Behavior |
|---------|----------|
| JSON | Auto-formatted with `jq` when installed, and filterable with `<leader>hj` |
| XML | Auto-formatted with `xmllint` when installed |
| HTML | Auto-formatted with `prettier` when installed |
| Anything else | Shown as raw text |

Formatting degrades to raw output when the optional tool is missing.

## Cookies

Enable the cookie jar per request:

```http
###
@cookie_jar = true
POST https://api.example.com/login

###
@cookie_jar = true
GET https://api.example.com/dashboard
```

Cookies are stored at `~/.cache/nvim/neo-http-cookies.txt`. Clear them with `<leader>hC`.

## Response History

Each request keeps an in-memory ring buffer of past responses. Open it with `<leader>hH`, choose a request, then choose a past response by timestamp and status code.

Configure the limit:

```lua
require("neo-http").setup({
  history_max = 50,
})
```

## Importing Collections

Press `<leader>hi` from any buffer to import an existing collection into `.http` format.

| Source | Supported format |
|--------|------------------|
| Postman | v2.1 JSON collection |
| Insomnia | v4 JSON export |
| Bruno | `.bru` files |

The importer prompts for the source file and output `.http` path, then opens the generated file.

## GraphQL

Mark a request body with `# [graphql]`. Add variables in a `# [variables]` block.

```http
###
POST https://api.example.com/graphql
Content-Type: application/json

# [graphql]
query GetUser($id: ID!) {
  user(id: $id) {
    name
    email
  }
}

# [variables]
{ "id": "123" }
```

The plugin sends a JSON payload shaped as `{"query":"...","variables":{...}}`. `Content-Type: application/json` is injected when missing.

## WebSocket

Use `WS` or `WSS` as the request method:

```http
###
WS wss://echo.websocket.org
Origin: https://echo.websocket.org
```

Press `<leader>hr` to connect. A console buffer opens with incoming and outgoing messages. WebSocket support requires `websocat`.

| Key | Action |
|-----|--------|
| `<leader>hr` | Connect from a `WS` or `WSS` block |
| `<leader>hwm` | Send a message |
| `<leader>hwd` | Disconnect |
| `q` | Close console and disconnect |

## Development

There is no build step or formal test runner. Use Neovim smoke checks when changing the plugin:

```sh
nvim --clean --cmd "set rtp^=$PWD" +"lua require('neo-http').setup()" test.http
nvim --headless --clean --cmd "set rtp^=$PWD" +"lua require('neo-http').setup()" +qa
```

When changing parsing or execution, manually test variables, headers, JSON bodies, GraphQL markers, multipart files, captures, assertions, cookies, SSL flags, and URL encoding.

## License

MIT
