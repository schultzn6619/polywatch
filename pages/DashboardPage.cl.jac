import from "@jac/runtime" { jacLogout, useNavigate }
import from ..components.GreetCard { GreetCard }

def:pub page() -> JsxElement {
    navigate = useNavigate();

    def handle_logout() -> None {
        jacLogout();
        navigate("/login");
    }

    return (
        <div className="page">
            <div className="page-container">
                <div className="page-header">
                    <div>
                        <h1>Welcome to Your App</h1>
                        <p className="text-sm text-muted-foreground">Your fullstack Jac project is ready.</p>
                    </div>
                    <button className="btn btn-ghost" onClick={handle_logout}>
                        Sign out
                    </button>
                </div>

                <GreetCard />

                <div className="info-grid">
                    <div className="info-card">
                        <div className="info-icon">{"{ }"}</div>
                        <h3>Build your backend</h3>
                        <p>
                            Define new functions, walkers in
                            <code className="code-inline">services/appService.jac</code>
                        </p>
                    </div>
                    <div className="info-card">
                        <div className="info-icon">{"< >"}</div>
                        <h3>Build your UI</h3>
                        <p>
                            Add pages in
                            <code className="code-inline">pages/</code>,
                            components in
                            <code className="code-inline">components/</code>
                        </p>
                    </div>
                    <div className="info-card">
                        <div className="info-icon">{"~"}</div>
                        <h3>Manage state</h3>
                        <p>
                            Put API logic and shared state in
                            <code className="code-inline">hooks/</code>
                        </p>
                    </div>
                    <div className="info-card">
                        <div className="info-icon">{"*"}</div>
                        <h3>Style it</h3>
                        <p>
                            Edit CSS variables and classes in
                            <code className="code-inline">styles/global.css</code>
                        </p>
                    </div>
                </div>
            </div>
        </div>
    );
}
