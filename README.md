# Fullstack Starter

A full-stack Jac starter template with user authentication and a working backend function demo.

## Project Structure

```
jactastic/
├── jac.toml                    # Project configuration
├── main.jac                    # Entry point (server + client)
├── services/
│   └── appService.jac          # Server-side functions (add yours here)
├── pages/
│   ├── LoginPage.cl.jac        # Login / signup page
│   └── DashboardPage.cl.jac    # Main dashboard (protected)
├── components/
│   └── GreetCard.cl.jac        # Demo component calling a backend function
├── hooks/                      # Shared state and API logic
├── styles/
│   └── global.css              # CSS variables and component styles
└── index.cl.jac                # Client router
```

## Getting Started

```bash
jac start main.jac
```

Then open your browser to the URL shown in the terminal.

## Features

- **User Authentication** — sign up and log in with username/password
- **Protected Routes** — dashboard requires a valid session via `AuthGuard`
- **Backend Function Demo** — `GreetCard` calls a `def:priv` function on the server
- **Clean Dark Theme** — black and golden orange design ready to customise

## How to Extend

### Add a server function

Open `services/appService.jac` and add a new `def:priv` function:

```jac
def:priv my_function(param: str) -> dict {
    return {"result": "Hello, " + param};
}
```

### Call it from the frontend

Use `sv import` in any `.cl.jac` file:

```jac
sv import from ..services.appService { my_function }

result = await my_function("world");
```

### Add a new page

1. Create `pages/MyPage.cl.jac` with `def:pub page() -> JsxElement { ... }`
2. Add a route in `index.cl.jac`

## Architecture

- **`services/*.jac`** — server-side logic; `def:priv` functions require a valid JWT
- **`pages/*.cl.jac`** — full-page React components, one per route
- **`components/*.cl.jac`** — reusable UI pieces
- **`hooks/*.cl.jac`** — shared state and API logic consumed by components
- **`styles/global.css`** — design tokens (`--primary`, `--background`, etc.) and utility classes
- **`main.jac`** — registers server symbols and mounts the client app
