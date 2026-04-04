import ".styles.global.css";
import from .pages.LoginPage { page as LoginPage }
import from .pages.DashboardPage { page as DashboardPage }
import from "@jac/runtime" { AuthGuard, Router, Routes, Route, Navigate }

def:pub AuthGuardRoute() -> JsxElement {
    return <>{AuthGuard("/login")}</>;
}

def:pub ClientApp() -> JsxElement {
    return (
        <Router>
            <Routes>
                <Route path="/" element={<Navigate to="/login" replace={True} />} />
                <Route path="/login" element={<LoginPage />} />
                <Route element={<AuthGuardRoute />}>
                    <Route path="/dashboard" element={<DashboardPage />} />
                </Route>
            </Routes>
        </Router>
    );
}
